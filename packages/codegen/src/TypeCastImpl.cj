package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Box as ChirBox
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.NumericType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TypeCast
import cangjie_compiler::chir.TransformToConcrete
import cangjie_compiler::chir.TransformToGeneric
import cangjie_compiler::chir.UnBox
import cangjie_compiler::chir.UnBoxToRef
import cangjie_compiler::utils.{CJC_ASSERT_WITH_MSG, OverflowStrategy, StaticCast}

public func EmitTypeCastExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    if (let Some(boxExpr) <- (chirExpr as ChirBox)) {
        return EmitBoxExpression(irBuilder, boxExpr)
    }
    if (let Some(unboxExpr) <- (chirExpr as UnBox)) {
        return EmitUnBoxExpression(irBuilder, unboxExpr)
    }
    if (let Some(unboxToRefExpr) <- (chirExpr as UnBoxToRef)) {
        return EmitUnBoxToRefExpression(irBuilder, unboxToRefExpr)
    }
    if (let Some(transformExpr) <- (chirExpr as TransformToConcrete)) {
        return EmitTransformToConcreteExpression(irBuilder, transformExpr)
    }
    if (let Some(transformExpr2) <- (chirExpr as TransformToGeneric)) {
        return EmitTransformToGenericExpression(irBuilder, transformExpr2)
    }
    let sourceOperand = chirExpr.GetOperand(0)
    let sourceCGValue = irBuilder.GetCGModule().GetMappedCGValue(sourceOperand)
    let sourceValue = sourceCGValue.GetRawValue()
    if (let Some(targetTy) <- chirExpr.GetResultType()) {
        let targetLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType()
        if (let Some(sourceTy) <- sourceOperand.GetType()) {
            let overflowStrategy = if (let Some(typeCast) <- (chirExpr as TypeCast)) {
                typeCast.GetOverflowStrategy()
            } else {
                OverflowStrategy.NA
            }
            return CastValueToType(irBuilder, sourceValue, sourceTy, targetTy, targetLLVMType,
                overflowStrategy: overflowStrategy)
        }
        return irBuilder.CreateBitCast(sourceValue, targetLLVMType)
    }
    return sourceValue
}

private func EmitBoxExpression(irBuilder: IRBuilder2, boxExpr: ChirBox): LLVMValueRef {
    let sourceValue = boxExpr.GetSourceValue()
    let sourceCGValue = irBuilder.GetCGModule().GetMappedCGValue(sourceValue)
    let sourceRawValue = sourceCGValue.GetRawValue()
    let sourceTy = boxExpr.GetSourceTy() ?? return sourceRawValue
    if (sourceTy.IsUnit() || sourceTy.IsVoid() || sourceTy.IsNothing()) {
        if (let Some(targetTy) <- boxExpr.GetTargetTy()) {
            return unsafe { LLVMConstNull(CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType()) }
        }
        return unsafe { LLVMConstNull(CGType.GetRefType(irBuilder.GetLLVMContext())) }
    }
    let sourceCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), sourceTy)
    if (sourceCGType.IsReference()) {
        return sourceRawValue
    }
    if (sourceCGType.GetSize().isSome()) {
        let objectValue = irBuilder.CallValueIntrinsicAlloc(sourceTy)
        let payloadPtr = irBuilder.GetPayloadFromObject(objectValue)
        let payloadElementType = if (sourceTy.IsRef()) {
            sourceCGType.GetPointerElementType().getOrThrow().GetLLVMType()
        } else {
            sourceCGType.GetLLVMType()
        }
        let addr = irBuilder.CreateBitCast(payloadPtr, unsafe { LLVMPointerType(payloadElementType, 1u32) })
        let addrTy = if (sourceTy.IsRef()) {
            sourceTy
        } else {
            irBuilder.GetCGContext().GetCHIRBuilder().context.GetRefTy(sourceTy)
        }
        let addrCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), addrTy, extraInfo: TypeExtraInfo(1u32))
        irBuilder.CreateStore(sourceCGValue, CGValue(addr, addrCGType))
        return objectValue
    }
    return sourceRawValue
}

