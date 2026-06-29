package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.InstanceOf
import cangjie_compiler::chir.Type

private let IS_SUBTYPE_INTRINSIC_NAME_FOR_INSTANCEOF: String = "llvm.cj.is.subtype"
private let IS_TUPLE_TYPE_OF_INTRINSIC_NAME: String = "llvm.cj.is.tupletype.of"
private let UG_TUPLE_KIND: UInt64 = 21u64

public func GenerateInstanceOf(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(instanceOf) <- (chirExpr as InstanceOf)) {
        let targetTypeInfo = irBuilder.CreateBitCast(irBuilder.CreateTypeInfo(instanceOf.GetType()),
            I8PtrType(irBuilder), name: "ti.i8")
        let objectTy = if (let Some(operandTy) <- instanceOf.GetObject().GetType()) {
            operandTy.StripAllRefs()
        } else {
            return LLVMNullValue()
        }
        let objectVal = irBuilder.GetCGModule().MaterializeValue(irBuilder, instanceOf.GetObject()).GetRawValue()
        if (objectTy.IsAny() || objectTy.IsGeneric()) {
            return GenerateAnyOrGenericInstanceOf(irBuilder, objectVal, targetTypeInfo)
        }
        if (objectTy.IsClass()) {
            return CallIsSubtype(irBuilder, GetTypeInfoFromObject(irBuilder, objectVal), targetTypeInfo)
        }
        if (objectTy.IsTuple()) {
            let instanceTypeInfo = if (CGType.GetOrCreate(irBuilder.GetCGModule(), objectTy).GetSize().isSome()) {
                irBuilder.CreateBitCast(irBuilder.CreateTypeInfo(objectTy), I8PtrType(irBuilder), name: "ti.i8")
            } else {
                unsafe { LLVMConstNull(I8PtrType(irBuilder)) }
            }
            return CallIsTupleTypeOf(irBuilder, objectVal, instanceTypeInfo, targetTypeInfo)
        }
        return CallIsSubtype(irBuilder,
            irBuilder.CreateBitCast(irBuilder.CreateTypeInfo(objectTy), I8PtrType(irBuilder), name: "ti.i8"),
            targetTypeInfo)
    }
    return LLVMNullValue()
}

private func GenerateAnyOrGenericInstanceOf(irBuilder: IRBuilder2, objectVal: LLVMValueRef,
    targetTypeInfo: LLVMValueRef): LLVMValueRef {
    let currentBlock = irBuilder.GetInsertBlock()
    if (currentBlock.isNull()) {
        return CallIsSubtype(irBuilder, GetTypeInfoFromObject(irBuilder, objectVal), targetTypeInfo)
    }
    let blocks = irBuilder.CreateAndInsertBasicBlocks(MakeInstanceOfBlockNames("isTuple", "nonTuple", "end"))
    if (blocks.size < 3) {
        return LLVMNullValue()
    }
    let instanceTypeInfo = GetTypeInfoFromObject(irBuilder, objectVal)
    let typeKind = GetTypeKindFromTypeInfo(irBuilder, instanceTypeInfo)
    let tupleKind = unsafe { LLVMConstInt(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), UG_TUPLE_KIND, 0) }
    let isTuple = irBuilder.CreateICmp(LLVMIntPredicate.EQ, typeKind, tupleKind, name: "is.tuple.kind")
    irBuilder.CreateCondBr(isTuple, blocks[0], blocks[1])

    irBuilder.SetInsertPoint(blocks[0])
    let nullTypeInfo = unsafe { LLVMConstNull(I8PtrType(irBuilder)) }
    let tupleResult = CallIsTupleTypeOf(irBuilder, objectVal, nullTypeInfo, targetTypeInfo)
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[1])
    let subtypeResult = CallIsSubtype(irBuilder, instanceTypeInfo, targetTypeInfo)
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[2])
    let resultPhi = irBuilder.CreatePHI(unsafe { LLVMInt1TypeInContext(irBuilder.GetLLVMContext().raw) },
        name: "instanceof")
    let values = ArrayList<LLVMValueRef>()
    values.add(tupleResult)
    values.add(subtypeResult)
    let incomingBlocks = ArrayList<LLVMBasicBlockRef>()
    incomingBlocks.add(blocks[0])
    incomingBlocks.add(blocks[1])
    irBuilder.AddIncoming(resultPhi, values, incomingBlocks)
    return resultPhi
}

private func GetTypeInfoFromObject(irBuilder: IRBuilder2, objectVal: LLVMValueRef): LLVMValueRef {
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
    let typeInfoSlotType = unsafe { LLVMPointerType(typeInfoPtrType, 1u32) }
    let typeInfoSlot = irBuilder.CreateBitCast(objectVal, typeInfoSlotType, name: "obj.ti.slot")
    return irBuilder.CreateBitCast(irBuilder.CreateLoad(typeInfoPtrType, typeInfoSlot, name: "ti"),
        I8PtrType(irBuilder), name: "ti.i8")
}

private func GetTypeKindFromTypeInfo(irBuilder: IRBuilder2, typeInfo: LLVMValueRef): LLVMValueRef {
    let typeInfoType = CGType.GetOrCreateTypeInfoType(irBuilder.GetLLVMContext())
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
    let typedTypeInfo = irBuilder.CreateBitCast(typeInfo, typeInfoPtrType, name: "ti.typed")
    let typeKindPtr = irBuilder.CreateStructGEP(typeInfoType, typedTypeInfo, 1u32, name: "ti.kind.ptr")
    return irBuilder.CreateLoad(unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }, typeKindPtr,
        name: "ti.kind")
}

private func CallIsSubtype(irBuilder: IRBuilder2, instanceTypeInfo: LLVMValueRef,
    targetTypeInfo: LLVMValueRef): LLVMValueRef {
    let args = ArrayList<LLVMValueRef>()
    args.add(instanceTypeInfo)
    args.add(targetTypeInfo)
    return irBuilder.CreateIntrinsicCall(IS_SUBTYPE_INTRINSIC_NAME_FOR_INSTANCEOF, ArrayList<LLVMTypeRef>(), args,
        name: "is.subtype")
}

private func CallIsTupleTypeOf(irBuilder: IRBuilder2, objectVal: LLVMValueRef, instanceTypeInfo: LLVMValueRef,
    targetTypeInfo: LLVMValueRef): LLVMValueRef {
    let args = ArrayList<LLVMValueRef>()
    args.add(objectVal)
    args.add(instanceTypeInfo)
    args.add(targetTypeInfo)
    let overloadTypes = ArrayList<LLVMTypeRef>()
    overloadTypes.add(unsafe { LLVMTypeOf(objectVal) })
    return irBuilder.CreateIntrinsicCall(IS_TUPLE_TYPE_OF_INTRINSIC_NAME, overloadTypes, args,
        name: "is.tuple.type.of")
}

private func I8PtrType(irBuilder: IRBuilder2): LLVMTypeRef {
    return unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
}

private func MakeInstanceOfBlockNames(first: String, second: String, third: String): ArrayList<String> {
    let names = ArrayList<String>()
    names.add(first)
    names.add(second)
    names.add(third)
    return names
}
