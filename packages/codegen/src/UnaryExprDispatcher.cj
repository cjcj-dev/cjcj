package cangjie_compiler::codegen

import cangjie_compiler::chir.ExprKind
import cangjie_compiler::utils.OverflowStrategy

public func HandleNegExpression(irBuilder: IRBuilder2, value: LLVMValueRef): LLVMValueRef {
    return irBuilder.CreateUnary(ExprKind.NEG, value, name: "neg")
}

public func HandleUnaryExpression(irBuilder: IRBuilder2, chirExpr: CHIRUnaryExprWrapper): LLVMValueRef {
    if (chirExpr.unaryExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let operand = chirExpr.unaryExpr.GetOperand(0)
    let cgValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, operand)
    let operandType = operand.GetType()
    let resultType = chirExpr.unaryExpr.GetResultType()
    let overflowStrategy = chirExpr.unaryExpr.GetOverflowStrategy()
    if ((overflowStrategy == OverflowStrategy.THROWING || overflowStrategy == OverflowStrategy.SATURATING ||
        overflowStrategy == OverflowStrategy.CHECKED) && chirExpr.unaryExpr.GetExprKind() == ExprKind.NEG) {
        if (let Some(resultTy) <- resultType) {
            if (resultTy.IsInteger()) {
                return GenerateOverflowUnary(irBuilder, overflowStrategy, chirExpr.unaryExpr.GetExprKind(), operand,
                    cgValue.GetRawValue(), resultType)
            }
        }
    }
    return irBuilder.CreateUnaryTypedWithResult(chirExpr.unaryExpr.GetExprKind(), cgValue.GetRawValue(),
        operandType, resultType, name: chirExpr.unaryExpr.GetExprKindName())
}
