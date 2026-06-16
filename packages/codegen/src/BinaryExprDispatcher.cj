package cangjie_compiler::codegen

public func HandleBinaryExpression(irBuilder: IRBuilder2, chirExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    let kind = chirExpr.binaryExpr.GetExprKind()
    if (IsBooleanBinaryExprKind(kind)) {
        return GenerateBooleanOperation(irBuilder, chirExpr)
    }
    return GenerateArithmeticOperation(irBuilder, chirExpr)
}
