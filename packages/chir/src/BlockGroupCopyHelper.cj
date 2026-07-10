package cjcj::chir

import std.collection.*
import cjcj::utils.CJC_ASSERT

public class BlockGroupCopyHelper {
    private let builder: CHIRBuilder
    private var instMap: HashMap<Int64, Type> = HashMap<Int64, Type>()
    private var thisType: Option<Type> = None

    public init(builder: CHIRBuilder) {
        this.builder = builder
    }

    public func CloneBlockGroup(oldBG: BlockGroup, newBG: BlockGroup): (ArrayList<Block>, Option<LocalVar>) {
        let newBlocks = ArrayList<Block>()
        for (block in oldBG.GetBlocks()) {
            newBlocks.add(block.Clone(builder, newBG))
        }
        InstBlockGroup(newBlocks)
        let valueMap = HashMap<Int64, Value>()
        let newDebugs = ArrayList<Expression>()
        CollectValueMap(oldBG, newBlocks, valueMap, newDebugs)
        BlockGroupCopyHelper.ReplaceExprOperands(newBlocks, valueMap)
        RemoveClonedDebugExpressions(newDebugs)
        return (newBlocks, FindClonedReturnValue(oldBG, valueMap))
    }

    public func GetInstMapFromApply(apply: Apply,
        newBodyOuterFunction!: Option<Function> = None): Unit {
        if (let Some(localCallee) <- apply.GetCallee().AsLocalVar()) {
            let lambda = (localCallee.GetExpr().getOrThrow() as Lambda).getOrThrow()
            let instantiatedTypeArgs = apply.GetInstantiatedTypeArgs()
            var index: Int64 = 0
            for (genericType in lambda.GetGenericTypeParams()) {
                if (!instMap.contains(genericType.objectId)) {
                    instMap[genericType.objectId] = instantiatedTypeArgs[index]
                }
                index++
            }
            thisType = builder.context.GetThisTy()
        } else {
            let calleeFunction = apply.GetCallee().AsFunction().getOrThrow()
            let customDef = calleeFunction.GetParentCustomTypeDef()
            if (let Some(customDefValue) <- customDef) {
                if (customDefValue.IsGenericDef()) {
                    var instParentCustomType = GetInstParentCustomTyOfCallee(apply.GetCallee(), apply.GetArgs(),
                        apply.GetThisType(), builder)
                    if (instParentCustomType.isNone()) {
                        if (let Some(extendDef) <- (customDefValue as ExtendDef)) {
                            instParentCustomType = extendDef.GetExtendedType()
                        } else {
                            instParentCustomType = customDefValue.GetType()
                        }
                    }
                    let strippedInstParentCustomType = instParentCustomType.getOrThrow().StripAllRefs()
                    if (let Some(extendDef) <- (customDefValue as ExtendDef)) {
                        let newMap = extendDef.GetExtendedType().getOrThrow().CalculateGenericTyMapping(
                            strippedInstParentCustomType)
                        CJC_ASSERT(newMap[0])
                        for ((key, value) in newMap[1]) {
                            if (!instMap.contains(key)) {
                                instMap[key] = value
                            }
                        }
                    } else {
                        instMap = GetInstMapFromCurDefToCurType(
                            (strippedInstParentCustomType as CustomType).getOrThrow())
                    }
                }
            }
            let instantiatedTypeArgs = apply.GetInstantiatedTypeArgs()
            var index: Int64 = 0
            for (genericType in calleeFunction.GetGenericTypeParams()) {
                if (!instMap.contains(genericType.objectId)) {
                    instMap[genericType.objectId] = instantiatedTypeArgs[index]
                }
                index++
            }
            let outerDef = match (newBodyOuterFunction) {
                case Some(outerFunction) => outerFunction.GetParentCustomTypeDef()
                case None => apply.GetTopLevelFunc().getOrThrow().GetParentCustomTypeDef()
            }
            if (let Some(customDefValue) <- customDef) {
                if (let Some(outerDefValue) <- outerDef) {
                    if (customDefValue.nodeId == outerDefValue.nodeId) {
                        thisType = builder.context.GetThisTy()
                    } else {
                        thisType = apply.GetThisType()
                    }
                } else {
                    thisType = apply.GetThisType()
                }
            } else {
                thisType = apply.GetThisType()
            }
        }
    }

    private func InstBlockGroup(blocks: ArrayList<Block>): Unit {
        let genericConverter = GenericTypeConvertor(instMap, builder)
        let convertFunc: ConvertTypeFunc = { ty =>
            if (let Some(concreteThisType) <- thisType) {
                let replaced = ReplaceThisTypeToConcreteType(ty, concreteThisType, builder)
                if (!refEq(replaced, ty)) {
                    return replaced
                }
            }
            return genericConverter.ConvertToInstantiatedType(ty)
        }
        let converter = PrivateTypeConverterNoInvokeOriginal(convertFunc, builder)
        let preVisit: VisitExprActionFunc = { expr =>
            converter.VisitExpr(expr)
            return VisitResult.CONTINUE
        }
        for (block in blocks) {
            Visitor.Visit(block, preVisit)
        }
    }

