package cjcj::chir

import std.collection.*

public class RedundantGetOrThrowElimination {
    public init() {}

    public func RunOnPackage(pkg: Package, isDebug!: Bool = false): Int64 {
        var changed: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            changed += RunOnFunc(fn, isDebug: isDebug)
        }
        return changed
    }

    public func RunOnFunc(fn: Function, isDebug!: Bool = false): Int64 {
        let analysis = GetOrThrowResultAnalysis(fn, isDebug: isDebug)
        let result = analysis.Run()
        var changed: Int64 = 0
        if (let Some(body) <- fn.GetBody()) {
            changed += VisitBody(body, result, body, isDebug: isDebug)
        }
        return changed
    }

    private func VisitBody(body: BlockGroup, result: GetOrThrowResultAnalysisResult, scope: BlockGroup,
        isDebug!: Bool): Int64 {
        var changed: Int64 = 0
        for (block in body.GetBlocksRef()) {
            var state = if (let Some(entryState) <- result.GetEntryState(block)) {
                entryState
            } else {
                analysisBottom(result)
            }
            let exprs = block.GetExpressionsRef()
            var idx: Int64 = 0
            while (idx < exprs.size) {
                let expr = exprs[idx]
                if (TryReplaceGetOrThrow(expr, state, scope, isDebug: isDebug)) {
                    changed++
                }
                if (let Some(term) <- expr.AsTerminator()) {
                    ApplyTerminatorEffect(state, term)
                } else {
                    ApplyExpressionEffect(state, expr)
                }
                if (let Some(lambdaExpr) <- (expr as Lambda)) {
                    if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                        changed += VisitBody(lambdaBody, result, scope, isDebug: isDebug)
                    }
                }
                idx++
            }
        }
        return changed
    }

    private func TryReplaceGetOrThrow(expr: Expression, state: GetOrThrowResultDomain, scope: BlockGroup,
        isDebug!: Bool): Bool {
        if (!IsGetOrThrowFunction(expr) || expr.GetNumOfOperands() < 2) {
            return false
        }
        if (let Some(previous) <- state.CheckGetOrThrowResult(expr.GetOperand(1))) {
            if (previous.nodeId == expr.nodeId) {
                return false
            }
            if (let Some(previousResult) <- previous.GetResult()) {
                if (let Some(result) <- expr.GetResult()) {
                    result.ReplaceWith(previousResult, scope)
                    if (isDebug) {
                        println("[RGetOtThrowE] replaced redundant getOrThrow result")
                    }
                    return true
                }
            }
        }
        return false
    }

    private func ApplyExpressionEffect(state: GetOrThrowResultDomain, expr: Expression): Unit {
        if (IsGetOrThrowFunction(expr) && expr.GetNumOfOperands() >= 2) {
            state.UpdateGetOrThrowResult(expr.GetOperand(1), expr)
        }
    }

    private func ApplyTerminatorEffect(state: GetOrThrowResultDomain, term: Terminator): Unit {
        ApplyExpressionEffect(state, term)
    }

    private func analysisBottom(result: GetOrThrowResultAnalysisResult): GetOrThrowResultDomain {
        let map = HashMap<Int64, Int64>()
        for (arg in result.GetTrackedArgs()) {
            map[arg.nodeId] = map.size
        }
        return GetOrThrowResultDomain(map)
    }
}
