package cangjie_compiler::codegen

import cangjie_compiler::chir.Expression

public func GenerateAllocate(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        let cgType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
        // Allocate yields a Ref<T> (a pointer to T). The stack slot must hold a T, so the alloca's
        // LLVM type is the pointee (T) -- the alloca instruction itself then produces the T* that
        // matches the Ref<T> result. Allocating the Ref type directly would yield a T** and break
        // the subsequent Load/Store (whose operand must be a pointer to the value type).
        if (let Some(elementType) <- cgType.GetPointerElementType()) {
            return irBuilder.CreateEntryAlloca(elementType, name: "alloca")
        }
        return irBuilder.CreateEntryAlloca(cgType, name: "alloca")
    }
    return LLVMNullValue()
}
