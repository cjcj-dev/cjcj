package cjcj::chir

import cjcj::utils.{CJC_ASSERT, OverflowStrategy, OverflowStrategyIndex}
import std.collection.*

private let syscall2IntrinsicKind = HashMap<String, IntrinsicKind>([
    ("CJ_AST_Lex", IntrinsicKind.FFI_CJ_AST_LEX),
    ("CJ_AST_ParseExpr", IntrinsicKind.FFI_CJ_AST_PARSEEXPR),
    ("CJ_AST_ParseDecl", IntrinsicKind.FFI_CJ_AST_PARSEDECL),
    ("CJ_AST_ParsePropMemberDecl", IntrinsicKind.FFI_CJ_AST_PARSE_PROPMEMBERDECL),
    ("CJ_AST_ParsePrimaryConstructor", IntrinsicKind.FFI_CJ_AST_PARSE_PRICONSTRUCTOR),
    ("CJ_AST_ParsePattern", IntrinsicKind.FFI_CJ_AST_PARSE_PATTERN),
    ("CJ_AST_ParseType", IntrinsicKind.FFI_CJ_AST_PARSE_TYPE),
    ("CJ_AST_ParseTopLevel", IntrinsicKind.FFI_CJ_AST_PARSETOPLEVEL),
    ("CJ_CheckParentContext", IntrinsicKind.FFI_CJ_PARENT_CONTEXT),
    ("CJ_SetItemInfo", IntrinsicKind.FFI_CJ_MACRO_ITEM_INFO),
    ("CJ_GetChildMessages", IntrinsicKind.FFI_CJ_GET_CHILD_MESSAGES),
    ("CJ_CheckAddSpace", IntrinsicKind.FFI_CJ_CHECK_ADD_SPACE),
    ("CJ_AST_DiagReport", IntrinsicKind.FFI_CJ_AST_DIAGREPORT),
    ("CJ_TLS_DYN_SetSessionCallback", IntrinsicKind.CJ_TLS_DYN_SET_SESSION_CALLBACK),
    ("CJ_TLS_DYN_SslInit", IntrinsicKind.CJ_TLS_DYN_SSL_INIT),
    ("CJ_CORE_CanUseSIMD", IntrinsicKind.CJ_CORE_CAN_USE_SIMD),
    ("std.core:CJ_CORE_CanUseSIMD", IntrinsicKind.CJ_CORE_CAN_USE_SIMD)
])

public func CHIR2BCHIRTranslateOtherExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    match (expr.GetExprKind()) {
        case ExprKind.CONSTANT => ()
        case ExprKind.TUPLE =>
            context.definition.PushOp(OpCode.TUPLE)
            context.definition.PushCell(expr.GetNumOfOperands())
        case ExprKind.FIELD => TranslateField(context, expr)
        case ExprKind.APPLY => TranslateApplyExpression(compiler, context, expr)
        case ExprKind.INVOKE => TranslateInvokeExpression(compiler, context, expr, false)
        case ExprKind.INSTANCEOF => TranslateInstanceOf(context, expr)
        case ExprKind.TYPECAST => TranslateTypecastExpression(compiler, context, expr, false)
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
        case ExprKind.BOX => TranslateBox(context, expr)
        case ExprKind.UNBOX => context.definition.PushOp(OpCode.UNBOX)
        case ExprKind.UNBOX_TO_REF => context.definition.PushOp(OpCode.UNBOX_REF)
        case ExprKind.VARRAY_BUILDER | ExprKind.SPAWN | ExprKind.INVOKESTATIC | ExprKind.GET_RTTI |
            ExprKind.GET_RTTI_STATIC | ExprKind.TRANSFORM_TO_CONCRETE | ExprKind.TRANSFORM_TO_GENERIC =>
            context.definition.PushOp(OpCode.ABORT)
        case _ => context.definition.PushOp(OpCode.ABORT)
    }
}

private func TranslateCApplyExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    apply: Apply, funcTy: FuncType): Unit {
    let numberArgs = apply.GetNumOfOperands() - 1
    CJC_ASSERT(numberArgs == funcTy.GetParamTypes().size)
    compiler.PushOpCodeWithAnnotations(context, OpCode.CAPPLY, apply,
        args: ArrayList<Int64>([funcTy.GetParamTypes().size]), storeCodePos: true)
    context.definition.PushCell(compiler.GetTypeIdx(funcTy.GetReturnType()))
    for (paramTy in funcTy.GetParamTypes()) {
        context.definition.PushCell(compiler.GetTypeIdx(paramTy))
    }
}

