package cjcj::codegen

import std.collection.*
import cjcj::chir.Allocate
import cjcj::chir.AllocateWithException
import cjcj::chir.ClassType
import cjcj::chir.Expression
import cjcj::chir.Type

public func GenerateAllocate(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let allocatedTy: Option<Type> = if (let Some(allocateExpr) <- (chirExpr as Allocate)) {
        Some(allocateExpr.GetType())
    } else if (let Some(allocateWithException) <- (chirExpr as AllocateWithException)) {
        Some(allocateWithException.GetType())
    } else {
        None
    }
    if (let Some(actualAllocatedTy) <- allocatedTy) {
        if (actualAllocatedTy.IsClass()) {
            let obj = irBuilder.CallClassIntrinsicAlloc(actualAllocatedTy)
            if (IsAutoEnvType(actualAllocatedTy)) {
                InitializeAutoEnvCallableAbi(irBuilder, obj, actualAllocatedTy)
            }
            return obj
        }
        let cgType = CGType.GetOrCreate(irBuilder.GetCGModule(), actualAllocatedTy)
        return irBuilder.CreateEntryAlloca(cgType, name: "alloca")
    }
    return LLVMNullValue()
}

private func InitializeAutoEnvCallableAbi(irBuilder: IRBuilder2, obj: LLVMValueRef, allocatedTy: Type): Unit {
    let classTy = (allocatedTy as ClassType) ?? return
    let payload = irBuilder.GetPayloadFromObject(obj)
    let i8Type = unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let i8PtrSlotType = unsafe { LLVMPointerType(i8PtrType, 1u32) }
    let typedPayload = irBuilder.CreateBitCast(payload, i8PtrSlotType, name: "autoenv.payload")
    let methods = classTy.GetClassDef().GetMethods()
    var idx: Int64 = 0
    while (idx < methods.size) {
        let rawMethod = irBuilder.GetCGModule().GetOrInsertCGFunction(methods[idx]).GetRawFunction()
        let methodPtr = irBuilder.CreateBitCast(rawMethod, i8PtrType, name: "autoenv.method")
        let indices = ArrayList<LLVMValueRef>()
        indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), UInt64(idx), 0) })
        let slot = irBuilder.CreateInBoundsGEP(i8PtrType, typedPayload, indices, name: "autoenv.method.addr")
        irBuilder.CreateStore(methodPtr, slot)
        idx++
    }
}
