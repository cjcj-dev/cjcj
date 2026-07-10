package cjcj::codegen

import cjcj::chir.Lambda

public func GenerateLambdaExpression(irBuilder: IRBuilder2, lambdaExpr: Lambda): LLVMValueRef {
    let _ = irBuilder
    let id = lambdaExpr.GetIdentifier()
    throw IllegalStateException("ClosureConversion did not lower lambda before codegen: " + id)
}
