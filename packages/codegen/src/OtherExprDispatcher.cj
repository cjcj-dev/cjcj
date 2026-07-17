package cjcj::codegen

import cjcj::chir.ClassType
import cjcj::chir.Debug
import cjcj::chir.Expression
import cjcj::chir.ExprKind
import cjcj::chir.GetRTTI
import cjcj::chir.GetRTTIStatic
import cjcj::chir.Lambda
import cjcj::chir.TypeCast
import cjcj::chir.IsCapturedClass
import cjcj::chir.`VArray` as CHIRVArray
import cjcj::utils.CJC_ASSERT

public func HandleStructedControlFlowExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetExprKind() == ExprKind.LAMBDA) {
        if (let Some(resultTy) <- chirExpr.GetResultType()) {
            return unsafe { LLVMConstNull(CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType()) }
        }
    }
    return LLVMNullValue()
}

public func HandleOthersExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let kind = chirExpr.GetExprKind()
    if (kind == ExprKind.LAMBDA) {
        if (let Some(lambdaExpr) <- (chirExpr as Lambda)) {
            return GenerateLambdaExpression(irBuilder, lambdaExpr)
        }
        return LLVMNullValue()
    }
    if (kind == ExprKind.GET_INSTANTIATE_VALUE) {
        if (let Some(resultTy) <- chirExpr.GetResultType()) {
            return unsafe { LLVMConstNull(CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType()) }
        }
        return LLVMNullValue()
    }
    if (kind == ExprKind.APPLY || kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC ||
        kind == ExprKind.FIELD || kind == ExprKind.TYPECAST || kind == ExprKind.TUPLE ||
        kind == ExprKind.VARRAY || kind == ExprKind.VARRAY_BUILDER || kind == ExprKind.INTRINSIC ||
        kind == ExprKind.RAW_ARRAY_LITERAL_INIT || kind == ExprKind.RAW_ARRAY_ALLOCATE ||
        kind == ExprKind.RAW_ARRAY_INIT_BY_VALUE || kind == ExprKind.INSTANCEOF || kind == ExprKind.SPAWN ||
        kind == ExprKind.GET_EXCEPTION || kind == ExprKind.BOX || kind == ExprKind.UNBOX ||
        kind == ExprKind.TRANSFORM_TO_GENERIC || kind == ExprKind.TRANSFORM_TO_CONCRETE ||
        kind == ExprKind.UNBOX_TO_REF || kind == ExprKind.GET_RTTI || kind == ExprKind.GET_RTTI_STATIC) {
        irBuilder.EmitLocation(CHIRExprWrapper(chirExpr))
    }
    if (kind == ExprKind.APPLY) {
        irBuilder.EmitLocation(CHIRExprWrapper(chirExpr))
        return EmitCallLikeExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.INVOKE) {
        irBuilder.EmitLocation(CHIRExprWrapper(chirExpr))
        return GenerateInvokeExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.INVOKESTATIC) {
        irBuilder.EmitLocation(CHIRExprWrapper(chirExpr))
        return GenerateInvokeExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.RAW_ARRAY_ALLOCATE) {
        return GenerateRawArrayAllocate(irBuilder, chirExpr)
    }
    if (kind == ExprKind.RAW_ARRAY_LITERAL_INIT) {
        return GenerateRawArrayLiteralInit(irBuilder, chirExpr)
    }
    if (kind == ExprKind.RAW_ARRAY_INIT_BY_VALUE) {
        return GenerateRawArrayInitByValue(irBuilder, chirExpr)
    }
    if (kind == ExprKind.TUPLE) {
        return GenerateTupleOrAggregateExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.VARRAY) {
        return GenerateVArray(irBuilder, (chirExpr as CHIRVArray).getOrThrow())
    }
    if (kind == ExprKind.VARRAY_BUILDER) {
        return GenerateVArrayBuilder(irBuilder, chirExpr)
    }
    if (kind == ExprKind.FIELD || kind == ExprKind.FIELD_BY_NAME) {
        return GenerateFieldExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.TYPECAST) {
        return HandleTypecastExpr(irBuilder, chirExpr)
    }
    if (kind == ExprKind.BOX || kind == ExprKind.UNBOX ||
        kind == ExprKind.TRANSFORM_TO_GENERIC || kind == ExprKind.TRANSFORM_TO_CONCRETE ||
        kind == ExprKind.UNBOX_TO_REF) {
        return EmitTypeCastExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.DEBUGEXPR) {
        return HandleDebugExpr(irBuilder, chirExpr)
    }
    if (kind == ExprKind.GET_EXCEPTION) {
        return irBuilder.CallExceptionIntrinsicGetExceptionValue()
    }
    if (kind == ExprKind.INTRINSIC) {
        irBuilder.EmitLocation(CHIRExprWrapper(chirExpr))
        return GenerateIntrinsic(irBuilder, chirExpr)
    }
    if (kind == ExprKind.GET_RTTI || kind == ExprKind.GET_RTTI_STATIC) {
        return GenerateRTTIExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.INSTANCEOF) {
        return GenerateInstanceOf(irBuilder, chirExpr)
    }
    if (kind == ExprKind.SPAWN) {
        return GenerateSpawn(irBuilder, chirExpr)
    }
    return LLVMNullValue()
}