    public static func ReplaceExprOperands(blocks: ArrayList<Block>, valueMap: HashMap<Int64, Value>): Unit {
        for (block in blocks) {
            ReplaceExprOperandsInBlock(block, valueMap)
        }
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

public func FixCastProblemAfterInst(blocks: ArrayList<Block>, builder: CHIRBuilder): Unit {
    let preVisit: VisitExprActionFunc = { expr =>
        if (expr.GetExprKind() == ExprKind.INSTANCEOF) {
            let instance = (expr as InstanceOf).getOrThrow()
            let objectType = instance.GetObject().GetType().getOrThrow()
            if (objectType.IsGenericRelated() ||
                (objectType.IsRef() && (objectType as RefType).getOrThrow().GetBaseType().IsClass()) ||
                instance.GetType().IsGenericRelated()) {
                return VisitResult.CONTINUE
            }
            if (objectType.IsEqualOrSubTypeOf(instance.GetType(), builder)) {
                let trueExpr = builder.CreateConstant(builder.context.GetBoolTy(), BoolLiteral(true),
                    expr.GetParentBlock().getOrThrow())
                expr.ReplaceWith(trueExpr)
            } else {
                let falseExpr = builder.CreateConstant(builder.context.GetBoolTy(), BoolLiteral(false),
                    expr.GetParentBlock().getOrThrow())
                expr.ReplaceWith(falseExpr)
            }
        } else if (expr.GetExprKind() == ExprKind.TRANSFORM_TO_CONCRETE) {
            let cast = (expr as TransformToConcrete).getOrThrow()
            if (!cast.GetSourceTy().getOrThrow().IsGenericRelated()) {
                let sourceValue = cast.GetSourceValue()
                let newCast = TypeCastOrBoxIfNeeded(sourceValue, cast.GetTargetTy().getOrThrow(), builder,
                    expr.GetParentBlock().getOrThrow(), expr.GetDebugLocation())
                if (refEq(newCast, sourceValue)) {
                    for (user in expr.GetResult().getOrThrow().GetUsers()) {
                        user.ReplaceOperand(expr.GetResult().getOrThrow(), sourceValue)
                    }
                    expr.RemoveSelfFromBlock()
                    return VisitResult.CONTINUE
                }
                for (user in expr.GetResult().getOrThrow().GetUsers()) {
                    user.ReplaceOperand(expr.GetResult().getOrThrow(), newCast)
                }
                newCast.AsLocalVar().getOrThrow().GetExpr().getOrThrow().MoveBefore(expr)
                expr.RemoveSelfFromBlock()
            }
        } else if (expr.GetExprKind() == ExprKind.TRANSFORM_TO_GENERIC) {
            let cast = (expr as TransformToGeneric).getOrThrow()
            if (!cast.GetTargetTy().getOrThrow().IsGenericRelated()) {
                let sourceValue = cast.GetSourceValue()
                let newCast = TypeCastOrBoxIfNeeded(sourceValue, cast.GetTargetTy().getOrThrow(), builder,
                    expr.GetParentBlock().getOrThrow(), expr.GetDebugLocation())
                if (refEq(newCast, sourceValue)) {
                    for (user in expr.GetResult().getOrThrow().GetUsers()) {
                        user.ReplaceOperand(expr.GetResult().getOrThrow(), sourceValue)
                    }
                    expr.RemoveSelfFromBlock()
                    return VisitResult.CONTINUE
                }
                for (user in expr.GetResult().getOrThrow().GetUsers()) {
                    user.ReplaceOperand(expr.GetResult().getOrThrow(), newCast)
                }
                newCast.AsLocalVar().getOrThrow().GetExpr().getOrThrow().MoveBefore(expr)
                expr.RemoveSelfFromBlock()
            }
        } else if (expr.GetExprKind() == ExprKind.TYPECAST) {
            let cast = (expr as TypeCast).getOrThrow()
            let sourceValue = cast.GetSourceValue()
            if (sourceValue.GetType().getOrThrow().IsGenericRelated()) {
                return VisitResult.CONTINUE
            }
            let newCastResult = TypeCastOrBoxIfNeeded(sourceValue, expr.GetResult().getOrThrow().GetType().getOrThrow(),
                builder, expr.GetParentBlock().getOrThrow(), expr.GetDebugLocation())
            if (refEq(newCastResult, sourceValue)) {
                return VisitResult.CONTINUE
            }
            let newCast = newCastResult.AsLocalVar().getOrThrow()
            if (newCast.GetExpr().getOrThrow().GetExprKind() == ExprKind.TYPECAST) {
                newCast.GetExpr().getOrThrow().RemoveSelfFromBlock()
                return VisitResult.CONTINUE
            }
            for (user in expr.GetResult().getOrThrow().GetUsers()) {
                user.ReplaceOperand(expr.GetResult().getOrThrow(), newCast)
            }
            newCast.GetExpr().getOrThrow().MoveBefore(expr)
            expr.RemoveSelfFromBlock()
        }
        return VisitResult.CONTINUE
    }
    for (block in blocks) {
        Visitor.Visit(block, preVisit)
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

private func RemoveClonedDebugExpressions(newDebugs: ArrayList<Expression>): Unit {
    for (debugExpr in newDebugs) {
        if (debugExpr.GetParentBlock().isSome()) {
            debugExpr.RemoveSelfFromBlock()
        }
    }
}
