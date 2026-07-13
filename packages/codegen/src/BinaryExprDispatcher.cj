package cjcj::codegen

import cjcj::chir.ExprKind
import cjcj::chir.ExprKindIndex
import cjcj::utils.{CJC_ASSERT_WITH_MSG, OverflowStrategy}

public func HandleBinaryExpression(irBuilder: IRBuilder2, chirExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    let kind = chirExpr.binaryExpr.GetExprKind()
    if (IsBooleanBinaryExprKind(kind)) {
        return GenerateBooleanOperation(irBuilder, chirExpr)
    }
    let overflowStrategy = chirExpr.binaryExpr.GetOverflowStrategy()
    if (ShouldUseOverflowBinary(kind, overflowStrategy)) {
        if (let Some(resultTy) <- chirExpr.binaryExpr.GetResultType()) {
            if (resultTy.IsInteger()) {
                return GenerateOverflowBinary(irBuilder, overflowStrategy, kind, chirExpr.binaryExpr.GetOperand(0),
                    chirExpr.binaryExpr.GetOperand(1), chirExpr.binaryExpr.GetResultType())
            }
        }
    }
    if (kind == ExprKind.EXP) {
        return GenerateBinaryExpOperation(irBuilder, chirExpr)
    }
    return HandleNonOverflowBinaryExpression(irBuilder, chirExpr)
}

private func HandleNonOverflowBinaryExpression(irBuilder: IRBuilder2,
    chirExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    let kind = chirExpr.binaryExpr.GetExprKind()
    if (kind == ExprKind.ADD || kind == ExprKind.SUB || kind == ExprKind.MUL || kind == ExprKind.DIV ||
        kind == ExprKind.MOD) {
        return GenerateArithmeticOperation(irBuilder, chirExpr)
    }
    if (kind == ExprKind.EXP) {
        return GenerateBinaryExpOperation(irBuilder, chirExpr)
    }
    if (kind == ExprKind.LSHIFT || kind == ExprKind.RSHIFT || kind == ExprKind.BITAND || kind == ExprKind.BITOR ||
        kind == ExprKind.BITXOR) {
        return GenerateBitwiseOperation(irBuilder, chirExpr)
    }
    if (kind == ExprKind.LT || kind == ExprKind.GT || kind == ExprKind.LE || kind == ExprKind.GE ||
        kind == ExprKind.EQUAL || kind == ExprKind.NOTEQUAL) {
        return GenerateBooleanOperation(irBuilder, chirExpr)
    }
    CJC_ASSERT_WITH_MSG(false, "Unexpected CHIRBinaryExprKind: ${ExprKindIndex(kind)}\n")
    return LLVMNullValue()
}

private func ShouldUseOverflowBinary(kind: ExprKind, strategy: OverflowStrategy): Bool {
    if ((strategy == OverflowStrategy.NA || strategy == OverflowStrategy.WRAPPING) &&
        kind != ExprKind.DIV && kind != ExprKind.MOD) {
        return false
    }
    return kind == ExprKind.ADD || kind == ExprKind.SUB || kind == ExprKind.MUL ||
        kind == ExprKind.DIV || kind == ExprKind.MOD || kind == ExprKind.EXP
}
