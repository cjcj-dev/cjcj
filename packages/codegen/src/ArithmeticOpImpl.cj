package cangjie_compiler::codegen

import cangjie_compiler::chir.ExprKind

public func GenerateArithmeticOperation(irBuilder: IRBuilder2, chirExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    if (chirExpr.binaryExpr.GetNumOfOperands() < 2) {
        return LLVMNullValue()
    }
    let leftOperand = chirExpr.binaryExpr.GetOperand(0)
    let rightOperand = chirExpr.binaryExpr.GetOperand(1)
    let leftValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, leftOperand)
    let rightValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, rightOperand)
    var rightRawValue = rightValue.GetRawValue()
    let operandType = leftOperand.GetType()
    let resultType = chirExpr.binaryExpr.GetResultType()
    let kind = chirExpr.binaryExpr.GetExprKind()
    if (kind == ExprKind.LSHIFT || kind == ExprKind.RSHIFT) {
        if (let Some(leftTy) <- leftOperand.GetType()) {
            if (let Some(rightTy) <- rightOperand.GetType()) {
                if (!leftTy.IsEqual(rightTy)) {
                    let targetType = CGType.GetOrCreate(irBuilder.GetCGModule(), leftTy).GetLLVMType()
                    rightRawValue = CastValueToType(irBuilder, rightRawValue, rightTy, leftTy, targetType)
                }
            }
        }
    }
    return irBuilder.CreateBinaryTyped(kind, leftValue.GetRawValue(), rightRawValue, operandType, resultType,
        name: chirExpr.binaryExpr.GetExprKindName())
}
