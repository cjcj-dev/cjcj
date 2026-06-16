package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ExprKind

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
    if (kind == ExprKind.APPLY || kind == ExprKind.INVOKE || kind == ExprKind.INVOKESTATIC) {
        return EmitCallLikeExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.TUPLE || kind == ExprKind.VARRAY || kind == ExprKind.RAW_ARRAY_LITERAL_INIT ||
        kind == ExprKind.RAW_ARRAY_INIT_BY_VALUE) {
        return EmitAggregateExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.TYPECAST || kind == ExprKind.BOX || kind == ExprKind.UNBOX ||
        kind == ExprKind.TRANSFORM_TO_GENERIC || kind == ExprKind.TRANSFORM_TO_CONCRETE ||
        kind == ExprKind.UNBOX_TO_REF) {
        if (chirExpr.GetNumOfOperands() == 0) {
            return LLVMNullValue()
        }
        let sourceValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0)).GetRawValue()
        if (let Some(resultTy) <- chirExpr.GetResultType()) {
            return irBuilder.CreateBitCast(sourceValue, CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType())
        }
        return sourceValue
    }
    if (kind == ExprKind.DEBUGEXPR) {
        return LLVMNullValue()
    }
    if (kind == ExprKind.GET_EXCEPTION || kind == ExprKind.GET_RTTI || kind == ExprKind.GET_RTTI_STATIC ||
        kind == ExprKind.INSTANCEOF || kind == ExprKind.INTRINSIC || kind == ExprKind.SPAWN ||
        kind == ExprKind.GET_INSTANTIATE_VALUE) {
        if (let Some(resultTy) <- chirExpr.GetResultType()) {
            return unsafe { LLVMConstNull(CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType()) }
        }
    }
    return LLVMNullValue()
}

private func EmitCallLikeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let calleeValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
    let args = ArrayList<LLVMValueRef>()
    var idx: Int64 = 1
    while (idx < chirExpr.GetNumOfOperands()) {
        args.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(idx)).GetRawValue())
        idx++
    }
    if (let Some(cgFunctionValue) <- (calleeValue as CGFunction)) {
        if (let Some(functionType) <- cgFunctionValue.GetCGFunctionType()) {
            return irBuilder.CreateCall(cgFunctionValue.GetRawFunction(), functionType.GetLLVMFunctionType(), args, name: "call")
        }
    }
    if (let Some(calleeType) <- calleeValue.GetCGType()) {
        if (let Some(functionType) <- (calleeType as CGFunctionType)) {
            return irBuilder.CreateCall(calleeValue.GetRawValue(), functionType.GetLLVMFunctionType(), args, name: "call")
        }
    }
    return LLVMNullValue()
}

private func EmitAggregateExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        let resultCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
        let elements = ArrayList<LLVMValueRef>()
        var idx: Int64 = 0
        while (idx < chirExpr.GetNumOfOperands()) {
            elements.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(idx)).GetRawValue())
            idx++
        }
        return irBuilder.CreateAggregateValue(resultCGType.GetLLVMType(), elements, name: chirExpr.GetExprKindName())
    }
    return LLVMNullValue()
}
