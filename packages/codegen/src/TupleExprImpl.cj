package cjcj::codegen

import std.collection.*
import cjcj::chir.Constant
import cjcj::chir.EnumType
import cjcj::chir.ExprKind
import cjcj::chir.Expression
import cjcj::chir.LocalVar
import cjcj::chir.Tuple
import cjcj::chir.Type
import cjcj::utils.StaticCast

public func GenerateTupleOrAggregateExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(resultTy) <- chirExpr.GetResultType()) {
        if (let Some(_) <- (resultTy as EnumType)) {
            if (let Some(enumCGType) <- (CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy) as CGEnumType)) {
                if (enumCGType.IsCommonEnum()) {
                    return GenerateCommonEnum(irBuilder, chirExpr)
                }
                if (enumCGType.IsOptionLikeT()) {
                    return GenerateOptionLikeTEnum(irBuilder, chirExpr, resultTy)
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
                if (enumCGType.IsTrivial()) {
                    return LLVMNullValue()
                }
            }
        }
        let resultCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
        if (resultTy.StripAllRefs().IsTuple()) {
            return GenerateNativeTuple(irBuilder, (chirExpr as Tuple).getOrThrow())
        }
        if (resultTy.StripAllRefs().IsStruct()) {
            return GenerateNativeStruct(irBuilder, chirExpr, resultTy, resultCGType)
        }
        return GenerateAggregateValue(irBuilder, chirExpr, resultCGType)
    }
    return LLVMNullValue()
}

private func GenerateNativeTuple(irBuilder: IRBuilder2, tupleExpr: Tuple): LLVMValueRef {
    let resultTy = tupleExpr.GetResultType().getOrThrow()
    let resultCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
    let constantTuple = IsConstantTuple(tupleExpr)
    if (constantTuple[0]) {
        let constants = ArrayList<LLVMValueRef>()
        var constantIdx: Int64 = 0
        while (constantIdx < tupleExpr.GetNumOfOperands()) {
            let raw = irBuilder.GetCGModule().GetMappedCGValue(tupleExpr.GetOperand(constantIdx)).GetRawValue()
            if (!unsafe { LLVMIsAGlobalVariable(raw) }.isNull()) {
                constants.add(unsafe { LLVMGetInitializer(raw) })
            } else {
                constants.add(raw)
            }
            constantIdx++
        }
        var constVal = LLVMNullValue()
        if (constants.isEmpty()) {
            constVal = unsafe { LLVMConstNamedStruct(resultCGType.GetLLVMType(), CPointer<LLVMValueRef>(), 0u32) }
        } else {
            try (valuePtr = LibC.malloc<LLVMValueRef>(count: constants.size).asResource()) {
                var idx: Int64 = 0
                while (idx < constants.size) {
                    unsafe { (valuePtr.value + idx).write(constants[idx]) }
                    idx++
                }
                constVal = unsafe { LLVMConstNamedStruct(resultCGType.GetLLVMType(), valuePtr.value,
                    UInt32(constants.size)) }
            }
        }
        return irBuilder.GetCGModule().GetOrCreateGlobalVariable(constVal, constantTuple[1], true)
    }
    let resultValue = irBuilder.CreateEntryAlloca(resultCGType)
    let resultAddr = CGValue(resultValue, GetRefCGType(irBuilder, resultTy))
    var idx: Int64 = 0
    while (idx < tupleExpr.GetNumOfOperands()) {
        let operand = tupleExpr.GetOperand(idx)
        let operandValue = irBuilder.GetCGModule().GetMappedCGValue(operand)
        let fieldAddr = irBuilder.CreateGEP(resultAddr, ArrayList<UInt64>([UInt64(idx)]))
        let resultValueType = unsafe { LLVMTypeOf(resultValue) }
        if (unsafe { LLVMGetPointerAddressSpace(resultValueType) } == 1u32) {
            irBuilder.GetCGContext().SetBasePtr(fieldAddr.GetRawValue(), resultValue)
        }
        irBuilder.CreateStore(operandValue, fieldAddr)
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
        let operandValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(idx))
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
    let i8Type = unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }
    let casted = irBuilder.CreateBitCast(enumValue, unsafe { LLVMPointerType(i8Type, 0u32) })
    let fieldTypes = CollectAssociatedNonRefFieldTypes(chirExpr)
    let useStructGEP = CGEnumType.NeedAndroidArm32AlignedEnumLayout(
        irBuilder.GetCGContext().GetCompileOptions().target)
    var layoutType = LLVMNullType()
    var castedStruct = LLVMNullValue()
    if (useStructGEP) {
        layoutType = CGEnumType.GetAndroidArm32AssociatedNonRefLayoutType(irBuilder.GetCGModule(), fieldTypes)
        castedStruct = irBuilder.CreateBitCast(enumValue, unsafe { LLVMPointerType(layoutType, 0u32) })
    }
    let layout = CGEnumType.ComputeAssociatedNonRefLayout(irBuilder.GetCGModule(), fieldTypes)
    var idx: Int64 = 0
    while (idx < chirExpr.GetNumOfOperands()) {
        let field = chirExpr.GetOperand(idx)
        let fieldCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), field.GetType().getOrThrow())
        let destPtr = if (useStructGEP) {
            irBuilder.CreateStructGEP(layoutType, castedStruct, UInt32(idx))
        } else {
            irBuilder.CreateConstGEP1_32(i8Type, casted, layout.offsets[idx])
        }
        let castedDestPtr = irBuilder.CreateBitCast(destPtr,
            unsafe { LLVMPointerType(fieldCGType.GetLLVMType(), 0u32) })
        let fieldValue = irBuilder.GetCGModule().GetMappedCGValue(field)
        irBuilder.CreateStore(fieldValue.GetRawValue(), castedDestPtr, field.GetType().getOrThrow())
        idx++
    }
    return enumValue
}

