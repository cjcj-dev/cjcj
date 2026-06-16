package cangjie_compiler::codegen

public func HandleBinaryExpression(irBuilder: IRBuilder2, chirExpr: CHIRBinaryExprWrapper): LLVMValueRef {
    // TODO(selfhost:CodeGen): map CHIR operands to LLVM values and apply signed/unsigned/float variants faithfully.
    return LLVMNullValue()
}
