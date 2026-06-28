package cangjie_compiler::chir

import std.collection.*

public class BlockGroupCloneResult {
    public let blocks: ArrayList<Block> = ArrayList<Block>()
    public let returnValue: Option<LocalVar>

    public init(blocks: ArrayList<Block>, returnValue: Option<LocalVar>) {
        for (block in blocks) {
            this.blocks.add(block)
        }
        this.returnValue = returnValue
    }

    public func GetBlocks(): ArrayList<Block> {
        return blocks.clone()
    }

    public func GetReturnValue(): Option<LocalVar> {
        return returnValue
    }
}

public class BlockGroupCopyHelper {
    private let builder: CHIRBuilder

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func CloneBlockGroup(oldBG: BlockGroup, newBG: BlockGroup): BlockGroupCloneResult {
        let newBlocks = CloneBlockGroupInto(oldBG, newBG)
        let valueMap = HashMap<Int64, Value>()
        let newDebugs = ArrayList<Expression>()
        CollectValueMap(oldBG, newBlocks, valueMap, newDebugs)
        BlockGroupCopyHelper.ReplaceExprOperands(newBlocks, valueMap)
        RemoveClonedDebugExpressions(newDebugs)
        return BlockGroupCloneResult(newBlocks, FindClonedReturnValue(oldBG, valueMap))
    }

    public static func ReplaceExprOperands(blocks: ArrayList<Block>, valueMap: HashMap<Int64, Value>): Unit {
        for (block in blocks) {
            ReplaceExprOperandsInBlock(block, valueMap)
        }
    }

    private func CloneBlockGroupInto(oldBG: BlockGroup, newBG: BlockGroup): ArrayList<Block> {
        let newBlocks = ArrayList<Block>()
        for (oldBlock in oldBG.GetBlocks()) {
            let newBlock = CloneBlock(oldBlock, newBG)
            newBlocks.add(newBlock)
            if (let Some(oldEntry) <- oldBG.GetEntryBlock()) {
                if (oldEntry.nodeId == oldBlock.nodeId) {
                    newBG.SetEntryBlock(newBlock)
                }
            }
        }
        return newBlocks
    }

    private func CloneBlock(oldBlock: Block, newBG: BlockGroup): Block {
        let newBlock = builder.CreateBlock(newBG)
        newBlock.AppendAttributeInfo(oldBlock.GetAttributeInfo())
        if (oldBlock.IsLandingPadBlock()) {
            newBlock.SetExceptions(oldBlock.GetExceptions())
        }
        for (expr in oldBlock.GetExpressions()) {
            let clonedExpr = CloneExpression(expr, newBlock)
            clonedExpr.CopyBaseInfoFrom(expr)
            if (let Some(sourceResult) <- expr.GetResult()) {
                if (let Some(clonedResult) <- clonedExpr.GetResult()) {
                    clonedResult.CopyBaseInfoFrom(sourceResult)
                }
            }
        }
        return newBlock
    }

    private func CloneExpression(expr: Expression, parent: Block): Expression {
        if (let Some(lambdaExpr) <- (expr as Lambda)) {
            return CloneLambdaExpression(lambdaExpr, parent)
        }
        if (let Some(forInExpr) <- (expr as ForIn)) {
            return CloneForInExpression(forInExpr, parent)
        }
        return expr.Clone(builder, parent)
    }