private func CollectAssociatedNonRefFieldTypes(chirExpr: Expression): ArrayList<Type> {
    let fieldTypes = ArrayList<Type>()
    var idx: Int64 = 0
    while (idx < chirExpr.GetNumOfOperands()) {
        fieldTypes.add(chirExpr.GetOperand(idx).GetType().getOrThrow())
        idx++
    }
    return fieldTypes
}

private func GenerateAggregateValue(irBuilder: IRBuilder2, chirExpr: Expression, resultCGType: CGType):
    LLVMValueRef {
    let containedTypes = resultCGType.GetContainedTypes()
    let elements = ArrayList<LLVMValueRef>()
    var idx: Int64 = 0
    while (idx < chirExpr.GetNumOfOperands()) {
        let operand = chirExpr.GetOperand(idx)
        let operandValue = irBuilder.GetCGModule().GetMappedCGValue(operand)
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
    let cgMod = irBuilder.GetCGModule()
    let cgCtx = cgMod.GetCGContext()
    let enumType = StaticCast<EnumType>(chirExpr.GetResultType().getOrThrow())
    let enumIdxExpr = StaticCast<Constant>(StaticCast<LocalVar>(chirExpr.GetOperand(0)).GetExpr().getOrThrow())
    var enumCaseTi = cgMod.GetOrCreateEnumCtorTIOrTT(enumType, Int64(enumIdxExpr.GetUnsignedIntLitVal()))
    let genericArgs = GetGenericArgsFromCHIRType(enumType)
    if (!genericArgs.isEmpty()) {
        let typeArgs = ArrayList<Type>()
        for (typeArg in GetGenericArgsFromCHIRType(enumType.GetEnumDef().GetType().getOrThrow())) {
            typeArgs.add(GetTypeInnerType(enumType, typeArg))
        }
        let typeArgsArr = irBuilder.CreateTypeInfoArray(typeArgs)
        let getTypeInfoArgs = ArrayList<LLVMValueRef>()
        getTypeInfoArgs.add(enumCaseTi)
        getTypeInfoArgs.add(irBuilder.GetInt32(typeArgs.size))
        getTypeInfoArgs.add(typeArgsArr)
        enumCaseTi = irBuilder.CallIntrinsicGetTypeInfo(getTypeInfoArgs)
    }
    let allocArgs = ArrayList<LLVMValueRef>()
    allocArgs.add(enumCaseTi)
    allocArgs.add(irBuilder.GetSizeFromTypeInfo(enumCaseTi))
    let enumVal = irBuilder.CallClassIntrinsicAlloc(allocArgs)
    if (genericArgs.isEmpty()) {
        let elemTypes = ArrayList<LLVMTypeRef>()
        var idx: Int64 = 0
        while (idx < chirExpr.GetNumOfOperands()) {
            elemTypes.add(CGType.GetOrCreate(cgMod, chirExpr.GetOperand(idx).GetType().getOrThrow()).GetLLVMType())
            idx++
        }
        var layoutType = LLVMNullType()
        try (elemTypePtr = LibC.malloc<LLVMTypeRef>(count: elemTypes.size).asResource()) {
            idx = 0
            while (idx < elemTypes.size) {
                unsafe { (elemTypePtr.value + idx).write(elemTypes[idx]) }
                idx++
            }
            layoutType = unsafe {
                LLVMStructTypeInContext(irBuilder.GetLLVMContext().raw, elemTypePtr.value, UInt32(elemTypes.size), 0)
            }
        }
        let payload = irBuilder.GetPayloadFromObject(enumVal)
        let castedEnumValPtr = irBuilder.CreateBitCast(payload, unsafe { LLVMPointerType(layoutType, 1u32) })
        idx = 0
        while (idx < chirExpr.GetNumOfOperands()) {
            let field = chirExpr.GetOperand(idx)
            let fieldType = field.GetType().getOrThrow()
            let fieldAddrType = GetRefCGType(irBuilder, fieldType)
            let fieldPtr = irBuilder.CreateStructGEP(layoutType, castedEnumValPtr, UInt32(idx))
            cgCtx.SetBasePtr(fieldPtr, enumVal)
            let cgAddr = CGValue(fieldPtr, fieldAddrType)
            irBuilder.CreateStore(cgMod.GetMappedCGValue(field), cgAddr)
            idx++
        }
    } else {
        var idx: Int64 = 0
        while (idx < chirExpr.GetNumOfOperands()) {
            let field = chirExpr.GetOperand(idx)
            let fieldType = field.GetType().getOrThrow()
            let fieldAddrType = GetRefCGType(irBuilder, fieldType)
            let offsetArgs = ArrayList<LLVMValueRef>()
            offsetArgs.add(enumCaseTi)
            offsetArgs.add(irBuilder.GetInt64(idx))
            var fieldOffset = irBuilder.CallIntrinsicGetFieldOffset(offsetArgs)
            fieldOffset = irBuilder.CreateBinary(ExprKind.ADD, fieldOffset,
                unsafe { LLVMConstInt(unsafe { LLVMTypeOf(fieldOffset) }, irBuilder.GetPayloadOffset(), 0) })
            let gepIndices = ArrayList<LLVMValueRef>()
            gepIndices.add(fieldOffset)
            var fieldAddr = irBuilder.CreateInBoundsGEP(
                unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }, enumVal, gepIndices)
            if (!fieldType.IsGeneric()) {
                let fieldCGType = CGType.GetOrCreate(cgMod, fieldType)
                let fieldAddrTypeRaw = unsafe { LLVMTypeOf(fieldAddr) }
                let fieldAddrspace = unsafe { LLVMGetPointerAddressSpace(fieldAddrTypeRaw) }
                fieldAddr = irBuilder.CreateBitCast(fieldAddr,
                    unsafe { LLVMPointerType(fieldCGType.GetLLVMType(), fieldAddrspace) })
            }
            cgCtx.SetBasePtr(fieldAddr, enumVal)
            let cgAddr = CGValue(fieldAddr, fieldAddrType)
            irBuilder.CreateStore(cgMod.GetMappedCGValue(field), cgAddr)
            idx++
        }
    }
    return enumVal
}

