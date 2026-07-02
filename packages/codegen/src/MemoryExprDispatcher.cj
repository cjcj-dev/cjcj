package cangjie_compiler::codegen

import cangjie_compiler::chir.Allocate
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.ExprKind

public func HandleMemoryExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let kind = chirExpr.GetExprKind()
    if (kind == ExprKind.ALLOCATE || kind == ExprKind.ALLOCATE_WITH_EXCEPTION) {
        if (let Some(allocateExpr) <- (chirExpr as Allocate)) {
            if (let Some(retValueStorage) <- TryGetSpecialRetValueStorage(irBuilder, allocateExpr)) {
                return retValueStorage
            }
        }
        return GenerateAllocate(irBuilder, chirExpr)
    }
    if (kind == ExprKind.LOAD) {
        return GenerateLoad(irBuilder, chirExpr)
    }
    if (kind == ExprKind.STORE) {
        return GenerateStore(irBuilder, chirExpr)
    }
    if (kind == ExprKind.GET_ELEMENT_REF || kind == ExprKind.GET_ELEMENT_BY_NAME) {
        return GenerateGetElementRef(irBuilder, chirExpr)
    }
    if (kind == ExprKind.STORE_ELEMENT_REF || kind == ExprKind.STORE_ELEMENT_BY_NAME) {
        return GenerateStoreElementRef(irBuilder, chirExpr)
    }
    return LLVMNullValue()
}

private func TryGetSpecialRetValueStorage(irBuilder: IRBuilder2, allocateExpr: Allocate): Option<LLVMValueRef> {
    let parentFunc = allocateExpr.GetTopLevelFunc() ?? return None
    let resultValue = allocateExpr.GetResult() ?? return None
    let returnValue = parentFunc.GetReturnValue() ?? return None
    if (returnValue.nodeId != resultValue.nodeId) {
        return None
    }

    let llvmFunc = irBuilder.GetCGModule().GetOrInsertCGFunction(parentFunc).GetRawFunction()
    if (HasAttributeAtIndex(llvmFunc, 1u32, "sret")) {
        return Some(unsafe { LLVMGetParam(llvmFunc, 0u32) })
    }

    let overrideSrcFuncType = parentFunc.GetOverrideSrcFuncType() ?? return None
    if (!allocateExpr.GetType().StripAllRefs().IsBox()) {
        return None
    }
    let retValueCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), overrideSrcFuncType.GetReturnType())
    if (retValueCGType.GetSize().isSome()) {
        return Some(irBuilder.CreateEntryAlloca(retValueCGType))
    }
    return None
}
