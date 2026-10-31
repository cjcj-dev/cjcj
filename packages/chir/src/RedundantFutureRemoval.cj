package cjcj::chir

import std.collection.*

private class RedundantFutureRemovalMatch {
    public let futureValue: LocalVar
    public let apply: Apply
    public let allocation: Allocate

    public init(futureValue: LocalVar, apply: Apply, allocation: Allocate) {
        this.futureValue = futureValue
        this.apply = apply
        this.allocation = allocation
    }
}

public class RedundantFutureRemoval {
    private let chirPackage: Package
    private let isDebug: Bool
    private var executeClosure: Option<Function> = None
    private let appendedGlobalUsers = ArrayList<(Value, Expression)>()

    public init(chirPackage: Package, isDebug!: Bool = false) {
        this.chirPackage = chirPackage
        this.isDebug = isDebug
    }

    public func RunOnPackage(threadNum!: Int64 = 1): Int64 {
        var changed: Int64 = 0
        if (threadNum <= 1 || isDebug) {
            for (fn in chirPackage.GetGlobalFuncsWithBody()) { changed += RunOnFunc(fn) }
            return changed
        }
        let runs = RunFunctionLocalPass<(Int64, ArrayList<(Value, Expression)>)>(
            chirPackage.GetGlobalFuncsWithBody(), threadNum, { fn =>
                let worker = RedundantFutureRemoval(chirPackage)
                (worker.RunOnFunc(fn), worker.appendedGlobalUsers)
            })
        for ((count, users) in runs) {
            changed += count
            for ((value, user) in users) { value.MoveUserToTail(user) }
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
                    if (let Some(spawnExpr) <- (expr as Spawn)) {
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

    private func GetExecureClosureFunc(): Option<Function> {
        for (def in chirPackage.GetAllCustomTypeDef()) {
            if (!IsCoreFuture(def)) {
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

    private func RewriteSpawnWithoutFuture(spawnExpr: Spawn, matched: RedundantFutureRemovalMatch): Unit {
        // CR01: allocated = Allocate(); updated = Future.init(allocated, closure);
        // Spawn(updated). Both receiver values must be unobserved outside this chain.
        let lambdaValue = matched.apply.GetOperand(2)
        if (executeClosure.isNone()) {
            executeClosure = GetExecureClosureFunc()
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
        matched.apply.RemoveSelfFromBlock()
        matched.allocation.GetResult().getOrThrow().ReplaceWith(lambdaValue)
        matched.allocation.RemoveSelfFromBlock()
        spawnExpr.SetExecuteClosure(fn)
    }

    private func CheckSpawnWithFuture(expr: Expression): Option<RedundantFutureRemovalMatch> {
        let spawnExpr = (expr as Spawn) ?? return None
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
        let apply = (producer as Apply) ?? return None
        let callee = (apply.GetCallee() as Function) ?? return None
        let owner = callee.GetParentCustomTypeDef() ?? return None
        if (!ConstructorReturnsReceiver(callee) || !IsCoreFuture(owner) || apply.GetNumOfOperands() != 3) {
            return None
        }
        let lambdaTy = apply.GetOperand(2).GetType() ?? return None
        if (!lambdaTy.IsFunc()) {
            return None
        }
        let allocated = apply.GetOperand(1).AsLocalVar() ?? return None
        let allocationExpr = allocated.GetExpr() ?? return None
        let allocation = (allocationExpr as Allocate) ?? return None
        let allocatedTy = (allocation.GetType() as ClassType) ?? return None
        if (!refEq(allocatedTy.GetClassDef(), owner) || !HasOnlyUserApartFromDebug(allocated, apply)) {
            return None
        }
        return RedundantFutureRemovalMatch(future, apply, allocation)
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
