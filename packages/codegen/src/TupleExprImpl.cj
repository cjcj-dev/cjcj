package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.EnumType
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TupleType

public func GenerateTupleOrAggregateExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        if (let Some(_) <- (resultTy as EnumType)) {
            if (let Some(enumCGType) <- (CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy) as CGEnumType)) {
                if (enumCGType.IsCommonEnum()) {
                    return GenerateCommonEnum(irBuilder, chirExpr)
                }
                if (enumCGType.IsOptionLikeRef()) {
                    return GenerateOptionLikeRefEnum(irBuilder, chirExpr, resultTy)
                }
                if (enumCGType.IsOptionLikeNonRef()) {
                    return GenerateOptionLikeNonRefEnum(irBuilder, chirExpr, resultTy, enumCGType)
                }
                if (enumCGType.IsZeroSizeEnum()) {
                    return irBuilder.CreateEntryAlloca(enumCGType, name: "enum.val")
                }
                if (enumCGType.IsAllAssociatedValuesAreNonRef()) {
                    return GenerateAssociatedNonRefEnum(irBuilder, chirExpr, enumCGType)
                }
            }
        }
        let resultCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
        if (resultTy.StripAllRefs().IsTuple()) {
            return GenerateNativeTuple(irBuilder, chirExpr, resultTy, resultCGType)
        }
        if (resultTy.StripAllRefs().IsStruct()) {
            return GenerateNativeStruct(irBuilder, chirExpr, resultTy, resultCGType)
        }
        return GenerateAggregateValue(irBuilder, chirExpr, resultCGType)
    }
    return LLVMNullValue()
}

private func GenerateNativeTuple(irBuilder: IRBuilder2, chirExpr: Expression, resultTy: Type,
    resultCGType: CGType): LLVMValueRef {
    let resultValue = irBuilder.CreateEntryAlloca(resultCGType)
    let resultAddr = CGValue(resultValue, GetRefCGType(irBuilder, resultTy))
    let containedTypes = resultCGType.GetContainedTypes()
    var idx: Int64 = 0
    while (idx < chirExpr.GetNumOfOperands()) {
        let operand = chirExpr.GetOperand(idx)
        let operandValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, operand)
        if (idx < containedTypes.size) {
            let fieldTy = containedTypes[idx].GetOriginal()
            let fieldPtr = irBuilder.CreateStructGEP(resultCGType.GetLLVMType(), resultValue, UInt32(idx),
                name: "tuple.field")
            let fieldAddr = CGValue(fieldPtr, GetRefCGType(irBuilder, fieldTy))
            CreateTypedStoreForAddress(irBuilder, operandValue, fieldAddr)
        } else {
            let indices = ArrayList<LLVMValueRef>()
            indices.add(LLVMConstI32(irBuilder, 0u64))
            indices.add(LLVMConstI32(irBuilder, UInt64(idx)))
            let fieldPtr = irBuilder.CreateGEP(resultCGType.GetLLVMType(), resultAddr.GetRawValue(), indices,
                name: "tuple.field")
            let fieldTy = operand.GetType() ?? resultTy
            let fieldAddr = CGValue(fieldPtr, GetRefCGType(irBuilder, fieldTy))
            CreateTypedStoreForAddress(irBuilder, operandValue, fieldAddr)
        }
        idx++
    }
    return resultValue
}

private func GenerateNativeStruct(irBuilder: IRBuilder2, chirExpr: Expression, _: Type,
    resultCGType: CGType): LLVMValueRef {
    let resultValue = irBuilder.CreateEntryAlloca(resultCGType, name: "struct")
    let containedTypes = resultCGType.GetContainedTypes()
    var idx: Int64 = 0
    while (idx < chirExpr.GetNumOfOperands()) {
        let operandValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(idx))
        if (idx < containedTypes.size) {
            let fieldTy = containedTypes[idx].GetOriginal()
            let fieldPtr = irBuilder.CreateStructGEP(resultCGType.GetLLVMType(), resultValue, UInt32(idx),
                name: "struct.field")
            let fieldAddr = CGValue(fieldPtr, GetRefCGType(irBuilder, fieldTy))
            CreateTypedStoreForAddress(irBuilder, operandValue, fieldAddr)
        }
        idx++
    }
    return resultValue
}