private func EmitUnBoxExpression(irBuilder: IRBuilder2, unboxExpr: UnBox): LLVMValueRef {
    let sourceValue = unboxExpr.GetSourceValue()
    let sourceCGValue = irBuilder.GetCGModule().GetMappedCGValue(sourceValue)
    let sourceRawValue = sourceCGValue.GetRawValue()
    let targetTy = unboxExpr.GetTargetTy() ?? return sourceRawValue
    let targetCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy)
    if (let Some(topLevelFunc) <- unboxExpr.GetTopLevelFunc()) {
        if (let Some(srcFuncType) <- topLevelFunc.GetOverrideSrcFuncType()) {
            if (sourceValue.IsParameter()) {
                if (let Some(sourceTy) <- unboxExpr.GetSourceTy()) {
                    if (DeRef(sourceTy).IsBox()) {
                        var idx: Int64 = 0
                        while (idx < topLevelFunc.GetNumOfParams()) {
                            if (sourceValue == topLevelFunc.GetParam(idx)) {
                                let cgParamType = CGType.GetOrCreate(irBuilder.GetCGModule(), srcFuncType.GetParamType(idx))
                                if (cgParamType.GetSize().isSome()) {
                                    return sourceRawValue
                                }
                                break
                            }
                            idx++
                        }
                    }
                }
            }
        }
    }
    if (targetCGType.IsReference()) {
        return sourceRawValue
    }
    if (targetTy.IsRef()) {
        return irBuilder.GetPayloadFromObject(sourceRawValue)
    }
    if (targetCGType.GetSize().isSome()) {
        let payload = irBuilder.GetPayloadFromObject(sourceRawValue)
        let payloadType = unsafe { LLVMPointerType(targetCGType.GetLLVMType(), 1u32) }
        let typedPayload = irBuilder.CreateBitCast(payload, payloadType, name: "unbox.payload")
        return irBuilder.CreateLoad(targetCGType.GetLLVMType(), typedPayload, name: "unbox.value")
    }
    return sourceRawValue
}

private func EmitUnBoxToRefExpression(irBuilder: IRBuilder2, unboxExpr: UnBoxToRef): LLVMValueRef {
    let sourceCGValue = irBuilder.GetCGModule().GetMappedCGValue(unboxExpr.GetSourceValue())
    let sourceRawValue = sourceCGValue.GetRawValue()
    let targetTy = unboxExpr.GetTargetTy() ?? return sourceRawValue
    let derefTargetTy = targetTy.StripAllRefs()
    let targetCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), derefTargetTy)
    if (targetCGType.GetSize().isSome()) {
        return irBuilder.GetPayloadFromObject(sourceRawValue)
    }
    return sourceRawValue
}

private func EmitTransformToGenericExpression(irBuilder: IRBuilder2, transformExpr: TransformToGeneric): LLVMValueRef {
    let sourceValue = transformExpr.GetSourceValue()
    let sourceCGValue = irBuilder.GetCGModule().GetMappedCGValue(sourceValue)
    let targetTy = transformExpr.GetTargetTy() ?? return sourceCGValue.GetRawValue()
    let sourceTy = transformExpr.GetSourceTy() ?? return sourceCGValue.GetRawValue()
    return CastValueToType(irBuilder, sourceCGValue.GetRawValue(), sourceTy, targetTy,
        CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType())
}

private func EmitTransformToConcreteExpression(irBuilder: IRBuilder2,
    transformExpr: TransformToConcrete): LLVMValueRef {
    let sourceCGValue = irBuilder.GetCGModule().GetMappedCGValue(transformExpr.GetSourceValue())
    let sourceRawValue = sourceCGValue.GetRawValue()
    let targetTy = transformExpr.GetTargetTy() ?? return sourceRawValue
    let targetCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy)
    if (targetCGType.IsReference()) {
        return irBuilder.CreatePointerCast(sourceRawValue, targetCGType.GetLLVMType(), name: "generic.concrete.ref")
    }
    if (targetCGType.GetSize().isSome()) {
        let payload = irBuilder.GetPayloadFromObject(sourceRawValue)
        let payloadType = unsafe { LLVMPointerType(targetCGType.GetLLVMType(), 1u32) }
        let typedPayload = irBuilder.CreateBitCast(payload, payloadType, name: "generic.concrete.payload")
        return irBuilder.CreateLoad(targetCGType.GetLLVMType(), typedPayload, name: "generic.concrete.value")
    }
    return sourceRawValue
}

