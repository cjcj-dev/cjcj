package cjcj::chir

import std.collection.*

public class FlatForInExpr {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func RunOnPackage(pkg: Package): Unit {
        for (fn in pkg.GetGlobalFuncsWithBody()) {
            RunOnFunc(fn)
        }
    }

    public func RunOnFunc(fn: Function): Unit {
        let isCommonFunctionWithoutBody = fn.TestAttr(Attribute.COMMON) && fn.GetBody().isNone()
        if (isCommonFunctionWithoutBody) {
            return
        }
        if (fn.TestAttr(Attribute.SKIP_ANALYSIS)) {
            return
        }
        RunOnBlockGroup(fn.GetBody() ??
            throw IllegalStateException("faithful FlatForInExpr expected function body"))
    }

    private func RunOnBlockGroup(blockGroup: BlockGroup): Unit {
        var changed = true
        while (changed) {
            changed = false
            let blocks = blockGroup.GetBlocks()
            for (block in blocks) {
                if (FlattenFirstForInInBlock(block)) {
                    changed = true
                    break
                }
            }
        }
    }

    private func FlattenFirstForInInBlock(block: Block): Bool {
        let exprs = block.GetExpressions()
        var idx: Int64 = 0
        while (idx < exprs.size) {
            let expr = exprs[idx]
            if (let Some(lambdaExpr) <- (expr as Lambda)) {
                if (let Some(body) <- lambdaExpr.GetBody()) {
                    RunOnBlockGroup(body)
                }
                idx++
                continue
            }
            if (let Some(forInExpr) <- (expr as ForIn)) {
                RunOnBlockGroup(forInExpr.GetBody())
                RunOnBlockGroup(forInExpr.GetLatch())
                FlattenForInExpression(forInExpr, block, idx)
                return true
            }
            idx++
        }
        return false
    }

    private func FlattenForInExpression(expr: ForIn, parentBlock: Block, exprIndex: Int64): Unit {
        if (let Some(closedRange) <- (expr as ForInClosedRange)) {
            FlattenForInClosedRange(closedRange, parentBlock, exprIndex)
            return
        }
        let forInSuc = MoveExpressionAfterForIn(parentBlock, exprIndex)
        let parentGroup = expr.GetParentBlockGroup() ??
            throw IllegalStateException("faithful FlatForInExpr expected parent block group")
        let jumpBlock = builder.CreateBlock(parentGroup)
        let loadCondVar = builder.CreateLoad(builder.context.GetBoolTy(), expr.GetLoopCondVar(), jumpBlock)
        let condValue = loadCondVar.GetResult() ??
            throw IllegalStateException("faithful FlatForInExpr load cond has no result")
        let bodyEntry = EntryBlockOf(expr.GetBody(), "for-in body")
        let jumpBr = builder.CreateBranch(condValue, bodyEntry, forInSuc, jumpBlock)
        jumpBr.SetSourceExpr(SourceExpr.FOR_IN_EXPR)

        if (let Some(_) <- (expr as ForInRange)) {
            ReplaceExitWithGoto(expr.GetCond(), jumpBlock)
            ReplaceExitWithGoto(expr.GetBody(), EntryBlockOf(expr.GetLatch(), "for-in latch"))
            ReplaceExitWithGoto(expr.GetLatch(), EntryBlockOf(expr.GetCond(), "for-in cond"))
        } else if (let Some(_) <- (expr as ForInIter)) {
            ReplaceExitWithGoto(expr.GetLatch(), EntryBlockOf(expr.GetCond(), "for-in cond"))
            ReplaceExitWithGoto(expr.GetCond(), EntryBlockOf(expr.GetBody(), "for-in body"))
            ReplaceExitWithGoto(expr.GetBody(), jumpBlock)
        } else {
            throw IllegalArgumentException("faithful FlatForInExpr unsupported ForIn kind: ${ExprKindName(expr.GetExprKind())}")
        }

        let firstEntry = GetEntryBlock(expr)
        let _ = builder.CreateGoTo(firstEntry, parentBlock)
        MoveBlocksToParentBlockGroup(expr)
        expr.ClearBlockGroups()
        expr.RemoveSelfFromBlock()
    }

