package cangjie_compiler::codegen

public func HandleBinaryExpression(irBuilder: IRBuilder2, chirExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    if (chirExpr.binaryExpr.GetNumOfOperands() < 2) {
        return LLVMNullValue()
    }
    let leftOperand = chirExpr.binaryExpr.GetOperand(0)
    let rightOperand = chirExpr.binaryExpr.GetOperand(1)
    let leftValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, leftOperand)
    let rightValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, rightOperand)
    let operandType = leftOperand.GetType()
    return irBuilder.CreateBinaryTyped(chirExpr.binaryExpr.GetExprKind(), leftValue.GetRawValue(), rightValue.GetRawValue(),
        operandType, chirExpr.binaryExpr.GetResultType(), name: chirExpr.binaryExpr.GetExprKindName())
}