private func GenerateGenericTypeCast(irBuilder: IRBuilder2, sourceCGValue: CGValue, sourceTy: Type,
    targetTy: Type): Option<LLVMValueRef> {
    let cgMod = irBuilder.GetCGModule()
    let sourceValue = sourceCGValue.GetRawValue()
    let targetCGType = CGType.GetOrCreate(cgMod, targetTy)
    let sourceCGType = CGType.GetOrCreate(cgMod, sourceTy)
    let targetIsOptionLike = if (targetTy.IsEnum()) {
        StaticCast<CGEnumType>(targetCGType).IsOptionLike()
    } else {
        false
    }
    let sourceIsOptionLike = if (sourceTy.IsEnum()) {
        StaticCast<CGEnumType>(sourceCGType).IsOptionLike()
    } else {
        false
    }
    if (sourceTy.IsGeneric() && targetTy.IsGeneric()) {
        return Some(sourceValue)
    } else if (sourceTy.IsGeneric() && IsGenericRef(targetTy)) {
        let result = irBuilder.CreateEntryAlloca(targetCGType.GetLLVMType())
        irBuilder.CreateStore(sourceValue, result)
        return Some(result)
    } else if (IsGenericRef(sourceTy) && targetTy.IsGeneric()) {
        return Some(irBuilder.CreateLoad(targetCGType.GetLLVMType(), sourceValue))
    } else if (sourceTy.IsGeneric() &&
        (targetTy.IsStruct() || targetTy.IsRawArray() || targetTy.IsTuple() || IsTrivialEnum(targetTy) ||
            targetIsOptionLike)) {
        if (targetCGType.GetSize().isSome()) {
            let elementType = targetCGType.GetLLVMType()
            let sourcePayload = irBuilder.CreateBitCast(irBuilder.GetPayloadFromObject(sourceValue),
                unsafe { LLVMPointerType(elementType, 1u32) })
            return Some(irBuilder.CreateLoad(elementType, sourcePayload))
        }
        return Some(sourceValue)
    } else if ((sourceTy.IsStruct() || sourceTy.IsRawArray() || sourceTy.IsTuple() || IsTrivialEnum(sourceTy) ||
        sourceIsOptionLike) && targetTy.IsGeneric()) {
        if (sourceCGType.GetSize().isSome()) {
            let typeInfoOfSource = irBuilder.CreateTypeInfo(sourceTy)
            let temp = irBuilder.CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>(
                [typeInfoOfSource, irBuilder.GetLayoutSize32(sourceTy, sourceCGType)]))
            let payloadPtr = irBuilder.GetPayloadFromObject(temp)
            let addr = irBuilder.CreateBitCast(payloadPtr,
                unsafe { LLVMPointerType(sourceCGType.GetLLVMType(), 1u32) })
            let addrType = CGType.GetOrCreate(cgMod,
                irBuilder.GetCGContext().GetCHIRBuilder().context.GetRefTy(sourceTy), extraInfo: TypeExtraInfo(1u32))
            irBuilder.CreateStore(sourceCGValue, CGValue(addr, addrType))
            return Some(temp)
        }
        return Some(sourceValue)
    } else if (sourceTy.IsGeneric() && IsStructRef(targetTy)) {
        CJC_ASSERT_WITH_MSG(false, "Illegal GenericTypeCast.")
        return Some(LLVMNullValue())
    } else if (IsStructRef(sourceTy) && targetTy.IsGeneric()) {
        CJC_ASSERT_WITH_MSG(false, "Illegal GenericTypeCast")
        return Some(LLVMNullValue())
    } else if (sourceTy.IsGeneric() && (IsClassRef(targetTy) || targetTy.IsEnum())) {
        return Some(sourceValue)
    } else if ((IsClassRef(sourceTy) || sourceTy.IsEnum()) && targetTy.IsGeneric()) {
        return Some(sourceValue)
    } else if (sourceTy.IsGeneric() && IsDynamicStruct(targetTy)) {
        return None
    } else if (IsDynamicStruct(sourceTy) && targetTy.IsGeneric()) {
        return None
    } else if (sourceTy.IsGeneric() && IsDynamicStructRef(targetTy)) {
        return None
    } else if (IsDynamicStructRef(sourceTy) && targetTy.IsGeneric()) {
        return None
    } else if (sourceTy.IsGeneric() && IsDynamicClassRef(targetTy)) {
        return Some(sourceValue)
    } else if (IsDynamicClassRef(sourceTy) && targetTy.IsGeneric()) {
        return Some(sourceValue)
    } else if (IsStructRef(sourceTy) && IsDynamicClassRef(targetTy)) {
        let typeInfo = irBuilder.CreateTypeInfo(sourceTy)
        let size = irBuilder.GetLayoutSize_32(sourceTy)
        let temp = irBuilder.CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>([typeInfo, size]))
        irBuilder.CallGCWriteGenericPayload(temp, sourceValue, size)
        return Some(temp)
    } else if (IsDynamicClassRef(sourceTy) && IsStructRef(targetTy)) {
        return None
    } else if (sourceTy.IsStructArray() && targetTy.IsStructArray()) {
        let tmp = irBuilder.CreateEntryAlloca(targetCGType)
        irBuilder.CreateMemCpy(tmp, 0u32, sourceValue, 0u32, irBuilder.GetLayoutSize_32(targetTy))
        return Some(tmp)
    } else if (IsStaticStruct(sourceTy) && IsDynamicStruct(targetTy)) {
        let typeInfo = irBuilder.CreateTypeInfo(sourceTy)
        let size = irBuilder.GetLayoutSize_32(sourceTy)
        let temp = irBuilder.CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>([typeInfo, size]))
        irBuilder.CallGCWriteGenericPayload(temp, sourceValue, size)
        return Some(temp)
    } else if (IsDynamicStruct(sourceTy) && IsStaticStruct(targetTy)) {
        let tmp = irBuilder.CreateEntryAlloca(targetCGType)
        let dataPtr = irBuilder.GetPayloadFromObject(sourceValue)
        if (irBuilder.IsLLVMTypeContainsRef(targetCGType.GetLLVMType())) {
            let args = ArrayList<LLVMValueRef>([
                tmp, sourceValue, dataPtr, irBuilder.GetLayoutSize_64(targetTy)
            ])
            irBuilder.CallGCReadAgg(targetCGType.GetLayoutType(), args)
        } else {
            irBuilder.CreateMemCpy(tmp, 0u32, dataPtr, 0u32, irBuilder.GetLayoutSize_32(targetTy))
        }
        return Some(tmp)
    } else if (IsStaticStruct(sourceTy) && IsDynamicStruct(targetTy)) {
        let typeInfo = irBuilder.CreateTypeInfo(sourceTy)
        let size = irBuilder.GetLayoutSize_32(sourceTy)
        let temp = irBuilder.CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>([typeInfo, size]))
        irBuilder.CallGCWriteGenericPayload(temp, sourceValue, size)
        return Some(temp)
    } else if (IsDynamicClass(sourceTy) && IsStaticClass(targetTy)) {
        return Some(sourceValue)
    } else if (IsStaticClass(sourceTy) && IsDynamicClass(targetTy)) {
        return Some(sourceValue)
    } else if ((sourceTy.IsTuple() && targetTy.IsTuple()) &&
        (sourceCGType.GetSize().isNone() && targetCGType.GetSize().isSome())) {
        let elementType = targetCGType.GetLLVMType()
        let sourcePayload = irBuilder.CreateBitCast(irBuilder.GetPayloadFromObject(sourceValue),
            unsafe { LLVMPointerType(elementType, 1u32) })
        return Some(irBuilder.CreateLoad(elementType, sourcePayload))
    }
    return None
}

