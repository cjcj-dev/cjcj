package cangjie_compiler::chir

import std.collection.*

private class RedundantFutureRemovalMatch {
    public let futureValue: LocalVar
    public let apply: Apply

    public init(futureValue: LocalVar, apply: Apply) {
        this.futureValue = futureValue
        this.apply = apply
    }
}

public class RedundantFutureRemoval {
    private let chirPackage: Package
    private let isDebug: Bool
    private var executeClosure: Option<Function> = None

    public init(chirPackage: Package, isDebug!: Bool = false) {
        this.chirPackage = chirPackage
        this.isDebug = isDebug
    }

    public func RunOnPackage(): Int64 {
        var changed: Int64 = 0
        for (fn in chirPackage.GetGlobalFuncsWithBody()) {
            changed += RunOnFunc(fn)
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
                        RewriteSpawnWithoutFuture(spawnExpr, matchResult.futureValue, matchResult.apply)
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

    private func RewriteSpawnWithoutFuture(spawnExpr: Spawn, futureValue: LocalVar, apply: Apply): Unit {
        if (apply.GetNumOfOperands() <= 2) {
            throw IllegalArgumentException("redundant future rewrite requires Future init lambda operand")
        }
        let lambdaValue = apply.GetOperand(2)
        if (let Some(lambdaTy) <- lambdaValue.GetType()) {
            if (!lambdaTy.IsFunc()) {
                throw IllegalArgumentException("redundant future rewrite requires a closure operand")
            }
        } else {
            throw IllegalArgumentException("redundant future rewrite requires typed closure operand")
        }

        let futureExpression = if (let Some(expr) <- futureValue.GetExpr()) {
            expr
        } else {
            throw IllegalArgumentException("redundant future rewrite requires future defining expression")
        }
        let scope = spawnExpr.GetParentBlockGroup()
        apply.RemoveSelfFromBlock()
        futureValue.ReplaceWith(lambdaValue, scope)
        futureExpression.RemoveSelfFromBlock()

        if (executeClosure.isNone()) {
            executeClosure = GetExecureClosureFunc()
        }
        if (let Some(fn) <- executeClosure) {
            spawnExpr.SetExecuteClosure(fn)
        } else {
            throw IllegalArgumentException("cannot find std.core.Future.executeClosure")
        }
    }

    private func CheckSpawnWithFuture(expr: Expression): Option<RedundantFutureRemovalMatch> {
        if (expr.GetExprKind() != ExprKind.SPAWN) {
            return None
        }
        let spawnExpr = if (let Some(spawnValue) <- (expr as Spawn)) {
            spawnValue
        } else {
            return None
        }
        if (spawnExpr.IsExecuteClosure()) {
            return None
        }
        let localFuture = if (let Some(local) <- spawnExpr.GetFuture().AsLocalVar()) {
            local
        } else {
            return None
        }
        let usersSet = UniqueUsers(localFuture.GetUsers())
        if (usersSet.size == 3) {
            RemoveDebugUser(usersSet)
        }
        if (usersSet.size == 2) {
            RemoveExpressionById(usersSet, spawnExpr.nodeId)
        }
        if (usersSet.size != 1) {
            return None
        }
        if (let Some(apply) <- (usersSet[0] as Apply)) {
            return RedundantFutureRemovalMatch(localFuture, apply)
        }
        return None
    }
}

private func IsCoreFuture(def: CustomTypeDef): Bool {
    return def.GetPackageName() == "std.core" && def.GetSrcCodeIdentifier() == "Future"
}

private func UniqueUsers(users: ArrayList<Expression>): ArrayList<Expression> {
    let out = ArrayList<Expression>()
    for (user in users) {
        if (!ContainsExpression(out, user)) {
            out.add(user)
        }
    }
    return out
}

private func RemoveDebugUser(users: ArrayList<Expression>): Unit {
    var idx: Int64 = 0
    while (idx < users.size) {
        if (users[idx].GetExprKind() == ExprKind.DEBUGEXPR) {
            users.remove(at: idx)
            return
        }
        idx++
    }
}
