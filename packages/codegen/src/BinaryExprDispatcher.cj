package cangjie_compiler::codegen

import cangjie_compiler::chir.ExprKind
import cangjie_compiler::utils.OverflowStrategy

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
    return GenerateArithmeticOperation(irBuilder, chirExpr)
}

private func ShouldUseOverflowBinary(kind: ExprKind, strategy: OverflowStrategy): Bool {
    if (strategy == OverflowStrategy.NA || strategy == OverflowStrategy.WRAPPING) {
        return false
    }
    return kind == ExprKind.ADD || kind == ExprKind.SUB || kind == ExprKind.MUL ||
        kind == ExprKind.DIV || kind == ExprKind.MOD || kind == ExprKind.LSHIFT || kind == ExprKind.RSHIFT
}