    private func CloneLambdaExpression(lambdaExpr: Lambda, parent: Block): Lambda {
        let resultTy = lambdaExpr.GetResult().getOrThrow().GetType().getOrThrow()
        let clonedIdentifier = lambdaExpr.GetIdentifier() + ".cloned${builder.context.GetAllNodesNum()}"
        var clonedLambda: Option<Lambda> = None

        if (let Some(lambdaTy) <- lambdaExpr.GetFuncType()) {
            let newLambda = builder.CreateLambda(resultTy, lambdaTy, parent, isLocalFunc: lambdaExpr.IsLocalFunc(),
                identifier: clonedIdentifier, srcCodeIdentifier: lambdaExpr.GetSrcCodeIdentifier(),
                genericTypeParams: lambdaExpr.GetGenericTypeParams())
            clonedLambda = newLambda
            if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
                let newBody = builder.CreateBlockGroup(lambdaBody.GetIdentifier())
                newLambda.InitBody(newBody)
                CloneBlockGroupInto(lambdaBody, newBody)
            }
        } else if (let Some(lambdaBody) <- lambdaExpr.GetBody()) {
            let newBody = builder.CreateBlockGroup(lambdaBody.GetIdentifier())
            let newLambda = builder.CreateLambda(resultTy, lambdaExpr.GetOperands(), newBody, parent)
            clonedLambda = newLambda
            CloneBlockGroupInto(lambdaBody, newBody)
        }

        if (let Some(newLambdaValue) <- clonedLambda) {
            CloneLambdaParameters(lambdaExpr, newLambdaValue)
            SetClonedLambdaReturnValue(lambdaExpr, newLambdaValue)
            if (lambdaExpr.IsCompileTimeValue()) {
                newLambdaValue.SetCompileTimeValue()
            }
            if (let Some(hostFunc) <- lambdaExpr.GetParamDftValHostFunc()) {
                newLambdaValue.SetParamDftValHostFunc(hostFunc)
            }
            return newLambdaValue
        }
        throw IllegalArgumentException("cannot clone lambda without function type or body")
    }

    private func CloneLambdaParameters(oldLambda: Lambda, newLambda: Lambda): Unit {
        for (oldParam in oldLambda.GetParams()) {
            if (let Some(paramTy) <- oldParam.GetType()) {
                let newParam = builder.CreateParameter(paramTy, INVALID_LOCATION, newLambda)
                newParam.SetSrcCodeIdentifier(oldParam.GetSrcCodeIdentifier())
                newParam.CopyBaseInfoFrom(oldParam)
            } else {
                throw IllegalArgumentException("lambda parameter clone requires a type")
            }
        }
    }

    private func SetClonedLambdaReturnValue(oldLambda: Lambda, newLambda: Lambda): Unit {
        if (let Some(oldReturn) <- oldLambda.GetReturnValue()) {
            if (let Some(oldBody) <- oldLambda.GetBody()) {
                if (let Some(newBody) <- newLambda.GetBody()) {
                    if (let Some(newReturn) <- FindMappedLocalByExprPosition(oldBody, newBody.GetBlocks(), oldReturn)) {
                        newLambda.SetReturnValue(newReturn)
                        return
                    }
                }
            }
            throw IllegalArgumentException("failed to map cloned lambda return value")
        }
    }

    private func CloneForInExpression(forInExpr: ForIn, parent: Block): ForIn {
        let newForIn = match (forInExpr.GetExprKind()) {
            case ExprKind.FORIN_RANGE => builder.CreateForInRange(forInExpr.GetResult().getOrThrow().GetType().getOrThrow(),
                forInExpr.GetInductionVar(), forInExpr.GetLoopCondVar(), parent)
            case ExprKind.FORIN_ITER => builder.CreateForInIter(forInExpr.GetResult().getOrThrow().GetType().getOrThrow(),
                forInExpr.GetInductionVar(), forInExpr.GetLoopCondVar(), parent)
            case ExprKind.FORIN_CLOSED_RANGE => builder.CreateForInClosedRange(forInExpr.GetResult().getOrThrow().GetType().getOrThrow(),
                forInExpr.GetInductionVar(), forInExpr.GetLoopCondVar(), parent)
            case _ => throw IllegalArgumentException("unsupported ForIn expression kind")
        }

        let newBody = builder.CreateBlockGroup(forInExpr.GetBody().GetIdentifier())
        let newLatch = builder.CreateBlockGroup(forInExpr.GetLatch().GetIdentifier())
        let newCond = builder.CreateBlockGroup(forInExpr.GetCond().GetIdentifier())
        newForIn.InitBlockGroups(newBody, newLatch, newCond)
        CloneBlockGroupInto(forInExpr.GetBody(), newBody)
        CloneBlockGroupInto(forInExpr.GetLatch(), newLatch)
        CloneBlockGroupInto(forInExpr.GetCond(), newCond)
        return newForIn
    }

    private static func ReplaceExprOperandsInBlock(block: Block, valueMap: HashMap<Int64, Value>): Unit {
        for (expr in block.GetExpressions()) {
            ReplaceExprOperandsInExpression(expr, valueMap)
        }
    }

    private static func ReplaceExprOperandsInExpression(expr: Expression, valueMap: HashMap<Int64, Value>): Unit {
        if (expr.GetExprKind() != ExprKind.DEBUGEXPR) {
            var idx: Int64 = 0
            while (idx < expr.GetNumOfOperands()) {
                let operand = expr.GetOperand(idx)
                if (let Some(newOperand) <- valueMap.get(operand.nodeId)) {
                    expr.ReplaceOperand(idx, newOperand)
                }
                idx++
            }
            if (let Some(term) <- expr.AsTerminator()) {
                var succIdx: Int64 = 0
                while (succIdx < term.GetNumOfSuccessor()) {
                    let successor = term.GetSuccessor(succIdx)
                    if (let Some(newSuccessorValue) <- valueMap.get(successor.nodeId)) {
                        if (let Some(newSuccessor) <- newSuccessorValue.AsBlock()) {
                            term.ReplaceSuccessor(succIdx, newSuccessor)
                        }
                    }
                    succIdx++
                }
            }
        }

        for (group in expr.GetBlockGroups()) {
            for (block in group.GetBlocks()) {
                ReplaceExprOperandsInBlock(block, valueMap)
            }
        }
    }
}