private func LoadRefAggregateElementIfNeeded(irBuilder: IRBuilder2, rawValue: LLVMValueRef, sourceTy: Type,
    storageTy: Type): LLVMValueRef {
    if (!sourceTy.IsRef() || !sourceTy.StripAllRefs().IsEqual(storageTy)) {
        return CastAggregateElementIfNeeded(irBuilder, rawValue, sourceTy, storageTy)
    }
    return irBuilder.CreateLoad(CGType.GetOrCreate(irBuilder.GetCGModule(), storageTy).GetLLVMType(), rawValue,
        name: "enum.field.load")
}

private func GenerateOptionLikeTEnum(irBuilder: IRBuilder2, chirExpr: Expression, resultTy: Type): LLVMValueRef {
    let enumTy = (resultTy as EnumType) ?? return LLVMNullValue()
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let i1Ty = unsafe { LLVMInt1TypeInContext(irBuilder.GetLLVMContext().raw) }
    let i8Ty = unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }
    let i8PtrTy = unsafe { LLVMPointerType(i8Ty, 1u32) }
    let enumTypeInfo = irBuilder.CreateTypeInfo(enumTy)
    let enumValue = irBuilder.CallAllocaGeneric(enumTy)
    let payload = irBuilder.GetPayloadFromObject(enumValue)
    let castedPayload = irBuilder.CreateBitCast(payload, i8PtrTy)
    let typeArgs = enumTy.GetTypeArgs()
    if (typeArgs.isEmpty()) {
        return enumValue
    }
    let associatedType = typeArgs[0]
    let hasAssociatedValue = chirExpr.GetNumOfOperands() > 1
    let isRef = irBuilder.CreateTypeInfoIsReferenceCall(associatedType)
    let blockNames = ArrayList<String>()
    blockNames.add("ref")
    blockNames.add("nonRef")
    blockNames.add("endBB")
    let blocks = irBuilder.CreateAndInsertBasicBlocks(blockNames)
    if (blocks.size < 3) {
        return enumValue
    }
    irBuilder.CreateCondBr(isRef, blocks[0], blocks[1])

    irBuilder.SetInsertPoint(blocks[0])
    if (hasAssociatedValue) {
        let associatedValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(1))
        irBuilder.CallGCWrite(associatedValue.GetRawValue(), enumValue, castedPayload)
    } else {
        irBuilder.CallGCWrite(unsafe { LLVMConstNull(i8PtrTy) }, enumValue, castedPayload)
    }
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[1])
    let selectorValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0)).GetRawValue()
    let selectorPtr = irBuilder.CreateBitCast(payload, unsafe { LLVMPointerType(i1Ty, 1u32) })
    irBuilder.CreateStore(selectorValue, selectorPtr)
    if (hasAssociatedValue) {
        let associatedOffset = irBuilder.CallGetFieldOffset(enumTypeInfo, 1u64, 0u64)
        let indices = ArrayList<LLVMValueRef>()
        indices.add(associatedOffset)
        let associatedPtr = irBuilder.CreateInBoundsGEP(i8Ty, castedPayload, indices)
        let associatedValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(1))
        let associatedCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), associatedType)
        let associatedTypeSize = irBuilder.GetLayoutSize32(associatedType, associatedCGType)
        irBuilder.CallGCWriteGeneric(enumValue, associatedPtr, associatedValue.GetRawValue(), associatedTypeSize)
    }
    irBuilder.CreateBr(blocks[2])

    irBuilder.SetInsertPoint(blocks[2])
    return enumValue
}