public func HandleDebugExpr(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let debug = (chirExpr as Debug).getOrThrow()
    let cgMod = irBuilder.GetCGModule()
    let cgVal = cgMod.GetMappedCGValue(debug.GetValue())
    let rawVal = cgVal.GetRawValue()
    let rawType = unsafe { LLVMTypeOf(rawVal) }
    if (unsafe { LLVMGetTypeKind(rawType) } != 0 && unsafe { LLVMIsAGlobalObject(rawVal) }.isNull()) {
        let identifier = debug.GetSrcCodeIdentifier()
        try (nameCString = unsafe { LibC.mallocCString(identifier) }.asResource()) {
            unsafe { LLVMSetValueName2(rawVal, nameCString.value, UIntNative(identifier.size)) }
        }
    }
    if (!irBuilder.GetCGContext().GetCompileOptions().enableCompileDebug) {
        return LLVMNullValue()
    }
    let ty = DeRef(debug.GetValue().GetType().getOrThrow())
    let isBoxClass = ty.IsClass() && IsCapturedClass((ty as ClassType).getOrThrow().GetClassDef())
    let hasSize = CGType.GetOrCreate(cgMod, ty).GetSize().isSome()
    if (!IsReferenceType(ty, cgMod) && hasSize && ty.IsGenericRelated()) {
        irBuilder.CreateBoxedValueForValueType(debug, cgVal)
    } else if (debug.GetValue().IsParameter()) {
        irBuilder.CreateValuePointer(debug, cgVal)
    } else if (unsafe { LLVMIsAAllocaInst(cgVal.GetRawValue()) }.isNull()) {
        CJC_ASSERT(unsafe { LLVMIsAAllocaInst(cgVal.GetRawValue()) }.isNull() == (!hasSize && !ty.IsClass()))
        irBuilder.CreateLocalVarPointer(debug, cgVal)
    } else if (isBoxClass) {
        irBuilder.CreateUnBoxDeclare(debug, cgVal)
    } else {
        irBuilder.EmitDeclare(debug)
    }
    return rawVal
}

private func HandleTypecastExpr(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let typeCast = (chirExpr as TypeCast).getOrThrow()
    return GenerateTypeCast(irBuilder, CHIRTypeCastWrapper(typeCast))
}

private func GenerateRTTIExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
    if (let Some(getRTTI) <- (chirExpr as GetRTTI)) {
        let objectValue = irBuilder.GetCGModule().GetMappedCGValue(getRTTI.GetOperand()).GetRawValue()
        let typeInfo = irBuilder.GetTypeInfoFromObject(objectValue)
        return irBuilder.CreateBitCast(typeInfo, typeInfoPtrType)
    }
    if (let Some(getRTTIStatic) <- (chirExpr as GetRTTIStatic)) {
        return irBuilder.CreateBitCast(irBuilder.CreateTypeInfo(getRTTIStatic.GetRTTIType()),
            typeInfoPtrType, name: "static.ti")
    }
    return LLVMNullValue()
}
