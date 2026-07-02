package cangjie_compiler::codegen

import cangjie_compiler::chir.Constant
import cangjie_compiler::chir.LiteralValue

public func HandleConstantExpression(irBuilder: IRBuilder2, chirConst: Constant): LLVMValueRef {
    if (let Some(resultTy) <- chirConst.GetResultType()) {
        return irBuilder.CreateLiteralValue(chirConst.literal, resultTy)
    }
    return LLVMNullValue()
}

public func HandleLiteralValue(irBuilder: IRBuilder2, chirLiteral: LiteralValue): LLVMValueRef {
    return irBuilder.CreateLiteralValue(chirLiteral, chirLiteral.GetType().getOrThrow())
}