private func GenerateOptionLikeRefEnum(irBuilder: IRBuilder2, chirExpr: Expression, _: Type): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() <= 1) {
        return unsafe { LLVMConstNull(CGType.GetRefType(irBuilder.GetLLVMContext())) }
    }
    let associatedOperand = chirExpr.GetOperand(1)
    return irBuilder.GetCGModule().GetMappedCGValue(associatedOperand).GetRawValue()
}

private func GenerateOptionLikeNonRefEnum(irBuilder: IRBuilder2, chirExpr: Expression, resultTy: Type,
    enumCGType: CGEnumType): LLVMValueRef {
    let hasAssociatedValue = chirExpr.GetNumOfOperands() > 1
    if (enumCGType.GetSize().isSome()) {
        let enumValue = irBuilder.CreateEntryAlloca(enumCGType, name: "enum.val")
        if (chirExpr.GetNumOfOperands() > 0) {
            let selectorValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0))
            let selectorTy = chirExpr.GetOperand(0).GetType() ??
                irBuilder.GetCGContext().GetCHIRBuilder().context.GetBoolTy()
            let selectorPtr = irBuilder.CreateStructGEP(enumCGType.GetLLVMType(), enumValue, 0u32)
            let selectorAddr = CGValue(selectorPtr, GetRefCGType(irBuilder, selectorTy))
            CreateTypedStoreForAddress(irBuilder, selectorValue, selectorAddr)
        }
        let associatedValueType = enumCGType.GetAssociatedValueTypeOfOptionLike() ?? return enumValue
        let recordValue = if (hasAssociatedValue) {
            irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(1))
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
        let selectorValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(0)).GetRawValue()
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
        let associatedValue = irBuilder.GetCGModule().GetMappedCGValue(chirExpr.GetOperand(1))
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
