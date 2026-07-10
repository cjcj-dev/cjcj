package cjcj::codegen

import cjcj::chir.Allocate
import cjcj::chir.Expression
import cjcj::chir.ExprKind
import cjcj::option.OptimizationLevel

private let LLVM_ALLOCA_OPCODE: Int32 = 26
private let LLVM_POINTER_TYPE_KIND: Int32 = 12

public func HandleMemoryExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let kind = chirExpr.GetExprKind()
    if (kind == ExprKind.ALLOCATE || kind == ExprKind.ALLOCATE_WITH_EXCEPTION) {
        if (let Some(allocateExpr) <- (chirExpr as Allocate)) {
            if (let Some(retValueStorage) <- TryGetSpecialRetValueStorage(irBuilder, allocateExpr)) {
                return retValueStorage
            }
        }
        let result = GenerateAllocate(irBuilder, chirExpr)
        if (let Some(allocateExpr) <- (chirExpr as Allocate)) {
            TryEmitNullInitForDebugLocalClass(irBuilder, allocateExpr, result)
        }
        return result
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
    if (unsafe { LLVMSelfhostFunctionHasStructRetAttr(llvmFunc) } != 0) {
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

private func TryEmitNullInitForDebugLocalClass(irBuilder: IRBuilder2, allocateExpr: Allocate,
    result: LLVMValueRef): Unit {
    if (irBuilder.GetCGContext().GetCompileOptions().optimizationLevel != OptimizationLevel.O0) {
        return
    }
    let localVar = match (allocateExpr.GetResult()) {
        case Some(value) => value
        case None => return
    }
    if (localVar.GetSrcCodeIdentifier().isEmpty()) {
        return
    }
    let chirType = allocateExpr.GetType().StripAllRefs()
    if (!chirType.IsClass() || result.isNull() || unsafe { LLVMIsAInstruction(result) }.isNull() ||
        unsafe { LLVMGetInstructionOpcode(result) } != LLVM_ALLOCA_OPCODE) {
        return
    }

    let allocatedType = unsafe { LLVMGetAllocatedType(result) }
    if (allocatedType.isNull() || unsafe { LLVMGetTypeKind(allocatedType) } != LLVM_POINTER_TYPE_KIND) {
        return
    }
    let currentBlock = irBuilder.GetInsertBlock()
    if (currentBlock.isNull()) {
        return
    }
    let currentInsertPoint = unsafe { LLVMSelfhostGetInsertPointInstruction(irBuilder.GetBuilder().raw) }
    let currentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
    if (currentFunction.isNull()) {
        return
    }
    let entryBlock = unsafe { LLVMGetEntryBasicBlock(currentFunction) }
    let terminator = unsafe { LLVMGetBasicBlockTerminator(entryBlock) }
    if (terminator.isNull()) {
        return
    }
    try (debugLocGuard = TemporarilySetDebugLocInThisScope(irBuilder, LLVMNullMetadata())) {
        irBuilder.SetInsertPointBefore(terminator)
        let _ = irBuilder.CreateStore(unsafe { LLVMConstNull(allocatedType) }, result)
    }
    irBuilder.SetInsertPoint(currentBlock, currentInsertPoint)
}
