package cjcj::chir

import cjcj::utils.{OverflowStrategy, OverflowStrategyIndex}

public func CHIR2BCHIRTranslateOtherExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    match (expr.GetExprKind()) {
        case ExprKind.CONSTANT =>
            if (let Some(constant) <- (expr as Constant)) {
                compiler.TranslateLiteralValue(context, constant.literal)
            } else {
                context.definition.PushOp(OpCode.NOT_SUPPORTED)
            }
        case ExprKind.TUPLE =>
            context.definition.PushOp(OpCode.TUPLE)
            context.definition.PushCell(expr.GetNumOfOperands())
        case ExprKind.FIELD => TranslateFieldExpression(context, expr)
        case ExprKind.APPLY => TranslateApplyExpression(context, expr)
        case ExprKind.INVOKE => TranslateInvokeExpression(context, expr, false)
        case ExprKind.INSTANCEOF => TranslateInstanceOfExpression(context, expr)
        case ExprKind.TYPECAST => TranslateTypecastExpression(context, expr, false)
        case ExprKind.INTRINSIC => TranslateIntrinsicExpression(compiler, context, expr, false)
        case ExprKind.GET_EXCEPTION => context.definition.PushOp(OpCode.GET_EXCEPTION)
        case ExprKind.RAW_ARRAY_ALLOCATE => context.definition.PushOp(OpCode.ALLOCATE_RAW_ARRAY)
        case ExprKind.RAW_ARRAY_LITERAL_INIT =>
            context.definition.PushOp(OpCode.RAW_ARRAY_LITERAL_INIT)
            context.definition.PushCell(if (expr.GetNumOfOperands() > 0) { expr.GetNumOfOperands() - 1 } else { 0 })
        case ExprKind.RAW_ARRAY_INIT_BY_VALUE => context.definition.PushOp(OpCode.RAW_ARRAY_INIT_BY_VALUE)
        case ExprKind.VARRAY =>
            context.definition.PushOp(OpCode.VARRAY)
            context.definition.PushCell(expr.GetNumOfOperands())
        case ExprKind.BOX => TranslateBoxExpression(context, expr)
        case ExprKind.UNBOX => context.definition.PushOp(OpCode.UNBOX)
        case ExprKind.UNBOX_TO_REF => context.definition.PushOp(OpCode.UNBOX_REF)
        case ExprKind.VARRAY_BUILDER | ExprKind.SPAWN | ExprKind.INVOKESTATIC | ExprKind.GET_RTTI |
            ExprKind.GET_RTTI_STATIC | ExprKind.TRANSFORM_TO_CONCRETE | ExprKind.TRANSFORM_TO_GENERIC =>
            context.definition.PushOp(OpCode.ABORT)
        case _ => context.definition.PushOp(OpCode.ABORT)
    }
}

private func TranslateApplyExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (let Some(apply) <- (expr as Apply)) {
        let callee = apply.GetCallee()
        if (callee.GetSrcCodeIdentifier() == "std.core:CJ_CORE_CanUseSIMD" ||
            callee.GetSrcCodeIdentifier() == "CJ_CORE_CanUseSIMD" ||
            callee.GetIdentifier().contains("CJ_CORE_CanUseSIMD")) {
            context.definition.PushOp(OpCode.INTRINSIC1)
            context.definition.PushCell(BCHIRIntrinsic.ToByteCodeKind(IntrinsicKind.CJ_CORE_CAN_USE_SIMD))
            context.definition.PushCell(0xffffffff)
            return
        }
    }
    context.definition.PushOp(OpCode.APPLY)
    context.definition.PushCell(expr.GetNumOfOperands())
}