public func CastValueToType(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: Type, targetTy: Type,
    targetLLVMType: LLVMTypeRef, overflowStrategy!: OverflowStrategy = OverflowStrategy.NA): LLVMValueRef {
    if (sourceTy.IsEqual(targetTy)) {
        return sourceValue
    }
    let sourceCGValue = CGValue(sourceValue, CGType.GetOrCreate(irBuilder.GetCGModule(), sourceTy))
    if (let Some(genericCast) <- GenerateGenericTypeCast(irBuilder, sourceCGValue, sourceTy, targetTy)) {
        return genericCast
    }
    if (sourceTy.IsEnum() && targetTy.IsTuple()) {
        return sourceValue
    }
    if ((targetTy.IsEnum() && sourceTy.IsInteger()) || (targetTy.IsInteger() && sourceTy.IsEnum())) {
        let enumTy = if (targetTy.IsEnum()) { targetTy } else { sourceTy }
        if (StaticCast<CGEnumType>(CGType.GetOrCreate(irBuilder.GetCGModule(), enumTy)).IsTrivial()) {
            return sourceValue
        }
        return irBuilder.CreateNullValue(targetTy)
    }
    if (sourceTy.StripAllRefs().IsValueType() && IsObjectReferenceType(targetTy)) {
        let objectValue = irBuilder.CallValueIntrinsicAlloc(sourceTy)
        irBuilder.StoreValueToObjectPayload(objectValue, sourceValue, sourceTy)
        return objectValue
    }
    if (IsIntegerLikeType(sourceTy) && IsIntegerLikeType(targetTy)) {
        return EmitIntegerCast(irBuilder, sourceValue, sourceTy, targetTy, targetLLVMType, overflowStrategy)
    }
    if (sourceTy.IsFloat() && targetTy.IsFloat()) {
        return EmitFloatCast(irBuilder, sourceValue, sourceTy, targetTy, targetLLVMType)
    }
    if (IsIntegerLikeType(sourceTy) && targetTy.IsFloat()) {
        return if (IsSignedIntegerLikeType(sourceTy)) {
            irBuilder.CreateSIToFP(sourceValue, targetLLVMType)
        } else {
            irBuilder.CreateUIToFP(sourceValue, targetLLVMType)
        }
    }
    if (sourceTy.IsFloat() && IsIntegerLikeType(targetTy)) {
        return if (IsSignedIntegerLikeType(targetTy)) {
            irBuilder.CreateFPToSI(sourceValue, targetLLVMType)
        } else {
            irBuilder.CreateFPToUI(sourceValue, targetLLVMType)
        }
    }
    if (IsPointerLikeType(sourceTy) && IsIntegerLikeType(targetTy)) {
        return irBuilder.CreatePtrToInt(sourceValue, targetLLVMType)
    }
    if (IsIntegerLikeType(sourceTy) && IsPointerLikeType(targetTy)) {
        return irBuilder.CreateIntToPtr(sourceValue, targetLLVMType)
    }
    if (IsPointerLikeType(sourceTy) && IsPointerLikeType(targetTy)) {
        return irBuilder.CreatePointerCast(sourceValue, targetLLVMType)
    }
    return irBuilder.CreateNullValue(targetTy)
}

