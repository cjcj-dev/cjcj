package cangjie_compiler::codegen

import cangjie_compiler::chir.Expression

public func HandleMemoryExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    // TODO(selfhost:CodeGen): lower allocate/load/store/get-element-ref memory expressions.
    return LLVMNullValue()
}
