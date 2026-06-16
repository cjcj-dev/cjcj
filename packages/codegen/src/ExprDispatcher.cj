package cangjie_compiler::codegen

import cangjie_compiler::chir.Constant
import cangjie_compiler::chir.BinaryExpression
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ExprMajorKind
import cangjie_compiler::chir.UnaryExpression

public func DispatchExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(chirConst) <- (chirExpr as Constant)) {
        return HandleConstantExpression(irBuilder, chirConst)
    }
    if (chirExpr.IsTerminator()) {
        return HandleTerminatorExpression(irBuilder, chirExpr)
    }
    if (chirExpr.IsUnaryExpr()) {
        if (let Some(unaryExpr) <- (chirExpr as UnaryExpression)) {
            return HandleUnaryExpression(irBuilder, CHIRUnaryExprWrapper(unaryExpr))
        }
        return HandleUnaryExpression(irBuilder, CHIRUnaryExprWrapper(UnaryExpression(chirExpr.GetExprKind(),
            chirExpr.GetOperand(0), chirExpr.GetParentBlock())))
    }
    if (chirExpr.IsBinaryExpr()) {
        if (let Some(binaryExpr) <- (chirExpr as BinaryExpression)) {
            return HandleBinaryExpression(irBuilder, CHIRBinaryExprWrapper(binaryExpr))
        }
        return HandleBinaryExpression(irBuilder, CHIRBinaryExprWrapper(BinaryExpression(chirExpr.GetExprKind(),
            chirExpr.GetOperand(0), chirExpr.GetOperand(1), chirExpr.GetParentBlock())))
    }
    if (chirExpr.GetExprMajorKind() == ExprMajorKind.MEMORY_EXPR) {
        return HandleMemoryExpression(irBuilder, chirExpr)
    }
    return HandleOthersExpression(irBuilder, chirExpr)
}
