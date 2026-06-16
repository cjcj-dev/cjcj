package cangjie_compiler::codegen

import cangjie_compiler::chir.Expression

public func GenerateAllocate(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        let cgType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
        return irBuilder.CreateEntryAlloca(cgType, name: "alloca")
    }
    return LLVMNullValue()
}