private func CollectValueMap(oldBG: BlockGroup, newBlocks: ArrayList<Block>, valueMap: HashMap<Int64, Value>,
    newDebugs: ArrayList<Expression>): Unit {
    let oldBlocks = oldBG.GetBlocks()
    if (oldBlocks.size != newBlocks.size) {
        throw IllegalArgumentException("cloned block group block count mismatch")
    }
    var idx: Int64 = 0
    while (idx < oldBlocks.size) {
        CollectValueMap(oldBlocks[idx], newBlocks[idx], valueMap, newDebugs)
        idx++
    }
}

private func CollectValueMap(oldBlock: Block, newBlock: Block, valueMap: HashMap<Int64, Value>,
    newDebugs: ArrayList<Expression>): Unit {
    valueMap[oldBlock.nodeId] = newBlock
    let oldExprs = oldBlock.GetExpressions()
    let newExprs = newBlock.GetExpressions()
    if (oldExprs.size != newExprs.size) {
        throw IllegalArgumentException("cloned block expression count mismatch")
    }
    var idx: Int64 = 0
    while (idx < oldExprs.size) {
        let oldExpr = oldExprs[idx]
        let newExpr = newExprs[idx]
        if (oldExpr.GetExprKind() != newExpr.GetExprKind()) {
            throw IllegalArgumentException("cloned expression kind mismatch")
        }
        if (let Some(oldResult) <- oldExpr.GetResult()) {
            if (let Some(newResult) <- newExpr.GetResult()) {
                valueMap[oldResult.nodeId] = newResult
                if (oldExpr.GetExprKind() == ExprKind.DEBUGEXPR) {
                    newDebugs.add(newExpr)
                }
            } else {
                throw IllegalArgumentException("cloned expression missing result")
            }
        }
        CollectNestedValueMaps(oldExpr, newExpr, valueMap, newDebugs)
        idx++
    }
}