    private func FlattenForInClosedRange(expr: ForInClosedRange, parentBlock: Block, exprIndex: Int64): Unit {
        let forInSuc = MoveExpressionAfterForIn(parentBlock, exprIndex)
        let firstEntry = GetEntryBlock(expr)
        let _ = builder.CreateGoTo(firstEntry, parentBlock)
        ReplaceExitWithGoto(expr.GetBody(), EntryBlockOf(expr.GetCond(), "for-in cond"))
        let parentGroup = expr.GetParentBlockGroup() ??
            throw IllegalStateException("faithful FlatForInExpr expected parent block group")
        let latchEntryBlock = builder.CreateBlock(parentGroup)
        latchEntryBlock.SetGeneratedFromForIn(true)
        ReplaceExitWithGoto(expr.GetCond(), latchEntryBlock)
        let condValueExpr = builder.CreateLoad(builder.context.GetBoolTy(), expr.GetLoopCondVar(), latchEntryBlock)
        let condValue = condValueExpr.GetResult() ??
            throw IllegalStateException("faithful FlatForInExpr closed-range cond load has no result")
        let _ = builder.CreateBranch(condValue, EntryBlockOf(expr.GetLatch(), "for-in latch"), forInSuc, latchEntryBlock)
        ReplaceExitWithGoto(expr.GetLatch(), EntryBlockOf(expr.GetBody(), "for-in body"))
        MoveBlocksToParentBlockGroup(expr)
        expr.ClearBlockGroups()
        expr.RemoveSelfFromBlock()
    }

    private func MoveExpressionAfterForIn(parentBlock: Block, exprIndex: Int64): Block {
        let parentGroup = parentBlock.GetParentBlockGroup() ??
            throw IllegalStateException("faithful FlatForInExpr parent block has no block group")
        let newSuc = builder.CreateBlock(parentGroup)
        let exprs = parentBlock.GetExpressions()
        let mv = ArrayList<Expression>()
        var idx = exprIndex + 1
        while (idx < exprs.size) {
            mv.add(exprs[idx])
            idx++
        }
        for (expr in mv) {
            expr.MoveTo(newSuc)
        }
        return newSuc
    }

    private func MoveBlocksToParentBlockGroup(expr: ForIn): Unit {
        let parentGroup = expr.GetParentBlockGroup() ??
            throw IllegalStateException("faithful FlatForInExpr expected parent block group")
        for (group in expr.GetExecutionOrder()) {
            let blocks = group.GetBlocks()
            for (block in blocks) {
                block.MoveTo(parentGroup)
            }
        }
    }

    private func ReplaceExitWithGoto(source: BlockGroup, target: Block): Unit {
        for (block in source.GetBlocks()) {
            let term = block.GetTerminator() ??
                throw IllegalStateException("faithful FlatForInExpr source block has no terminator")
            if (term.GetExprKind() == ExprKind.EXIT) {
                let gotoTerm = builder.CreateGoTo(target, block)
                gotoTerm.CopyBaseInfoFrom(term)
                term.RemoveSelfFromBlock()
            }
        }
    }

    private func GetEntryBlock(expr: ForIn): Block {
        let order = expr.GetExecutionOrder()
        if (order.isEmpty()) {
            throw IllegalStateException("faithful FlatForInExpr ForIn has empty execution order")
        }
        return EntryBlockOf(order[0], "for-in first")
    }

    private func EntryBlockOf(blockGroup: BlockGroup, context: String): Block {
        return blockGroup.GetEntryBlock() ??
            throw IllegalStateException("faithful FlatForInExpr ${context} block group has no entry")
    }
}
