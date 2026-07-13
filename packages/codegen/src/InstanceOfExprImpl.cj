package cjcj::codegen

import std.collection.*
import cjcj::chir.Expression
import cjcj::chir.InstanceOf

public func GenerateInstanceOf(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(instanceOf) <- (chirExpr as InstanceOf)) {
        let targetTypeInfo = irBuilder.CreateTypeInfo(instanceOf.GetType())
        let objectTy = if (let Some(operandTy) <- instanceOf.GetObject().GetType()) {
            DeRef(operandTy)
        } else {
            return LLVMNullValue()
        }
        let objectVal = irBuilder.GetCGModule().GetMappedCGValue(instanceOf.GetObject()).GetRawValue()
        if (objectTy.IsAny() || objectTy.IsGeneric()) {
            let instanceTypeInfo = irBuilder.GetTypeInfoFromObject(objectVal)
            let typeKind = irBuilder.GetTypeKindFromTypeInfo(instanceTypeInfo)
            let tupleKind = unsafe {
                LLVMConstInt(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw),
                    21u64, 0)
            }
            let isTuple = irBuilder.CreateICmp(LLVMIntPredicate.EQ, typeKind, tupleKind, name: "is.tuple.kind")
            let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>(["isTuple", "nonTuple", "end"]))
            irBuilder.CreateCondBr(isTuple, blocks[0], blocks[1])

            irBuilder.SetInsertPoint(blocks[0])
            let i8PtrType = unsafe {
                LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32)
            }
            let nullTypeInfo = unsafe { LLVMConstNull(i8PtrType) }
            let tupleResult = irBuilder.CallIntrinsicIsTupleTypeOf(
                ArrayList<LLVMValueRef>([objectVal, nullTypeInfo, targetTypeInfo]))
            irBuilder.CreateBr(blocks[2])

            irBuilder.SetInsertPoint(blocks[1])
            let subtypeResult = irBuilder.CallIntrinsicIsSubtype(
                ArrayList<LLVMValueRef>([instanceTypeInfo, targetTypeInfo]))
            irBuilder.CreateBr(blocks[2])

            irBuilder.SetInsertPoint(blocks[2])
            let resultPhi = irBuilder.CreatePHI(unsafe { LLVMInt1TypeInContext(irBuilder.GetLLVMContext().raw) },
                name: "instanceof")
            irBuilder.AddIncoming(resultPhi, ArrayList<LLVMValueRef>([tupleResult, subtypeResult]),
                ArrayList<LLVMBasicBlockRef>([blocks[0], blocks[1]]))
            return resultPhi
        } else if (objectTy.IsClass()) {
            let instanceTypeInfo = irBuilder.GetTypeInfoFromObject(objectVal)
            return irBuilder.CallIntrinsicIsSubtype(
                ArrayList<LLVMValueRef>([instanceTypeInfo, targetTypeInfo]))
        } else if (objectTy.IsTuple()) {
            let i8PtrType = unsafe {
                LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32)
            }
            let instanceTypeInfo = if (CGType.GetOrCreate(irBuilder.GetCGModule(), objectTy).GetSize().isSome()) {
                irBuilder.CreateTypeInfo(objectTy)
            } else {
                unsafe { LLVMConstNull(i8PtrType) }
            }
            return irBuilder.CallIntrinsicIsTupleTypeOf(
                ArrayList<LLVMValueRef>([objectVal, instanceTypeInfo, targetTypeInfo]))
        }
        return irBuilder.CallIntrinsicIsSubtype(
            ArrayList<LLVMValueRef>([irBuilder.CreateTypeInfo(objectTy), targetTypeInfo]))
    }
    return LLVMNullValue()
}
