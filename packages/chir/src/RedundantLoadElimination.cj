package cangjie_compiler::chir

import std.collection.*

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
        if (let Some(body) <- fn.GetBody()) {
            let analysis = ReachingDefinitionAnalysis(fn)
            let result = analysis.Run()
            return RunOnBody(body, analysis, result, isDebug) + RunLocalFallbackOnBody(body, isDebug)
        }
        return 0
    }

    private func RunOnBody(body: BlockGroup, analysis: ReachingDefinitionAnalysis, result: ReachingDefinitionResult,
        isDebug: Bool): Int64 {
        var changed: Int64 = 0
        for (block in body.GetBlocksRef()) {
            changed += RunOnBlock(block, body, analysis, result, isDebug)
            for (expr in block.GetExpressions()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        changed += RunOnBody(lambdaBody, analysis, result, isDebug)
                    }
                }
            }
        }
        return changed
    }

    private func RunOnBlock(block: Block, scope: BlockGroup, analysis: ReachingDefinitionAnalysis,
        result: ReachingDefinitionResult, isDebug: Bool): Int64 {
        var changed: Int64 = 0
        let state = if (let Some(entryState) <- result.GetEntryState(block)) { entryState } else { analysis.Bottom() }
        let exprs = block.GetExpressions()
        for (expr in exprs) {
            if (expr.GetParentBlock().isNone()) {
                continue
            }
            if (let Some(term) <- expr.AsTerminator()) {
                analysis.PropagateTerminatorEffect(state, term)
            } else {
                analysis.PropagateExpressionEffect(state, expr)
            }
            if (expr.GetParentBlock().isSome() && expr.GetExprKind() == ExprKind.LOAD && expr.GetNumOfOperands() == 1) {
                if (TryReplaceLoad(expr, state, scope, isDebug)) {
                    changed++
                }
            }
        }
        return changed
    }

    private func TryReplaceLoad(loadExpr: Expression, state: ReachingDefinitionDomain, scope: BlockGroup,
        isDebug: Bool): Bool {
        let location = loadExpr.GetOperand(0)
        if (let Some(storeExpr) <- state.CheckReachingDef(location)) {
            if (storeExpr.GetNumOfOperands() >= 1) {
                let storedValue = storeExpr.GetOperand(0)
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

    private func RunLocalFallbackOnBody(body: BlockGroup, isDebug: Bool): Int64 {
        var changed: Int64 = 0
        for (block in body.GetBlocksRef()) {
            changed += RunLocalFallbackOnBlock(block, body, isDebug)
            for (expr in block.GetExpressions()) {
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        changed += RunLocalFallbackOnBody(lambdaBody, isDebug)
                    }
                }
            }
        }
        return changed
    }

    private func RunLocalFallbackOnBlock(block: Block, scope: BlockGroup, isDebug: Bool): Int64 {
        let knownStores = HashMap<Int64, Value>()
        var changed: Int64 = 0
        let exprs = block.GetExpressions()
        for (expr in exprs) {
            if (expr.GetParentBlock().isNone()) {
                continue
            }
            if (expr.GetExprKind() == ExprKind.LOAD && expr.GetNumOfOperands() == 1) {
                let location = expr.GetOperand(0)
                if (let Some(value) <- knownStores.get(location.nodeId)) {
                    if (ReplaceLoad(expr, value, scope, isDebug)) {
                        changed++
                    }
                }
                continue
            }
            if (expr.GetExprKind() == ExprKind.STORE && expr.GetNumOfOperands() >= 2) {
                let value = expr.GetOperand(0)
                let location = expr.GetOperand(1)
                knownStores[location.nodeId] = value
                continue
            }
            if (MayInvalidateStoredLocations(expr)) {
                knownStores.clear()
            }
        }
        return changed
    }

    private func ReplaceLoad(loadExpr: Expression, value: Value, scope: BlockGroup, isDebug: Bool): Bool {
        if (let Some(result) <- loadExpr.GetResult()) {
            result.ReplaceWith(value, scope)
            loadExpr.RemoveSelfFromBlock()
            if (isDebug) {
                println("[RLE] replaced Load " + loadExpr.GetDebugLocation().ToString() +
                    " with " + value.GetIdentifier() + ".")
            }
            return true
        }
        return false
    }

    private func MayInvalidateStoredLocations(expr: Expression): Bool {
        if (expr.IsTerminator() || expr.HasExceptionBranch()) {
            return true
        }
        let kind = expr.GetExprKind()
        if (kind == ExprKind.CONSTANT || kind == ExprKind.DEBUGEXPR || kind == ExprKind.LOAD ||
            kind == ExprKind.NEG || kind == ExprKind.NOT || kind == ExprKind.BITNOT ||
            kind == ExprKind.ADD || kind == ExprKind.SUB || kind == ExprKind.MUL || kind == ExprKind.DIV ||
            kind == ExprKind.MOD || kind == ExprKind.EXP || kind == ExprKind.LSHIFT ||
            kind == ExprKind.RSHIFT || kind == ExprKind.BITAND || kind == ExprKind.BITOR ||
            kind == ExprKind.BITXOR || kind == ExprKind.LT || kind == ExprKind.GT ||
            kind == ExprKind.LE || kind == ExprKind.GE || kind == ExprKind.EQUAL ||
            kind == ExprKind.NOTEQUAL || kind == ExprKind.AND || kind == ExprKind.OR ||
            kind == ExprKind.TUPLE || kind == ExprKind.FIELD || kind == ExprKind.FIELD_BY_NAME ||
            kind == ExprKind.INSTANCEOF || kind == ExprKind.TYPECAST || kind == ExprKind.GET_EXCEPTION ||
            kind == ExprKind.GET_RTTI || kind == ExprKind.GET_RTTI_STATIC) {
            return false
        }
        if (expr.IsFuncCall()) {
            return true
        }
        return true
    }
}
