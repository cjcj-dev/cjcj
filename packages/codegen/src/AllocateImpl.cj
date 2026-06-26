package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Allocate
import cangjie_compiler::chir.ClassDef
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Type

public func GenerateAllocate(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(allocateExpr) <- (chirExpr as Allocate)) {
        let allocatedTy = allocateExpr.GetType()
        if (allocatedTy.IsClass()) {
            let obj = irBuilder.CallClassIntrinsicAlloc(allocatedTy)
            if (IsAutoEnvType(allocatedTy)) {
                InitializeAutoEnvCallableAbi(irBuilder, obj, allocatedTy)
            }
            return obj
        }
    }
    if (IsGenericSRetReturnSlot(irBuilder, chirExpr)) {
        if (let Some(cgFunc) <- irBuilder.GetInsertCGFunction()) {
            let bodyBlock = irBuilder.CreateAndInsertBasicBlock("sret.entry")
            if (!bodyBlock.isNull()) {
                irBuilder.CreateBr(bodyBlock)
                irBuilder.SetInsertPoint(bodyBlock)
            }
            return unsafe { LLVMGetParam(cgFunc.GetRawFunction(), 0u32) }
        }
    }
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

private func IsGenericSRetReturnSlot(irBuilder: IRBuilder2, chirExpr: Expression): Bool {
    let resultValue = chirExpr.GetResult() ?? return false
    let cgFunc = irBuilder.GetInsertCGFunction() ?? return false
    if (!cgFunc.IsSRet()) {
        return false
    }
    let topLevelFunc = chirExpr.GetTopLevelFunc() ?? return false
    let returnValue = topLevelFunc.GetReturnValue() ?? return false
    if (returnValue.nodeId != resultValue.nodeId) {
        return false
    }
    let returnTy = topLevelFunc.GetReturnType() ?? return false
    return returnTy.IsGeneric()
}

private func InitializeAutoEnvCallableAbi(irBuilder: IRBuilder2, obj: LLVMValueRef, allocatedTy: Type): Unit {
    let classTy = (allocatedTy as ClassType) ?? return
    let payload = irBuilder.GetPayloadFromObject(obj)
    let i8Type = unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let i8PtrSlotType = unsafe { LLVMPointerType(i8PtrType, 1u32) }
    let typedPayload = irBuilder.CreateBitCast(payload, i8PtrSlotType, name: "autoenv.payload")
    var idx: Int64 = 0
    while (idx < 2) {
        let implMethod = FindAutoEnvCallableImplementationMethod(classTy, idx) ?? break
        let rawMethod = if (let Some(expectedMethod) <- FindAutoEnvCallableExpectedMethod(classTy, idx)) {
            GetOrCreateExpectedVirtualSlotWrapper(irBuilder.GetCGModule(), implMethod, expectedMethod)
        } else {
            irBuilder.GetCGModule().GetOrInsertCGFunction(implMethod).GetRawFunction()
        }
        let methodPtr = irBuilder.CreateBitCast(rawMethod, i8PtrType, name: "autoenv.method")
        let indices = ArrayList<LLVMValueRef>()
        indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(idx), 0) })
        let slot = irBuilder.CreateGEP(i8PtrType, typedPayload, indices, name: "autoenv.method.addr")
        irBuilder.CreateStore(methodPtr, slot)
        idx++
    }
}

private func FindAutoEnvCallableImplementationMethod(classTy: ClassType, idx: Int64): Option<Function> {
    let methods = classTy.GetClassDef().GetMethods()
    if (idx >= 0 && idx < methods.size) {
        return Some(methods[idx])
    }
    return None
}

private func FindAutoEnvCallableExpectedMethod(classTy: ClassType, idx: Int64): Option<Function> {
    if (idx == 0) {
        return FindAutoEnvGenericBaseMethod(classTy.GetClassDef())
    }
    if (idx == 1) {
        if (let Some(superDef) <- classTy.GetClassDef().GetSuperClassDef()) {
            if (superDef.GetAnnotation("IsAutoEnvInstBase").isSome()) {
                let methods = superDef.GetMethods()
                if (!methods.isEmpty()) {
                    return Some(methods[0])
                }
            }
        }
    }
    return None
}

private func FindAutoEnvGenericBaseMethod(classDef: ClassDef): Option<Function> {
    if (classDef.GetAnnotation("IsAutoEnvGenericBase").isSome()) {
        let methods = classDef.GetMethods()
        if (!methods.isEmpty()) {
            return Some(methods[0])
        }
        return None
    }
    if (let Some(superDef) <- classDef.GetSuperClassDef()) {
        return FindAutoEnvGenericBaseMethod(superDef)
    }
    return None
}