private func GenerateAssociatedNonRefEnum(irBuilder: IRBuilder2, chirExpr: Expression,
    enumCGType: CGEnumType): LLVMValueRef {
    let enumValue = irBuilder.CreateEntryAlloca(enumCGType, name: "enum.val")
    let containedTypes = enumCGType.GetContainedTypes()
    var idx: Int64 = 0
    while (idx < chirExpr.GetNumOfOperands()) {
        let operandValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(idx))
        if (idx < containedTypes.size) {
            let fieldTy = containedTypes[idx].GetOriginal()
            let fieldPtr = irBuilder.CreateStructGEP(enumCGType.GetLLVMType(), enumValue, UInt32(idx),
                name: "enum.field")
            let fieldAddr = CGValue(fieldPtr, GetRefCGType(irBuilder, fieldTy))
            CreateTypedStoreForAddress(irBuilder, operandValue, fieldAddr)
        }
        idx++
    }
    return enumValue
}

private func GenerateAggregateValue(irBuilder: IRBuilder2, chirExpr: Expression, resultCGType: CGType):
    LLVMValueRef {
    let containedTypes = resultCGType.GetContainedTypes()
    let elements = ArrayList<LLVMValueRef>()
    var idx: Int64 = 0
    while (idx < chirExpr.GetNumOfOperands()) {
        let operand = chirExpr.GetOperand(idx)
        let operandValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, operand)
        var rawValue = operandValue.GetRawValue()
        if (idx < containedTypes.size) {
            let storageTy = containedTypes[idx].GetOriginal()
            if (let Some(sourceTy) <- operand.GetType()) {
                rawValue = LoadRefAggregateElementIfNeeded(irBuilder, rawValue, sourceTy, storageTy)
            }
        }
        elements.add(rawValue)
        idx++
    }
    return irBuilder.CreateAggregateValue(resultCGType.GetLLVMType(), elements, name: chirExpr.GetExprKindName())
}

private func GenerateCommonEnum(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    let fieldTys = ArrayList<Type>()
    var idx: Int64 = 0
    while (idx < chirExpr.GetNumOfOperands()) {
        if (let Some(fieldTy) <- chirExpr.GetOperand(idx).GetType()) {
            fieldTys.add(CommonEnumStorageFieldType(idx, fieldTy))
        } else {
            return LLVMNullValue()
        }
        idx++
    }
    let storageTy = TupleType(fieldTys)
    let storageCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), storageTy)
    let layoutType = storageCGType.GetLLVMType()
    let enumVal = CallCommonEnumObjectAlloc(irBuilder, storageTy, layoutType)
    if (enumVal.isNull()) {
        return enumVal
    }
    let payload = irBuilder.GetPayloadFromObject(enumVal)
    let typedPayload = irBuilder.CreateBitCast(payload, unsafe { LLVMPointerType(layoutType, 1u32) },
        name: "enum.payload")
    let containedTypes = storageCGType.GetContainedTypes()
    idx = 0
    while (idx < chirExpr.GetNumOfOperands()) {
        let operand = chirExpr.GetOperand(idx)
        var rawValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, operand).GetRawValue()
        if (idx < containedTypes.size) {
            let storageFieldTy = containedTypes[idx].GetOriginal()
            if (let Some(sourceTy) <- operand.GetType()) {
                rawValue = LoadRefAggregateElementIfNeeded(irBuilder, rawValue, sourceTy, storageFieldTy)
            }
        }
        let fieldTy = containedTypes[idx].GetOriginal()
        let fieldPtr = irBuilder.CreateStructGEP(layoutType, typedPayload, UInt32(idx), name: "enum.field")
        if (IsGCRefPayloadField(irBuilder, fieldTy)) {
            let _ = irBuilder.CallGCWriteRef(rawValue, enumVal, fieldPtr)
        } else if (IsValueAggregatePointerPayload(rawValue, fieldTy)) {
            let _ = StoreValueAggregatePointerPayload(irBuilder, enumVal, rawValue, fieldPtr, fieldTy)
        } else {
            let _ = irBuilder.CreateStore(rawValue, fieldPtr)
        }
        idx++
    }
    return enumVal
}

