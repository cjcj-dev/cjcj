package cangjie_compiler::chir

public class MergeBlocks {
    public init() {}

    public func RunOnPackage(pkg: Package, enableCompileDebug!: Bool = false, enableCoverage!: Bool = false): Int64 {
        var merged: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            merged += RunOnFunction(fn, enableCompileDebug: enableCompileDebug, enableCoverage: enableCoverage)
        }
        return merged
    }

    public func RunOnFunction(fn: Function, enableCompileDebug!: Bool = false, enableCoverage!: Bool = false): Int64 {
        if (let Some(body) <- fn.GetBody()) {
            return RunOnBody(body, enableCompileDebug: enableCompileDebug, enableCoverage: enableCoverage)
        }
        return 0
    }

    public func RunOnBody(body: BlockGroup, enableCompileDebug!: Bool = false, enableCoverage!: Bool = false): Int64 {
        var merged: Int64 = 0
        var changed = true
        while (changed) {
            changed = false
            let blocks = body.GetBlocks()
            for (block in blocks) {
                merged += RunOnNestedLambdas(block, enableCompileDebug: enableCompileDebug,
                    enableCoverage: enableCoverage)
                if (CanMergeIntoPredecessor(block, enableCompileDebug, enableCoverage)) {
                    if (MergeIntoPredecessor(block)) {
                        merged++
                        changed = true
                        break
                    }
                }
                if (CanMergeGotoOnlyBlock(block, enableCompileDebug, enableCoverage)) {
                    if (MergeGotoOnlyBlock(block)) {
                        merged++
                        changed = true
                        break
                    }
                }
            }
        }
        return merged
    }

    private func RunOnNestedLambdas(block: Block, enableCompileDebug!: Bool = false,
        enableCoverage!: Bool = false): Int64 {
        var merged: Int64 = 0
        for (expr in block.GetExpressionsRef()) {
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                    merged += RunOnBody(lambdaBody, enableCompileDebug: enableCompileDebug,
                        enableCoverage: enableCoverage)
                }
            }
        }
        return merged
    }

    private func CanMergeIntoPredecessor(block: Block, enableCompileDebug: Bool, enableCoverage: Bool): Bool {
        if (SkipMergeBlock(block, enableCompileDebug)) {
            return false
        }
        let preds = block.GetPredecessors()
        if (preds.size != 1) {
            return false
        }
        let pred = preds[0]
        if (pred.nodeId == block.nodeId) {
            return false
        }
        let succs = pred.GetSuccessors()
        if (succs.size != 1 || succs[0].nodeId != block.nodeId) {
            return false
        }
        if (let Some(predTerm) <- pred.GetTerminator()) {
            if (predTerm.GetExprKind() != ExprKind.GOTO) {
                return false
            }
            if (enableCompileDebug || enableCoverage) {
                return !predTerm.GetDebugLocation().IsValid()
            }
            return true
        }
        return false
    }

    private func MergeIntoPredecessor(block: Block): Bool {
        let preds = block.GetPredecessors()
        if (preds.size != 1) {
            return false
        }
        let pred = preds[0]
        if (let Some(predTerm) <- pred.GetTerminator()) {
            predTerm.RemoveSelfFromBlock()
        } else {
            return false
        }
        let movingExprs = block.GetExpressions()
        for (expr in movingExprs) {
            expr.MoveTo(pred)
        }
        block.RemoveSelfFromBlockGroup()
        return true
    }

    private func CanMergeGotoOnlyBlock(block: Block, enableCompileDebug: Bool, enableCoverage: Bool): Bool {
        if (block.IsEntry() || block.GetExpressionsNum() != 1 || SkipMergeBlock(block, enableCompileDebug)) {
            return false
        }
        if (let Some(term) <- block.GetTerminator()) {
            if (term.GetExprKind() != ExprKind.GOTO || term.GetSuccessorsRef().size != 1) {
                return false
            }
            for (pred in block.GetPredecessorsRef()) {
                if (pred.nodeId == block.nodeId) {
                    return false
                }
            }
            if (enableCompileDebug || enableCoverage) {
                return !term.GetDebugLocation().IsValid()
            }
            return true
        }
        return false
    }

    private func MergeGotoOnlyBlock(block: Block): Bool {
        if (let Some(term) <- block.GetTerminator()) {
            let succs = term.GetSuccessors()
            if (succs.size != 1) {
                return false
            }
            let target = succs[0]
            let preds = block.GetPredecessors()
            for (pred in preds) {
                if (let Some(predTerm) <- pred.GetTerminator()) {
                    target.SetDebugLocation(block.GetDebugLocation())
                    predTerm.ReplaceSuccessor(block, target)
                }
            }
            term.RemoveSelfFromBlock()
            block.RemoveSelfFromBlockGroup()
            return true
        }
        return false
    }

    private func SkipMergeBlock(block: Block, enableCompileDebug: Bool): Bool {
        if (!enableCompileDebug) {
            return false
        }
        if (let Some(term) <- block.GetTerminator()) {
            return term.GetDebugLocation().IsValid()
        }
        return false
    }
}