private func CollectNestedValueMaps(oldExpr: Expression, newExpr: Expression, valueMap: HashMap<Int64, Value>,
    newDebugs: ArrayList<Expression>): Unit {
    if (let Some(oldLambda) <- (oldExpr as Lambda)) {
        if (let Some(newLambda) <- (newExpr as Lambda)) {
            CollectLambdaValueMap(oldLambda, newLambda, valueMap, newDebugs)
            return
        }
        throw IllegalArgumentException("cloned lambda expression type mismatch")
    }

    let oldGroupNum = oldExpr.GetNumOfBlockGroups()
    if (oldGroupNum != newExpr.GetNumOfBlockGroups()) {
        if (oldGroupNum == 0 && newExpr.GetNumOfBlockGroups() == 0) {
            return
        }
        throw IllegalArgumentException("cloned expression block group count mismatch")
    }
    var groupIdx: Int64 = 0
    while (groupIdx < oldGroupNum) {
        CollectValueMap(oldExpr.GetBlockGroup(groupIdx), newExpr.GetBlockGroup(groupIdx).GetBlocks(), valueMap,
            newDebugs)
        groupIdx++
    }
}

private func CollectLambdaValueMap(oldLambda: Lambda, newLambda: Lambda, valueMap: HashMap<Int64, Value>,
    newDebugs: ArrayList<Expression>): Unit {
    let oldParams = oldLambda.GetParams()
    let newParams = newLambda.GetParams()
    if (oldParams.size != newParams.size) {
        throw IllegalArgumentException("cloned lambda parameter count mismatch")
    }
    var idx: Int64 = 0
    while (idx < oldParams.size) {
        valueMap[oldParams[idx].nodeId] = newParams[idx]
        idx++
    }
    if (let Some(oldBody) <- oldLambda.GetBody()) {
        if (let Some(newBody) <- newLambda.GetBody()) {
            CollectValueMap(oldBody, newBody.GetBlocks(), valueMap, newDebugs)
            return
        }
        throw IllegalArgumentException("cloned lambda missing body")
    }
}

private func FindClonedReturnValue(oldBG: BlockGroup, valueMap: HashMap<Int64, Value>): Option<LocalVar> {
    var oldReturn: Option<LocalVar> = None
    if (let Some(ownerFunc) <- oldBG.GetOwnerFunc()) {
        oldReturn = ownerFunc.GetReturnValue()
    } else if (let Some(ownerExpr) <- oldBG.GetOwnerExpression()) {
        if (let Some(ownerLambda) <- (ownerExpr as Lambda)) {
            oldReturn = ownerLambda.GetReturnValue()
        }
    }

    if (let Some(oldReturnValue) <- oldReturn) {
        if (let Some(newReturnValue) <- valueMap.get(oldReturnValue.nodeId)) {
            return newReturnValue.AsLocalVar()
        }
    }
    return None
}

private func FindMappedLocalByExprPosition(oldBG: BlockGroup, newBlocks: ArrayList<Block>,
    oldLocal: LocalVar): Option<LocalVar> {
    let oldBlocks = oldBG.GetBlocks()
    var blockIdx: Int64 = 0
    while (blockIdx < oldBlocks.size && blockIdx < newBlocks.size) {
        let oldExprs = oldBlocks[blockIdx].GetExpressions()
        let newExprs = newBlocks[blockIdx].GetExpressions()
        var exprIdx: Int64 = 0
        while (exprIdx < oldExprs.size && exprIdx < newExprs.size) {
            if (let Some(oldResult) <- oldExprs[exprIdx].GetResult()) {
                if (oldResult.nodeId == oldLocal.nodeId) {
                    return newExprs[exprIdx].GetResult()
                }
            }
            exprIdx++
        }
        blockIdx++
    }
    return None
}

private func RemoveClonedDebugExpressions(newDebugs: ArrayList<Expression>): Unit {
    for (debugExpr in newDebugs) {
        if (debugExpr.GetParentBlock().isSome()) {
            debugExpr.RemoveSelfFromBlock()
        }
    }
}