private func CommonEnumStorageFieldType(index: Int64, operandTy: Type): Type {
    if (index == 0) {
        return operandTy
    }
    return operandTy.StripAllRefs()
}

private func LoadRefAggregateElementIfNeeded(irBuilder: IRBuilder2, rawValue: LLVMValueRef, sourceTy: Type,
    storageTy: Type): LLVMValueRef {
    if (!sourceTy.IsRef() || !sourceTy.StripAllRefs().IsEqual(storageTy)) {
        return CastAggregateElementIfNeeded(irBuilder, rawValue, sourceTy, storageTy)
    }
    return irBuilder.CreateLoad(CGType.GetOrCreate(irBuilder.GetCGModule(), storageTy).GetLLVMType(), rawValue,
        name: "enum.field.load")
}

private func IsGCRefPayloadField(irBuilder: IRBuilder2, fieldTy: Type): Bool {
    let stripped = fieldTy.StripAllRefs()
    if (stripped.IsReferenceType()) {
        return true
    }
    if (let Some(enumCGType) <- (CGType.GetOrCreate(irBuilder.GetCGModule(), stripped) as CGEnumType)) {
        return enumCGType.IsCommonEnum() || enumCGType.IsOptionLikeRef()
    }
    return false
}

private func IsValueAggregatePointerPayload(rawValue: LLVMValueRef, fieldTy: Type): Bool {
    let stripped = fieldTy.StripAllRefs()
    if (!(stripped.IsStruct() || stripped.IsTuple() || stripped.IsVArray())) {
        return false
    }
    let rawTy = unsafe { LLVMTypeOf(rawValue) }
    return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 12
}

private func StoreValueAggregatePointerPayload(irBuilder: IRBuilder2, enumVal: LLVMValueRef, rawValue: LLVMValueRef,
    fieldPtr: LLVMValueRef, fieldTy: Type): LLVMValueRef {
    let fieldCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), fieldTy.StripAllRefs())
    let fieldLLVMType = fieldCGType.GetLLVMType()
    let size = unsafe {
        LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw),
            irBuilder.GetCGModule().GetTypeSize(fieldLLVMType), 0)
    }
    let align = irBuilder.GetCGModule().GetABITypeAlignment(fieldLLVMType)
    if (irBuilder.IsLLVMTypeContainsRef(fieldLLVMType)) {
        return irBuilder.CallGCWriteStruct(enumVal, fieldPtr, rawValue, size, fieldCGType.GetOriginal().ToString())
    }
    return irBuilder.CreateMemCpy(fieldPtr, align, rawValue, align, size)
}

private func CallCommonEnumObjectAlloc(irBuilder: IRBuilder2, storageTy: Type, layoutType: LLVMTypeRef): LLVMValueRef {
    let typeInfo = CGType.GetOrCreate(irBuilder.GetCGModule(), storageTy).GetOrCreateTypeInfo()
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
    let typeInfoArg = irBuilder.CreateBitCast(typeInfo, i8PtrType, name: "enum.ti")
    let sizeArg = unsafe {
        LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw),
            irBuilder.GetCGModule().GetTypeSize(layoutType), 0)
    }
    let args = ArrayList<LLVMValueRef>()
    args.add(typeInfoArg)
    args.add(sizeArg)
    let objectValue = irBuilder.CreateIntrinsicCall("llvm.cj.malloc.object", ArrayList<LLVMTypeRef>(), args,
        name: "enum.alloc")
    if (!objectValue.isNull()) {
        AddRetAttr(objectValue, "noalias")
    }
    return objectValue
}

private func GenerateOptionLikeRefEnum(irBuilder: IRBuilder2, chirExpr: Expression, _: Type): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() <= 1) {
        return unsafe { LLVMConstNull(CGType.GetRefType(irBuilder.GetLLVMContext())) }
    }
    let associatedOperand = chirExpr.GetOperand(1)
    return irBuilder.GetCGModule().MaterializeValue(irBuilder, associatedOperand).GetRawValue()
}