private func EmitIntegerCast(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: Type, targetTy: Type,
    targetLLVMType: LLVMTypeRef, overflowStrategy: OverflowStrategy): LLVMValueRef {
    let sourceBits = GetIntegerBitWidth(sourceTy)
    let targetBits = GetIntegerBitWidth(targetTy)
    if (sourceBits == targetBits && IsSignedIntegerLikeType(sourceTy) == IsSignedIntegerLikeType(targetTy)) {
        return sourceValue
    }
    if (overflowStrategy == OverflowStrategy.SATURATING) {
        return EmitSaturatingIntegerCast(irBuilder, sourceValue, sourceTy, targetTy, targetLLVMType)
    }
    if (overflowStrategy == OverflowStrategy.THROWING || overflowStrategy == OverflowStrategy.CHECKED) {
        return EmitThrowingIntegerCast(irBuilder, sourceValue, sourceTy, targetTy, targetLLVMType)
    }
    return EmitWrappingIntegerCast(irBuilder, sourceValue, sourceTy, targetLLVMType)
}

private func EmitWrappingIntegerCast(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: Type,
    targetLLVMType: LLVMTypeRef): LLVMValueRef {
    let sourceBits = GetIntegerBitWidth(sourceTy)
    let targetBits = Int64(unsafe { LLVMGetIntTypeWidth(targetLLVMType) })
    if (sourceBits == targetBits) {
        return sourceValue
    }
    if (sourceBits > targetBits) {
        return irBuilder.CreateTrunc(sourceValue, targetLLVMType)
    }
    if (IsSignedIntegerLikeType(sourceTy)) {
        return irBuilder.CreateSExt(sourceValue, targetLLVMType)
    }
    return irBuilder.CreateZExt(sourceValue, targetLLVMType)
}