private func TranslateFieldExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (let Some(field) <- (expr as Field)) {
        let path = field.GetPath()
        if (path.size == 1) {
            context.definition.PushOp(OpCode.FIELD)
            context.definition.PushCell(BCHIRCellFromUInt64(path[0]))
        } else if (path.size > 1) {
            context.definition.PushOp(OpCode.FIELD_TPL)
            context.definition.PushCell(path.size)
            for (item in path) {
                context.definition.PushCell(BCHIRCellFromUInt64(item))
            }
        } else {
            context.definition.PushOp(OpCode.NOT_SUPPORTED)
        }
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

public func TranslateInvokeExpression(context: CHIR2BCHIRContext, expr: Expression, withException: Bool): Unit {
    if (let Some(invoke) <- (expr as Invoke)) {
        let opCode = if (withException) { OpCode.INVOKE_EXC } else { OpCode.INVOKE }
        BCHIRPushOpWithName(context.definition, opCode,
            MangleMethodName(invoke.GetMethodName(), invoke.GetMethodType(), omitFirstArg: true))
        context.definition.PushCell(expr.GetNumOfOperands())
        context.definition.PushCell(0)
    } else if (let Some(invokeWithException) <- (expr as InvokeWithException)) {
        let opCode = if (withException) { OpCode.INVOKE_EXC } else { OpCode.INVOKE }
        BCHIRPushOpWithName(context.definition, opCode,
            MangleMethodName(invokeWithException.GetMethodName(), invokeWithException.GetMethodType(), omitFirstArg: true))
        context.definition.PushCell(expr.GetNumOfOperands())
        context.definition.PushCell(0)
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

public func TranslateTypecastExpression(context: CHIR2BCHIRContext, expr: Expression, withException: Bool): Unit {
    let sourceTy: Option<Type> = if (let Some(typeCast) <- (expr as TypeCast)) {
        typeCast.GetSourceTy()
    } else if (let Some(typeCastWithException) <- (expr as TypeCastWithException)) {
        typeCastWithException.GetSourceTy()
    } else {
        None
    }
    let targetTy: Option<Type> = if (let Some(typeCast) <- (expr as TypeCast)) {
        typeCast.GetTargetTy()
    } else if (let Some(typeCastWithException) <- (expr as TypeCastWithException)) {
        typeCastWithException.GetTargetTy()
    } else {
        None
    }
    if (let Some(src) <- sourceTy) {
        if (let Some(dst) <- targetTy) {
            if (src.IsPrimitive() && dst.IsPrimitive()) {
                context.definition.PushOp(if (withException) { OpCode.TYPECAST_EXC } else { OpCode.TYPECAST })
                context.definition.PushCell(BCHIRTypeKindCell(src))
                context.definition.PushCell(BCHIRTypeKindCell(dst))
                let overflowStrategy = if (let Some(typeCast) <- (expr as TypeCast)) {
                    typeCast.GetOverflowStrategy()
                } else {
                    OverflowStrategy.THROWING
                }
                context.definition.PushCell(OverflowStrategyIndex(overflowStrategy))
            }
        }
    }
}

private func TranslateInstanceOfExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (let Some(instanceOf) <- (expr as InstanceOf)) {
        let opIndex = context.definition.NextIndex()
        context.definition.PushOp(OpCode.INSTANCEOF)
        context.definition.PushCell(0)
        let testedTy = instanceOf.GetType()
        if (testedTy.IsRef()) {
            let refTy = (testedTy as RefType).getOrThrow()
            let classTy = (refTy.GetBaseType() as ClassType).getOrThrow()
            let classDef = classTy.GetClassDef()
            context.definition.AddMangledNameAnnotation(opIndex, classDef.GetIdentifierWithoutPrefix())
        } else if (testedTy.IsPrimitive()) {
            let primitiveClassName = testedTy.ToString()
            context.definition.AddMangledNameAnnotation(opIndex, primitiveClassName)
        } else {
            let customTy = (testedTy as CustomType).getOrThrow()
            let customDef = customTy.GetCustomTypeDef()
            context.definition.AddMangledNameAnnotation(opIndex, customDef.GetIdentifierWithoutPrefix())
        }
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

private func TranslateBoxExpression(context: CHIR2BCHIRContext, expr: Expression): Unit {
    if (let Some(box) <- (expr as Box)) {
        if (let Some(sourceTy) <- box.GetSourceTy()) {
            let opIndex = context.definition.NextIndex()
            context.definition.PushOp(OpCode.BOX)
            context.definition.PushCell(0)
            if (sourceTy.IsStruct()) {
                let structTy = (sourceTy as StructType).getOrThrow()
                let structDef = structTy.GetStructDef()
                context.definition.AddMangledNameAnnotation(opIndex, structDef.GetIdentifierWithoutPrefix())
            } else if (sourceTy.IsEnum()) {
                let enumTy = (sourceTy as EnumType).getOrThrow()
                let enumDef = enumTy.GetEnumDef()
                context.definition.AddMangledNameAnnotation(opIndex, enumDef.GetIdentifierWithoutPrefix())
            } else {
                context.definition.AddMangledNameAnnotation(opIndex, sourceTy.ToString())
            }
        } else {
            context.definition.PushOp(OpCode.NOT_SUPPORTED)
        }
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}