private func GenerateOptionLikeNonRefEnum(irBuilder: IRBuilder2, chirExpr: Expression, resultTy: Type,
    enumCGType: CGEnumType): LLVMValueRef {
    let hasAssociatedValue = chirExpr.GetNumOfOperands() > 1
    if (enumCGType.GetSize().isSome()) {
        let enumValue = irBuilder.CreateEntryAlloca(enumCGType, name: "enum.val")
        if (chirExpr.GetNumOfOperands() > 0) {
            let selectorValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0))
            let selectorTy = chirExpr.GetOperand(0).GetType() ??
                irBuilder.GetCGContext().GetCHIRBuilder().context.GetBoolTy()
            let selectorPtr = irBuilder.CreateStructGEP(enumCGType.GetLLVMType(), enumValue, 0u32)
            let selectorAddr = CGValue(selectorPtr, GetRefCGType(irBuilder, selectorTy))
            CreateTypedStoreForAddress(irBuilder, selectorValue, selectorAddr)
        }
        let associatedValueType = enumCGType.GetAssociatedValueTypeOfOptionLike() ?? return enumValue
        let recordValue = if (hasAssociatedValue) {
            irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(1))
        } else {
            CGValue(irBuilder.CreateNullValue(associatedValueType),
                CGType.GetOrCreate(irBuilder.GetCGModule(), associatedValueType))
        }
        let associatedPtr = irBuilder.CreateStructGEP(enumCGType.GetLLVMType(), enumValue, 1u32)
        irBuilder.CreateStore(recordValue.GetRawValue(), associatedPtr, associatedValueType)
        return enumValue
    }
    let enumType = (resultTy as EnumType) ?? return LLVMNullValue()
    let enumTypeInfo = irBuilder.CreateTypeInfo(enumType)
    let enumValue = irBuilder.CallAllocaGeneric(enumType)
    let payload = irBuilder.GetPayloadFromObject(enumValue)
    if (chirExpr.GetNumOfOperands() > 0) {
        let selectorValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(0)).GetRawValue()
        let selectorPtr = irBuilder.CreateBitCast(payload,
            unsafe { LLVMPointerType(LLVMInt1TypeInContext(irBuilder.GetLLVMContext().raw), 1u32) })
        irBuilder.CreateStore(selectorValue, selectorPtr)
    }
    if (hasAssociatedValue) {
        let associatedOffset = irBuilder.CallGetFieldOffset(enumTypeInfo, 1u64, 0u64)
        let indices = ArrayList<LLVMValueRef>()
        indices.add(associatedOffset)
        let i8Type = unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 1u32) }
        let associatedPtr = irBuilder.CreateGEP(i8Type, irBuilder.CreateBitCast(payload, i8PtrType), indices)
        let associatedValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, chirExpr.GetOperand(1))
        let associatedType = chirExpr.GetOperand(1).GetType() ?? return enumValue
        let associatedCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), associatedType)
        irBuilder.CallGCWriteGeneric(enumValue, associatedPtr, associatedValue.GetRawValue(),
            irBuilder.GetSize32(associatedType, associatedCGType))
    }
    return enumValue
}

private func CastAggregateElementIfNeeded(irBuilder: IRBuilder2, rawValue: LLVMValueRef, sourceTy: Type,
    storageTy: Type): LLVMValueRef {
    if (sourceTy.IsEqual(storageTy)) {
        return rawValue
    }
    let storageLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), storageTy).GetLLVMType()
    return CastValueToType(irBuilder, rawValue, sourceTy, storageTy, storageLLVMType)
}

private func GetRefCGType(irBuilder: IRBuilder2, ty: Type): CGType {
    return CGType.GetOrCreate(irBuilder.GetCGModule(), irBuilder.GetCGContext().GetCHIRBuilder().context.GetRefTy(ty))
}

private func LLVMConstI32(irBuilder: IRBuilder2, value: UInt64): LLVMValueRef {
    return unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), value, 0) }
}
