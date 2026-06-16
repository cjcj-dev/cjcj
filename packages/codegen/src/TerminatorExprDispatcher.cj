package cangjie_compiler::codegen

import cangjie_compiler::chir.Expression

public func HandleTerminatorExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    // TODO(selfhost:CodeGen): lower GoTo, Branch, MultiBranch, Exit, and exception terminators.
    return LLVMNullValue()
}
