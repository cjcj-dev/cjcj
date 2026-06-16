package cangjie_compiler::codegen

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
    if (kind == ExprKind.TUPLE || kind == ExprKind.RAW_ARRAY_LITERAL_INIT ||
        kind == ExprKind.RAW_ARRAY_INIT_BY_VALUE) {
        return GenerateTupleOrAggregateExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.VARRAY) {
        return GenerateVArrayExpression(irBuilder, chirExpr)
    }
    if (kind == ExprKind.TYPECAST || kind == ExprKind.BOX || kind == ExprKind.UNBOX ||
        kind == ExprKind.TRANSFORM_TO_GENERIC || kind == ExprKind.TRANSFORM_TO_CONCRETE ||
        kind == ExprKind.UNBOX_TO_REF) {
        return EmitTypeCastExpression(irBuilder, chirExpr)
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
