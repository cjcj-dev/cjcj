package cjcj::chir

import std.collection.*

private func ModifyApplyCalleeInfo(loadResult: LocalVar, storeValue: Value): Unit {
    if (!storeValue.IsFunc()) {
        return
    }
    let funcBase = storeValue.AsFunction().getOrThrow()
    if (!funcBase.IsMemberFunc() || !funcBase.TestAttr(Attribute.STATIC)) {
        return
    }
    let thisType = funcBase.GetParentCustomTypeOrExtendedType().getOrThrow()
    let oldUsers = loadResult.GetUsers()
    for (user in oldUsers) {
        if (user.GetExprKind() == ExprKind.APPLY) {
            let apply = (user as Apply).getOrThrow()
            apply.SetThisType(thisType)
        }
        if (user.GetExprKind() == ExprKind.APPLY_WITH_EXCEPTION) {
            let apply = (user as ApplyWithException).getOrThrow()
            apply.SetThisType(thisType)
        }
    }
}

public class RedundantLoadElimination {
    public init() {}

    public func RunOnPackage(pkg: Package, isDebug!: Bool = false): Int64 {
        var changed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            changed += RunOnFunction(fn, isDebug: isDebug)
        }
        return changed
    }

    public func RunOnFunction(fn: Function, isDebug!: Bool = false): Int64 {
        if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
            return 0
        }
        if (let Some(body) <- fn.GetBody()) {
            let analysis = ReachingDefinitionAnalysis(fn)
            let result = Engine<ReachingDefinitionDomain>(fn, analysis).IterateToFixpoint() ?? return 0
            let toBeRemoved = ArrayList<Expression>()
            result.VisitWith(
                { _: ReachingDefinitionDomain, _: Expression, _: Int64 => () },
                { state: ReachingDefinitionDomain, expr: Expression, _: Int64 =>
                    if (expr.GetParentBlock().isSome() && expr.GetExprKind() == ExprKind.LOAD &&
                        expr.GetNumOfOperands() == 1) {
                        if (TryReplaceLoad(expr, state, body, isDebug)) {
                            toBeRemoved.add(expr)
                        }
                    }
                },
                { _: ReachingDefinitionDomain, _: Terminator, _: Option<Block> => () }
            )
            for (expr in toBeRemoved) {
                if (expr.GetParentBlock().isSome()) {
                    expr.RemoveSelfFromBlock()
                }
            }
            return toBeRemoved.size
        }
        return 0
    }

    private func TryReplaceLoad(loadExpr: Expression, state: ReachingDefinitionDomain, scope: BlockGroup,
        isDebug: Bool): Bool {
        let location = loadExpr.GetOperand(0)
        if (let Some(storeExpr) <- state.CheckReachingDef(location)) {
            if (storeExpr.GetNumOfOperands() >= 1) {
                let storedValue = storeExpr.GetOperand(0)
                ModifyApplyCalleeInfo(loadExpr.GetResult().getOrThrow(), storedValue)
                if (ReplaceLoad(loadExpr, storedValue, scope, isDebug)) {
                    return true
                }
            }
        }
        if (let Some(validLoad) <- state.CheckReachingLoadDef(location)) {
            if (validLoad.nodeId == loadExpr.nodeId) {
                return false
            }
            if (let Some(validResult) <- validLoad.GetResult()) {
                if (ReplaceLoad(loadExpr, validResult, scope, isDebug)) {
                    return true
                }
            }
        }
        return false
    }

    private func ReplaceLoad(loadExpr: Expression, value: Value, scope: BlockGroup, isDebug: Bool): Bool {
        if (let Some(result) <- loadExpr.GetResult()) {
            result.ReplaceWith(value, scope)
            if (isDebug) {
                println("[RLE] replaced Load " + loadExpr.GetDebugLocation().ToString() +
                    " with " + value.GetIdentifier() + ".")
            }
            return true
        }
        return false
    }
}
