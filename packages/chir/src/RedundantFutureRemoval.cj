package cjcj::chir

import std.collection.*

private class RedundantFutureRemovalMatch {
    public let futureValue: LocalVar
    public let apply: Expression
    public let allocation: AllocateBase

    public init(futureValue: LocalVar, apply: Expression, allocation: AllocateBase) {
        this.futureValue = futureValue
        this.apply = apply
        this.allocation = allocation
    }
}

public class RedundantFutureRemoval {
    private let builder: CHIRBuilder
    private let chirPackage: Package
    private let isDebug: Bool
    private var executeClosure: Option<Function> = None
    private let appendedGlobalUsers = ArrayList<(Value, Expression)>()

    public init(builder: CHIRBuilder, chirPackage: Package, isDebug!: Bool = false) {
        this.builder = builder
        this.chirPackage = chirPackage
        this.isDebug = isDebug
    }

    public func RunOnPackage(threadNum!: Int64 = 1): Int64 {
        var changed: Int64 = 0
        if (threadNum <= 1 || isDebug) {
            for (fn in chirPackage.GetGlobalFuncsWithBody()) { changed += RunOnFunc(fn) }
            return changed
        }
        let runs = RunFunctionLocalPass<(Int64, CHIRBuilder, ArrayList<(Value, Expression)>)>(
            chirPackage.GetGlobalFuncsWithBody(), threadNum, { fn =>
                let localBuilder = CHIRBuilder(builder.context)
                let worker = RedundantFutureRemoval(localBuilder, chirPackage)
                (worker.RunOnFunc(fn), localBuilder, worker.appendedGlobalUsers)
            }, passName: "redundant-future")
        for ((count, localBuilder, users) in runs) {
            changed += count
            for ((value, user) in users) { value.MoveUserToTail(user) }
            localBuilder.MergeAllocatedInstance()
        }
        return changed
    }

    public func RunOnFunc(fn: Function): Int64 {
        if (let Some(body) <- fn.GetBody()) {
            return RunOnBody(body)
        }
        return 0
    }

    private func RunOnBody(body: BlockGroup): Int64 {
        var changed: Int64 = 0
        for (block in body.GetBlocksRef()) {
            let exprs = block.GetExpressions()
            for (expr in exprs) {
                if (expr.GetParentBlock().isNone()) {
                    continue
                }
                if (let Some(matchResult) <- CheckSpawnWithFuture(expr)) {
                    if (let Some(spawnExpr) <- (expr as SpawnBase)) {
                        RewriteSpawnWithoutFuture(spawnExpr, matchResult)
                        changed++
                        if (isDebug) {
                            println("[RedundantFutureRemoval] The call to Spawn" +
                                expr.GetDebugLocation().ToString() +
                                " has been optimised due to redundant future in spawn.")
                        }
                    }
                }
                if (expr.GetParentBlock().isSome()) {
                    for (group in expr.GetBlockGroups()) {
                        changed += RunOnBody(group)
                    }
                }
            }
        }
        return changed
    }

    private func GetExecuteClosureFunc(): Option<Function> {
        for (def in chirPackage.GetAllCustomTypeDef()) {
            if (!IsCoreFuture(def) || def.TestAttr(Attribute.GENERIC_INSTANTIATED)) {
                continue
            }
            for (method in def.GetMethods()) {
                if (method.GetSrcCodeIdentifier() == "executeClosure") {
                    return method
                }
            }
            return None
        }
        return None
    }

    private func ReplaceTerminatorWithGoTo(terminator: Expression, successBlock: Block): Unit {
        let parent = terminator.GetParentBlock().getOrThrow()
        let location = terminator.GetDebugLocation()
        // Removing the terminator drops both predecessor links. Appending GoTo
        // reconnects only the success edge; TrySpawn keeps its exception edge.
        terminator.RemoveSelfFromBlock()
        let goTo = builder.CreateGoTo(successBlock, parent)
        goTo.SetDebugLocation(location)
        parent.AppendExpression(goTo)
    }

    private func RewriteSpawnWithoutFuture(spawnExpr: SpawnBase, matched: RedundantFutureRemovalMatch): Unit {
        // CR01: allocated = Allocate(); updated = Future.init(allocated, closure);
        // Spawn(updated). Both receiver values must be unobserved outside this chain.
        let lambdaValue = matched.apply.GetOperand(2)
        if (executeClosure.isNone()) {
            executeClosure = GetExecuteClosureFunc()
        }
        let fn = executeClosure ??
            throw IllegalArgumentException("cannot find std.core.Future.executeClosure")
        if (lambdaValue.IsGlobal()) {
            for (user in matched.futureValue.GetUsers()) { appendedGlobalUsers.add((lambdaValue, user)) }
            for (user in matched.allocation.GetResult().getOrThrow().GetUsers()) {
                appendedGlobalUsers.add((lambdaValue, user))
            }
        }
        matched.futureValue.ReplaceWith(lambdaValue)
        if (let Some(tryApply) <- (matched.apply as TryApply)) {
            ReplaceTerminatorWithGoTo(tryApply, tryApply.GetSuccessBlock())
        } else {
            matched.apply.RemoveSelfFromBlock()
        }
        matched.allocation.GetResult().getOrThrow().ReplaceWith(lambdaValue)
        if (let Some(tryAllocate) <- (matched.allocation as TryAllocate)) {
            ReplaceTerminatorWithGoTo(tryAllocate, tryAllocate.GetSuccessBlock())
        } else {
            matched.allocation.RemoveSelfFromBlock()
        }
        spawnExpr.SetExecuteClosure(fn)
    }

    private func CheckSpawnWithFuture(expr: Expression): Option<RedundantFutureRemovalMatch> {
        let spawnExpr = (expr as SpawnBase) ?? return None
        if (spawnExpr.IsExecuteClosure()) {
            return None
        }
        let future = spawnExpr.GetFuture().AsLocalVar() ?? return None
        // The constructor is the producer of the updated receiver, not one of
        // its users. A sole non-spawn user can be Future.get(), including get()
        // without a timeout; neither is a constructor or a removable use.
        if (!HasOnlyUserApartFromDebug(future, spawnExpr)) {
            return None
        }
        let producer = future.GetExpr() ?? return None
        if (producer.GetExprKind() != ExprKind.APPLY && producer.GetExprKind() != ExprKind.TRY_APPLY) {
            return None
        }
        let apply = ApplyBase(producer)
        let callee = (apply.GetCallee() as Function) ?? return None
        let owner = callee.GetParentCustomTypeDef() ?? return None
        if (!ConstructorReturnsReceiver(callee) || !IsCoreFuture(owner) || apply.GetOperands().size != 3) {
            return None
        }
        let lambdaTy = producer.GetOperand(2).GetType() ?? return None
        if (!lambdaTy.IsFunc()) {
            return None
        }
        let allocated = producer.GetOperand(1).AsLocalVar() ?? return None
        let allocationExpr = allocated.GetExpr() ?? return None
        let allocation = (allocationExpr as AllocateBase) ?? return None
        let allocatedTy = (allocation.GetType() as ClassType) ?? return None
        if (!refEq(allocatedTy.GetClassDef(), owner) || !HasOnlyUserApartFromDebug(allocated, producer)) {
            return None
        }
        return RedundantFutureRemovalMatch(future, producer, allocation)
    }

}


private func HasOnlyUserApartFromDebug(value: Value, expected: Expression): Bool {
    var found = false
    for (user in value.GetUsers()) {
        if (refEq(user, expected)) {
            found = true
        } else if (user.GetExprKind() != ExprKind.DEBUGEXPR) {
            return false
        }
    }
    return found
}
