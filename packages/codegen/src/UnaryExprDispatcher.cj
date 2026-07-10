package cjcj::codegen

import cjcj::chir.ExprKind
import cjcj::utils.OverflowStrategy

public func HandleNegExpression(irBuilder: IRBuilder2, value: LLVMValueRef): LLVMValueRef {
    let valueType = unsafe { LLVMTypeOf(value) }
    let valueTypeKind = if (valueType.isNull()) { 0i32 } else { unsafe { LLVMGetTypeKind(valueType) } }
    let isFloatingPoint = (valueTypeKind >= 1i32 && valueTypeKind <= 6i32) || valueTypeKind == 18i32
    let name = if (isFloatingPoint) { "FNeg" } else { "Neg" }
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = if (isFloatingPoint) {
            unsafe { LLVMBuildFNeg(irBuilder.GetBuilder().raw, value, nameCString.value) }
        } else {
            unsafe { LLVMBuildNeg(irBuilder.GetBuilder().raw, value, nameCString.value) }
        }
    }
    return result
}

public func HandleUnaryExpression(irBuilder: IRBuilder2, chirExpr: CHIRUnaryExprWrapper): LLVMValueRef {
    if (chirExpr.unaryExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let operand = chirExpr.unaryExpr.GetOperand(0)
    let cgValue = irBuilder.GetCGModule().GetMappedCGValue(operand)
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
    return irBuilder.CreateUnaryTyped(chirExpr.unaryExpr.GetExprKind(), cgValue.GetRawValue(),
        operandType, name: chirExpr.unaryExpr.GetExprKindName())
}