private func EmitThrowingIntegerCast(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: Type, targetTy: Type,
    targetLLVMType: LLVMTypeRef): LLVMValueRef {
    let currentBlock = irBuilder.GetInsertBlock()
    if (currentBlock.isNull()) {
        return EmitWrappingIntegerCast(irBuilder, sourceValue, sourceTy, targetLLVMType)
    }
    let blocks = MakeBlockNames(ArrayList<String>([
        "lower.bound.ok", "upper.bound.ok", "lower.bound.overflow", "upper.bound.overflow"
    ]))
    let created = irBuilder.CreateAndInsertBasicBlocks(blocks)
    if (created.size < 4) {
        return EmitWrappingIntegerCast(irBuilder, sourceValue, sourceTy, targetLLVMType)
    }
    let lowerOK = created[0]
    let upperOK = created[1]
    let lowerOverflow = created[2]
    let upperOverflow = created[3]
    irBuilder.CreateCondBr(CheckIntegerCastLowerBound(irBuilder, sourceValue, sourceTy, targetTy),
        lowerOK, lowerOverflow)
    irBuilder.SetInsertPoint(lowerOverflow)
    irBuilder.CreateOverflowOrArithmeticException("The result would be less than " + targetTy.ToString() + ".Min.")
    irBuilder.SetInsertPoint(lowerOK)
    irBuilder.CreateCondBr(CheckIntegerCastUpperBound(irBuilder, sourceValue, sourceTy, targetTy),
        upperOK, upperOverflow)
    irBuilder.SetInsertPoint(upperOverflow)
    irBuilder.CreateOverflowOrArithmeticException("The result would be greater than " + targetTy.ToString() + ".Max.")
    irBuilder.SetInsertPoint(upperOK)
    return EmitWrappingIntegerCast(irBuilder, sourceValue, sourceTy, targetLLVMType)
}

private func EmitSaturatingIntegerCast(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: Type, targetTy: Type,
    targetLLVMType: LLVMTypeRef): LLVMValueRef {
    let currentBlock = irBuilder.GetInsertBlock()
    if (currentBlock.isNull()) {
        return EmitWrappingIntegerCast(irBuilder, sourceValue, sourceTy, targetLLVMType)
    }
    let blocks = MakeBlockNames(ArrayList<String>([
        "lower.bound.ok", "upper.bound.ok", "lower.bound.overflow", "upper.bound.overflow", "sat.end"
    ]))
    let created = irBuilder.CreateAndInsertBasicBlocks(blocks)
    if (created.size < 5) {
        return EmitWrappingIntegerCast(irBuilder, sourceValue, sourceTy, targetLLVMType)
    }
    let lowerOK = created[0]
    let upperOK = created[1]
    let lowerOverflow = created[2]
    let upperOverflow = created[3]
    let satEnd = created[4]
    irBuilder.CreateCondBr(CheckIntegerCastLowerBound(irBuilder, sourceValue, sourceTy, targetTy),
        lowerOK, lowerOverflow)

    irBuilder.SetInsertPoint(lowerOverflow)
    let retMin = TargetIntegerMinValue(targetLLVMType, targetTy)
    irBuilder.CreateBr(satEnd)

    irBuilder.SetInsertPoint(lowerOK)
    irBuilder.CreateCondBr(CheckIntegerCastUpperBound(irBuilder, sourceValue, sourceTy, targetTy),
        upperOK, upperOverflow)

    irBuilder.SetInsertPoint(upperOverflow)
    let retMax = TargetIntegerMaxValue(targetLLVMType, targetTy)
    irBuilder.CreateBr(satEnd)

    irBuilder.SetInsertPoint(upperOK)
    let castValue = EmitWrappingIntegerCast(irBuilder, sourceValue, sourceTy, targetLLVMType)
    irBuilder.CreateBr(satEnd)

    irBuilder.SetInsertPoint(satEnd)
    let result = irBuilder.CreatePHI(targetLLVMType, name: "sat.cast")
    let values = ArrayList<LLVMValueRef>()
    values.add(castValue)
    values.add(retMin)
    values.add(retMax)
    let incomingBlocks = ArrayList<LLVMBasicBlockRef>()
    incomingBlocks.add(upperOK)
    incomingBlocks.add(lowerOverflow)
    incomingBlocks.add(upperOverflow)
    irBuilder.AddIncoming(result, values, incomingBlocks)
    return result
}

