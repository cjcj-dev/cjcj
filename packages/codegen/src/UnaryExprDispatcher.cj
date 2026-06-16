package cangjie_compiler::codegen

import cangjie_compiler::chir.ExprKind

public func HandleNegExpression(irBuilder: IRBuilder2, value: LLVMValueRef): LLVMValueRef {
    return irBuilder.CreateUnary(ExprKind.NEG, value, name: "neg")
}

public func HandleUnaryExpression(irBuilder: IRBuilder2, chirExpr: CHIRUnaryExprWrapper): LLVMValueRef {
    // TODO(selfhost:CodeGen): map CHIR operands to CGValues before emitting unary operations.
    return LLVMNullValue()
}
