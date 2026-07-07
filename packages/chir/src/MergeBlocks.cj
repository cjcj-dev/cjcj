package cangjie_compiler::chir

import std.collection.*
import cangjie_compiler::utils.CJC_ASSERT

extend SkipKind {
    operator func &(right: SkipKind): SkipKind {
        if (this != SkipKind.NO_SKIP) {
            return this
        }
        return right
    }
}

private func CopyBlock(builder: CHIRBuilder, block: Block): Block {
    let blockGroup = block.GetParentBlockGroup() ??
        throw IllegalStateException("MergeBlocks CopyBlock expected parent block group")
    let copiedBlock = builder.CreateBlock(blockGroup)
    let replaceTable = ArrayList<(Value, Value)>()
    let exprs = block.GetExpressions()
    var idx: Int64 = 0
    while (idx < exprs.size) {
        let expr = exprs[idx]
        let cloned = expr.Clone(builder, copiedBlock)
        for ((oldValue, newValue) in replaceTable) {
            cloned.ReplaceOperand(oldValue, newValue)
        }
        if (idx + 1 != exprs.size) {
            replaceTable.add((expr.GetResult().getOrThrow(), cloned.GetResult().getOrThrow()))
        }
        idx++
    }
    return copiedBlock
}

private func MergeForInCondBlock(builder: CHIRBuilder, block: Block): Unit {
    let oldPreds = block.GetPredecessors()
    CJC_ASSERT(!oldPreds.isEmpty())
    var idx: Int64 = 0
    while (idx < oldPreds.size - 1) {
        let copiedBlock = CopyBlock(builder, block)
        let pred = oldPreds[idx]
        pred.GetTerminator().getOrThrow().ReplaceSuccessor(block, copiedBlock)
        idx++
    }
    block.RemoveGeneratedFromForIn()
}

public class MergeBlocks {
    public init() {}

    public func RunOnPackage(pkg: Package, builder: CHIRBuilder, enableCompileDebug!: Bool = false,
        enableCoverage!: Bool = false): Int64 {
        var merged: Int64 = 0
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
                continue
            }
            merged += RunOnFunction(fn, builder, enableCompileDebug: enableCompileDebug, enableCoverage: enableCoverage)
        }
        return merged
    }

    public func RunOnFunction(fn: Function, builder: CHIRBuilder, enableCompileDebug!: Bool = false,
        enableCoverage!: Bool = false): Int64 {
        if (let Some(body) <- fn.GetBody()) {
            return RunOnBody(body, builder, enableCompileDebug: enableCompileDebug, enableCoverage: enableCoverage)
        }
        return 0
    }

    public func RunOnBody(body: BlockGroup, builder: CHIRBuilder, enableCompileDebug!: Bool = false,
        enableCoverage!: Bool = false): Int64 {
        var merged: Int64 = 0
        var changed = true
        while (changed) {
            changed = false
            let blocks = body.GetBlocks()
            for (block in blocks) {
                merged += RunOnNestedLambdas(block, builder, enableCompileDebug: enableCompileDebug,
                    enableCoverage: enableCoverage)
                if (block.GetGeneratedFromForIn()) {
                    MergeForInCondBlock(builder, block)
                    merged++
                    changed = true
                } else if (CanMergeIntoPredecessor(block, enableCompileDebug, enableCoverage)) {
                    if (MergeIntoPredecessor(block)) {
                        merged++
                        changed = true
                    }
                } else if (CanMergeGotoOnlyBlock(block, enableCompileDebug, enableCoverage)) {
                    if (MergeGotoOnlyBlock(block)) {
                        merged++
                        changed = true
                    }
                }
            }
        }
        return merged
    }

    private func RunOnNestedLambdas(block: Block, builder: CHIRBuilder, enableCompileDebug!: Bool = false,
        enableCoverage!: Bool = false): Int64 {
        var merged: Int64 = 0
        for (expr in block.GetExpressionsRef()) {
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                    merged += RunOnBody(lambdaBody, builder, enableCompileDebug: enableCompileDebug,
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
            var appendSkipCheck = pred.GetSkipCheck() & predTerm.GetSkipCheck()
            predTerm.RemoveSelfFromBlock()
            for (expr in block.GetExpressions()) {
                expr.MoveTo(pred)
            }
            appendSkipCheck = appendSkipCheck & block.GetSkipCheck()
            block.RemoveSelfFromBlockGroup()
            if (appendSkipCheck != SkipKind.NO_SKIP) {
                pred.SetSkipCheck(appendSkipCheck)
            }
        } else {
            return false
        }
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
                    let skip = predTerm.GetSkipCheck() & block.GetSkipCheck()
                    if (skip != SkipKind.NO_SKIP) {
                        predTerm.SetSkipCheck(skip)
                    }
                }
            }
            term.RemoveSelfFromBlock()
            block.RemoveSelfFromBlockGroup()
            return true
        }
        return false
    }

    private func SkipMergeBlock(block: Block, enableCompileDebug: Bool): Bool {
        if (block.TestAttr(Attribute.UNREACHABLE)) {
            return true
        }
        if (!enableCompileDebug) {
            return false
        }
        if (let Some(term) <- block.GetTerminator()) {
            return term.GetDebugLocation().IsValid()
        }
        return false
    }
}