private func CheckIntegerCastLowerBound(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: Type,
    targetTy: Type): LLVMValueRef {
    if (!IsSignedIntegerLikeType(sourceTy) || IsSignedIntegerLikeType(targetTy)) {
        if (!IsSignedIntegerLikeType(sourceTy) || !IsSignedIntegerLikeType(targetTy) ||
            GetIntegerBitWidth(targetTy) >= GetIntegerBitWidth(sourceTy)) {
            return irBuilder.GetTrue()
        }
        let minVal = SignedIntegerConst(unsafe { LLVMTypeOf(sourceValue) }, SignedMinValue(GetIntegerBitWidth(targetTy)))
        return irBuilder.CreateICmp(LLVMIntPredicate.SLE, minVal, sourceValue, name: "i2i.lower")
    }
    let minVal = unsafe { LLVMConstInt(LLVMTypeOf(sourceValue), 0u64, 0) }
    return irBuilder.CreateICmp(LLVMIntPredicate.SLE, minVal, sourceValue, name: "i2ui.lower")
}

private func CheckIntegerCastUpperBound(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: Type,
    targetTy: Type): LLVMValueRef {
    let sourceBits = GetIntegerBitWidth(sourceTy)
    let targetBits = GetIntegerBitWidth(targetTy)
    if (!IsSignedIntegerLikeType(sourceTy) && IsSignedIntegerLikeType(targetTy)) {
        if (targetBits > sourceBits) {
            return irBuilder.GetTrue()
        }
        let maxVal = UnsignedIntegerConst(unsafe { LLVMTypeOf(sourceValue) }, SignedMaxBits(targetBits))
        return irBuilder.CreateICmp(LLVMIntPredicate.ULE, sourceValue, maxVal, name: "ui2i.upper")
    }
    if (IsSignedIntegerLikeType(sourceTy) && !IsSignedIntegerLikeType(targetTy)) {
        if (targetBits >= sourceBits) {
            return irBuilder.GetTrue()
        }
        let maxVal = UnsignedIntegerConst(unsafe { LLVMTypeOf(sourceValue) }, UnsignedMaxBits(targetBits))
        return irBuilder.CreateICmp(LLVMIntPredicate.SLE, sourceValue, maxVal, name: "i2ui.upper")
    }
    if (IsSignedIntegerLikeType(sourceTy) && IsSignedIntegerLikeType(targetTy)) {
        if (targetBits >= sourceBits) {
            return irBuilder.GetTrue()
        }
        let maxVal = SignedIntegerConst(unsafe { LLVMTypeOf(sourceValue) }, SignedMaxValue(targetBits))
        return irBuilder.CreateICmp(LLVMIntPredicate.SLE, sourceValue, maxVal, name: "i2i.upper")
    }
    if (targetBits >= sourceBits) {
        return irBuilder.GetTrue()
    }
    let maxVal = UnsignedIntegerConst(unsafe { LLVMTypeOf(sourceValue) }, UnsignedMaxBits(targetBits))
    return irBuilder.CreateICmp(LLVMIntPredicate.ULE, sourceValue, maxVal, name: "ui2ui.upper")
}