private func TranslateApplyExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression): Unit {
    let apply = (expr as Apply).getOrThrow()
    let operands = apply.GetOperands()
    let callee = operands[0]
    let calleeName = callee.GetSrcCodeIdentifier()
    if ((callee.IsImportedFunc() && callee.GetAttributeInfo().Test(Attribute.FOREIGN)) ||
        calleeName == "std.core:CJ_CORE_CanUseSIMD") {
        if (let Some(intrinsicKind) <- syscall2IntrinsicKind.get(calleeName)) {
            compiler.PushOpCodeWithAnnotations(context, OpCode.INTRINSIC1, apply,
                args: ArrayList<Int64>([BCHIRIntrinsic.ToByteCodeKind(intrinsicKind), 0xffffffff]),
                storeCodePos: true)
            return
        }
        let stringIndex = compiler.GetStringIdx(calleeName)
        let numberArgs = apply.GetNumOfOperands() - 1
        compiler.PushOpCodeWithAnnotations(context, OpCode.SYSCALL, apply,
            args: ArrayList<Int64>([stringIndex, numberArgs]), storeCodePos: true)
        context.definition.PushCell(compiler.GetTypeIdx(apply.GetResult().getOrThrow().GetType().getOrThrow()))
        var operandIndex: Int64 = 1
        while (operandIndex < operands.size) {
            context.definition.PushCell(compiler.GetTypeIdx(operands[operandIndex].GetType().getOrThrow()))
            operandIndex++
        }
        return
    }
    let funcTy = (callee.GetType().getOrThrow() as FuncType).getOrThrow()
    if (funcTy.IsCFunc()) {
        TranslateCApplyExpression(compiler, context, apply, funcTy)
        return
    }
    compiler.PushOpCodeWithAnnotations(context, OpCode.APPLY, apply,
        args: ArrayList<Int64>([apply.GetNumOfOperands()]), storeCodePos: true)
}

private func TranslateField(context: CHIR2BCHIRContext, expr: Expression): Unit {
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

public func TranslateInvokeExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression, withException: Bool): Unit {
    if (let Some(invoke) <- (expr as Invoke)) {
        let numberArgs = invoke.GetArgs().size
        CJC_ASSERT(numberArgs > 0)
        CJC_ASSERT(numberArgs <= BYTECODE_CONTENT_MAX)
        let opCode = if (withException) { OpCode.INVOKE_EXC } else { OpCode.INVOKE }
        let opIndex = context.definition.NextIndex()
        compiler.PushOpCodeWithAnnotations(context, opCode, expr,
            args: ArrayList<Int64>([numberArgs, 0]), storeCodePos: true)
        context.definition.AddMangledNameAnnotation(opIndex,
            MangleMethodName(invoke.GetMethodName(), invoke.GetMethodType(), omitFirstArg: true))
    } else if (let Some(invokeWithException) <- (expr as InvokeWithException)) {
        let numberArgs = invokeWithException.GetArgs().size
        CJC_ASSERT(numberArgs > 0)
        CJC_ASSERT(numberArgs <= BYTECODE_CONTENT_MAX)
        let opCode = if (withException) { OpCode.INVOKE_EXC } else { OpCode.INVOKE }
        let opIndex = context.definition.NextIndex()
        compiler.PushOpCodeWithAnnotations(context, opCode, expr,
            args: ArrayList<Int64>([numberArgs, 0]), storeCodePos: true)
        context.definition.AddMangledNameAnnotation(opIndex, MangleMethodName(invokeWithException.GetMethodName(),
            invokeWithException.GetMethodType(), omitFirstArg: true))
    } else {
        context.definition.PushOp(OpCode.NOT_SUPPORTED)
    }
}

public func TranslateTypecastExpression(compiler: CHIR2BCHIR, context: CHIR2BCHIRContext,
    expr: Expression, withException: Bool): Unit {
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
                let overflowStrategy = if (let Some(typeCast) <- (expr as TypeCast)) {
                    typeCast.GetOverflowStrategy()
                } else {
                    OverflowStrategy.THROWING
                }
                compiler.PushOpCodeWithAnnotations(context,
                    if (withException) { OpCode.TYPECAST_EXC } else { OpCode.TYPECAST }, expr,
                    args: ArrayList<Int64>([
                        BCHIRTypeKindCell(src), BCHIRTypeKindCell(dst), OverflowStrategyIndex(overflowStrategy)
                    ]))
            }
        }
    }
}

private func TranslateInstanceOf(context: CHIR2BCHIRContext, expr: Expression): Unit {
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

private func TranslateBox(context: CHIR2BCHIRContext, expr: Expression): Unit {
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
