package cangjie_compiler::codegen

import cangjie_compiler::chir.Expression

public func HandleStructedControlFlowExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    // TODO(selfhost:CodeGen): lower structured control-flow CHIR expressions.
    return LLVMNullValue()
}

public func HandleOthersExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    // TODO(selfhost:CodeGen): lower tuple, field, apply, invoke, cast, array, spawn, box, and RTTI expressions.
    return LLVMNullValue()
}