private func TargetIntegerMinValue(targetLLVMType: LLVMTypeRef, targetTy: Type): LLVMValueRef {
    if (IsSignedIntegerLikeType(targetTy)) {
        return SignedIntegerConst(targetLLVMType, SignedMinValue(GetIntegerBitWidth(targetTy)))
    }
    return unsafe { LLVMConstInt(targetLLVMType, 0u64, 0) }
}

private func TargetIntegerMaxValue(targetLLVMType: LLVMTypeRef, targetTy: Type): LLVMValueRef {
    if (IsSignedIntegerLikeType(targetTy)) {
        return SignedIntegerConst(targetLLVMType, SignedMaxValue(GetIntegerBitWidth(targetTy)))
    }
    return UnsignedIntegerConst(targetLLVMType, UnsignedMaxBits(GetIntegerBitWidth(targetTy)))
}

private func SignedIntegerConst(llvmType: LLVMTypeRef, value: Int64): LLVMValueRef {
    return unsafe { LLVMConstInt(llvmType, SignedInt64BitsForConst(value), 1) }
}

private func UnsignedIntegerConst(llvmType: LLVMTypeRef, value: UInt64): LLVMValueRef {
    return unsafe { LLVMConstInt(llvmType, value, 0) }
}

private func SignedMinValue(bits: Int64): Int64 {
    if (bits >= 64) {
        return Int64.Min
    }
    return -Int64(1u64 << UInt64(bits - 1))
}

private func SignedMaxValue(bits: Int64): Int64 {
    if (bits >= 64) {
        return Int64.Max
    }
    return Int64((1u64 << UInt64(bits - 1)) - 1u64)
}

private func SignedMaxBits(bits: Int64): UInt64 {
    if (bits >= 64) {
        return 0x7fffffffffffffffu64
    }
    return (1u64 << UInt64(bits - 1)) - 1u64
}

private func UnsignedMaxBits(bits: Int64): UInt64 {
    if (bits >= 64) {
        return UInt64.Max
    }
    return (1u64 << UInt64(bits)) - 1u64
}

private func SignedInt64BitsForConst(value: Int64): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return 0x8000000000000000u64 + UInt64(value - Int64.Min)
}

private func MakeBlockNames(names: ArrayList<String>): ArrayList<String> {
    let out = ArrayList<String>()
    for (name in names) {
        out.add(GenNameForBB(name))
    }
    return out
}

private func EmitFloatCast(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: Type, targetTy: Type,
    targetLLVMType: LLVMTypeRef): LLVMValueRef {
    let sourceBits = GetNumericBitWidth(sourceTy)
    let targetBits = GetNumericBitWidth(targetTy)
    if (sourceBits == targetBits) {
        return sourceValue
    }
    if (sourceBits > targetBits) {
        return irBuilder.CreateFPTrunc(sourceValue, targetLLVMType)
    }
    return irBuilder.CreateFPExt(sourceValue, targetLLVMType)
}

private func IsIntegerLikeType(ty: Type): Bool {
    return ty.IsInteger() || ty.IsBoolean() || ty.IsRune()
}

private func IsSignedIntegerLikeType(ty: Type): Bool {
    return ty.IsSignedInteger()
}

private func IsPointerLikeType(ty: Type): Bool {
    return ty.IsRef() || ty.IsReferenceType() || ty.IsCPointer() || ty.IsCString() || ty.IsFunc()
}

private func IsObjectReferenceType(ty: Type): Bool {
    let strippedTy = ty.StripAllRefs()
    return strippedTy.IsClassOrArray() || strippedTy.IsBox() || strippedTy.IsThis()
}

private func GetIntegerBitWidth(ty: Type): Int64 {
    if (ty.IsBoolean()) {
        return 1
    }
    if (ty.IsRune()) {
        return 32
    }
    return GetNumericBitWidth(ty)
}

private func GetNumericBitWidth(ty: Type): Int64 {
    if (let Some(numTy) <- (ty as NumericType)) {
        return Int64(numTy.GetBitness())
    }
    return 0
}
