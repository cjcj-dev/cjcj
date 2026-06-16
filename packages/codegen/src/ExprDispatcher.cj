package cangjie_compiler::codegen

import cangjie_compiler::chir.Constant
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ExprMajorKind

public func DispatchExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(chirConst) <- (chirExpr as Constant)) {
        return HandleConstantExpression(irBuilder, chirConst)
    }
    if (chirExpr.IsTerminator()) {
        return HandleTerminatorExpression(irBuilder, chirExpr)
    }
    if (chirExpr.IsUnaryExpr()) {
        // TODO(selfhost:CodeGen): construct CHIRUnaryExprWrapper after CHIR exposes typed operand access here.
        return LLVMNullValue()
    }
    if (chirExpr.IsBinaryExpr()) {
        // TODO(selfhost:CodeGen): construct CHIRBinaryExprWrapper after CHIR exposes typed operand access here.
        return LLVMNullValue()
    }
    if (chirExpr.GetExprMajorKind() == ExprMajorKind.MEMORY_EXPR) {
        return HandleMemoryExpression(irBuilder, chirExpr)
    }
    return HandleOthersExpression(irBuilder, chirExpr)
}
