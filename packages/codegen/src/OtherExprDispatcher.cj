package cangjie_compiler::codegen

import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.GetRTTI
import cangjie_compiler::chir.GetRTTIStatic
import cangjie_compiler::chir.Lambda

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
    if (kind == ExprKind.APPLY) {
        return EmitCallLikeExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC) {
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
        return GenerateVArrayExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.VARRAY_BUILDER) {
        return GenerateVArrayBuilderExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.FIELD || kind == ExprKind.FIELD_BY_NAME) {
        return GenerateFieldExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.TYPECAST || kind == ExprKind.BOX || kind == ExprKind.UNBOX ||
        kind == ExprKind.TRANSFORM_TO_GENERIC || kind == ExprKind.TRANSFORM_TO_CONCRETE ||
        kind == ExprKind.UNBOX_TO_REF) {
        return EmitTypeCastExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.DEBUGEXPR) {
        return LLVMNullValue()
    }
    if (kind == ExprKind.GET_EXCEPTION) {
        return irBuilder.CallExceptionIntrinsicGetExceptionValue()
    }
    if (kind == ExprKind.INTRINSIC) {
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
    if (kind == ExprKind.GET_INSTANTIATE_VALUE) {
        if (let Some(resultTy) <- chirExpr.GetResultType()) {
            return unsafe { LLVMConstNull(CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType()) }
        }
    }
    return LLVMNullValue()
}

private func GenerateRTTIExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
    if (let Some(getRTTI) <- (chirExpr as GetRTTI)) {
        let objectValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, getRTTI.GetOperand()).GetRawValue()
        let typeInfoSlotType = unsafe { LLVMPointerType(typeInfoPtrType, 1u32) }
        let typeInfoSlot = irBuilder.CreateBitCast(objectValue, typeInfoSlotType, name: "obj.ti.slot")
        return irBuilder.CreateLoad(typeInfoPtrType, typeInfoSlot, name: "ti")
    }
    if (let Some(getRTTIStatic) <- (chirExpr as GetRTTIStatic)) {
        return irBuilder.CreateBitCast(CGType.GetOrCreate(irBuilder.GetCGModule(),
            getRTTIStatic.GetRTTIType()).GetOrCreateTypeInfo(), typeInfoPtrType, name: "static.ti")
    }
    return LLVMNullValue()
}
