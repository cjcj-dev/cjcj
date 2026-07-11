package cjcj::codegen

import std.collection.*
import cjcj::chir.Box as ChirBox
import cjcj::chir.Expression
import cjcj::chir.ExprKind
import cjcj::chir.IntType
import cjcj::chir.NumericType
import cjcj::chir.Type
import cjcj::chir.TypeCast
import cjcj::chir.TypeKind
import cjcj::chir.TypeKindIndex
import cjcj::chir.TransformToConcrete
import cjcj::chir.TransformToGeneric
import cjcj::chir.UnBox
import cjcj::chir.UnBoxToRef
import cjcj::utils.{CJC_ASSERT_WITH_MSG, OverflowStrategy, StaticCast}

private let LLVM_POINTER_TYPE_KIND: Int32 = 12

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
    let sourceCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), sourceTy)
    if (let Some(targetTy) <- boxExpr.GetResultType()) {
        if (let Some(result) <- GenerateGenericTypeCast(irBuilder, sourceCGValue, sourceTy, targetTy)) {
            return result
        }
    }
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
    if (IsThisArgOfStructMethod(sourceValue)) {
        let tmp = irBuilder.CallClassIntrinsicAlloc(DeRef(sourceTy))
        let payloadPtr = irBuilder.GetPayloadFromObject(tmp)
        let size = irBuilder.GetLayoutSize_32(DeRef(sourceTy))
        if (irBuilder.IsLLVMTypeContainsRef(sourceCGType.GetLLVMType())) {
            let args = ArrayList<LLVMValueRef>()
            args.add(tmp)
            args.add(payloadPtr)
            args.add(sourceRawValue)
            args.add(size)
            irBuilder.CallGCWriteAgg(sourceCGType.GetLayoutType(), args)
        } else {
            irBuilder.CreateMemCpy(payloadPtr, 0u32, sourceRawValue, 0u32, size)
        }
        return tmp
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
    let cgMod = irBuilder.GetCGModule()
    let sourceCGValue = cgMod.GetMappedCGValue(sourceValue)
    let targetTy = transformExpr.GetTargetTy() ?? return sourceCGValue.GetRawValue()
    let sourceTy = transformExpr.GetSourceTy() ?? return sourceCGValue.GetRawValue()
    let srcCGType = CGType.GetOrCreate(cgMod, sourceTy)
    let targetCGType = CGType.GetOrCreate(cgMod, targetTy)
    if (srcCGType.IsReference() && targetTy.IsGeneric()) {
        return sourceCGValue.GetRawValue()
    }
    if (let Some(srcSize) <- srcCGType.GetSize()) {
        if (let Some(targetSize) <- targetCGType.GetSize()) {
            if (srcSize == targetSize) {
                return sourceCGValue.GetRawValue()
            }
        }
    }
    let boxedValue = irBuilder.CallClassIntrinsicAlloc(sourceTy.StripAllRefs())
    let payloadPtr = irBuilder.GetPayloadFromObject(boxedValue)
    let elemLLVMType = if (sourceTy.IsRef()) {
        (srcCGType.GetPointerElementType() ?? srcCGType).GetLLVMType()
    } else {
        srcCGType.GetLLVMType()
    }
    let addr = irBuilder.CreateBitCast(payloadPtr, unsafe { LLVMPointerType(elemLLVMType, 1u32) })
    let refChirTy: Type = if (sourceTy.IsRef()) {
        sourceTy
    } else {
        irBuilder.GetCGContext().GetCHIRBuilder().context.GetRefTy(sourceTy)
    }
    let addrCGType = CGType.GetOrCreate(cgMod, refChirTy, extraInfo: TypeExtraInfo(1u32))
    let rawSource = sourceCGValue.GetRawValue()
    let baseSourceTy = sourceTy.StripAllRefs()
    let rawSourceTy = unsafe { LLVMTypeOf(rawSource) }
    let rawSourceIsPointer = !rawSourceTy.isNull() && unsafe { LLVMGetTypeKind(rawSourceTy) } == LLVM_POINTER_TYPE_KIND
    let valueForStore = if (!sourceTy.IsRef() && rawSourceIsPointer &&
        (baseSourceTy.IsStruct() || baseSourceTy.IsTuple() || baseSourceTy.IsVArray())) {
        CGValue(rawSource, CGType.GetOrCreate(cgMod,
            irBuilder.GetCGContext().GetCHIRBuilder().context.GetRefTy(baseSourceTy)))
    } else {
        sourceCGValue
    }
    irBuilder.CreateStore(valueForStore, CGValue(addr, addrCGType))
    return boxedValue
}

private func EmitTransformToConcreteExpression(irBuilder: IRBuilder2,
    transformExpr: TransformToConcrete): LLVMValueRef {
    let cgMod = irBuilder.GetCGModule()
    let sourceValue = transformExpr.GetSourceValue()
    var cgValue = cgMod.GetMappedCGValue(sourceValue)
    let targetTy = transformExpr.GetTargetTy().getOrThrow()
    let targetCGType = CGType.GetOrCreate(cgMod, targetTy)
    CJC_ASSERT_WITH_MSG(targetCGType.GetSize().isSome(), "target type must have size")
    var sourceTy = transformExpr.GetSourceTy().getOrThrow()
    var sourceCGType = CGType.GetOrCreate(cgMod, sourceTy)

    if (IsGenericRef(sourceTy)) {
        let sourceLocal = sourceValue.AsLocalVar().getOrThrow()
        let sourceExpr = sourceLocal.GetExpr().getOrThrow()
        if (sourceExpr.GetExprKind() == ExprKind.GET_ELEMENT_REF) {
            sourceTy = sourceTy.GetTypeArgs()[0]
            let blocks = irBuilder.CreateAndInsertBasicBlocks(
                ArrayList<String>(["handle_ref", "handle_non_ref", "handle_end"]))
            let handleRefBB = blocks[0]
            let handleNonRefBB = blocks[1]
            let handleEndBB = blocks[2]
            let sourceTI = irBuilder.CreateTypeInfo(sourceTy)
            irBuilder.CreateCondBr(irBuilder.CreateTypeInfoIsReferenceCall(sourceTI), handleRefBB, handleNonRefBB)

            irBuilder.SetInsertPoint(handleRefBB)
            sourceCGType = sourceCGType.GetPointerElementType().getOrThrow()
            let refValue = irBuilder.CreateLoad(sourceCGType.GetLLVMType(), cgValue.GetRawValue())
            irBuilder.CreateBr(handleEndBB)

            irBuilder.SetInsertPoint(handleNonRefBB)
            let sizeOfSource = irBuilder.GetSizeFromTypeInfo(sourceTI)
            let boxedValue = irBuilder.CallIntrinsicAllocaGeneric(
                ArrayList<LLVMValueRef>([sourceTI, sizeOfSource]))
            let sourceRawValue = cgValue.GetRawValue()
            let basePtrOfSource = cgMod.GetCGContext().GetBasePtrOf(sourceRawValue).getOrThrow()
            irBuilder.CallGCReadGeneric(boxedValue, basePtrOfSource, sourceRawValue, sizeOfSource)
            irBuilder.CreateBr(handleEndBB)

            irBuilder.SetInsertPoint(handleEndBB)
            let phi = irBuilder.CreatePHI(targetCGType.GetLLVMType())
            irBuilder.AddIncoming(phi, ArrayList<LLVMValueRef>([refValue, boxedValue]),
                ArrayList<LLVMBasicBlockRef>([handleRefBB, handleNonRefBB]))
            cgMod.GetCGContext().SetBoxedValueMap(phi, sourceRawValue)
            cgValue = CGValue(phi, sourceCGType)
        } else {
            sourceTy = sourceTy.GetTypeArgs()[0]
            sourceCGType = sourceCGType.GetPointerElementType().getOrThrow()
            cgValue = CGValue(irBuilder.CreateLoad(sourceCGType.GetLLVMType(), cgValue.GetRawValue()), sourceCGType)
        }
    }

    if (sourceTy.IsGeneric() && targetCGType.IsReference()) {
        return cgValue.GetRawValue()
    }
    if (targetCGType.GetSize() == sourceCGType.GetSize()) {
        return cgValue.GetRawValue()
    }
    let elementType = targetCGType.GetLLVMType()
    let sourcePayload = irBuilder.CreateBitCast(irBuilder.GetPayloadFromObject(cgValue.GetRawValue()),
        unsafe { LLVMPointerType(elementType, 1u32) })
    return irBuilder.CreateLoad(elementType, sourcePayload)
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
    if (sourceTy.IsInteger() && targetTy.IsInteger()) {
        return GenerateIntegerConversionExpr(irBuilder, overflowStrategy, sourceValue,
            CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy), StaticCast<IntType>(sourceTy))
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

private func IsUInt2Int(sourceTy: IntType, targetTy: IntType): Bool {
    return !sourceTy.IsSigned() && targetTy.IsSigned()
}

private func IsInt2UInt(sourceTy: IntType, targetTy: IntType): Bool {
    return sourceTy.IsSigned() && !targetTy.IsSigned()
}

private func IsInt2Int(sourceTy: IntType, targetTy: IntType): Bool {
    return sourceTy.IsSigned() && targetTy.IsSigned()
}

private func IsUInt2UInt(sourceTy: IntType, targetTy: IntType): Bool {
    return !sourceTy.IsSigned() && !targetTy.IsSigned()
}

private func GenerateOverflowThrowingBasicBlock(irBuilder: IRBuilder2,
    checkInfOrNaN: Option<() -> LLVMValueRef>, checkLowerBound: () -> LLVMValueRef,
    checkUpperBound: () -> LLVMValueRef, typecast: (IRBuilder2) -> LLVMValueRef,
    targetTyName: String): LLVMValueRef {
    let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>([
        GenNameForBB("not.inf.nan"), GenNameForBB("lower.bound.ok"), GenNameForBB("upper.bound.ok"),
        GenNameForBB("upper.bound.overflow"), GenNameForBB("lower.bound.overflow"),
        GenNameForBB("inf.or.nan"), GenNameForBB("overflow.throwing.end")
    ]))
    let notInfOrNaN = blocks[0]
    let lowerBoundOK = blocks[1]
    let upperBoundOK = blocks[2]
    let upperBoundOverflow = blocks[3]
    let lowerBoundOverflow = blocks[4]
    let infOrNaN = blocks[5]
    let end = blocks[6]
    if (let Some(check) <- checkInfOrNaN) {
        irBuilder.CreateCondBr(check(), notInfOrNaN, infOrNaN)
        irBuilder.SetInsertPoint(infOrNaN)
        irBuilder.CreateOverflowOrArithmeticException("Casting Infinite or NaN value to integer.")
        irBuilder.CreateUnreachable()
        irBuilder.SetInsertPoint(notInfOrNaN)
    } else {
        unsafe { LLVMDeleteBasicBlock(notInfOrNaN) }
        unsafe { LLVMDeleteBasicBlock(infOrNaN) }
    }
    irBuilder.CreateCondBr(checkLowerBound(), lowerBoundOK, lowerBoundOverflow)
    irBuilder.SetInsertPoint(lowerBoundOverflow)
    irBuilder.CreateOverflowOrArithmeticException("The result would be less than " + targetTyName + ".Min.")
    irBuilder.CreateUnreachable()
    irBuilder.SetInsertPoint(lowerBoundOK)
    irBuilder.CreateCondBr(checkUpperBound(), upperBoundOK, upperBoundOverflow)
    irBuilder.SetInsertPoint(upperBoundOverflow)
    irBuilder.CreateOverflowOrArithmeticException("The result would be greater than " + targetTyName + ".Max.")
    irBuilder.CreateUnreachable()
    irBuilder.SetInsertPoint(upperBoundOK)
    let typecastValue = typecast(irBuilder)
    irBuilder.CreateBr(end)
    irBuilder.SetInsertPoint(end)
    return typecastValue
}

private func GenerateCondCheckLowerBound(irBuilder: IRBuilder2, targetType: CGType,
    sourceValue: LLVMValueRef, sourceTy: IntType): LLVMValueRef {
    let targetTy = StaticCast<IntType>(targetType.GetOriginal())
    if (IsUInt2Int(sourceTy, targetTy)) {
        return irBuilder.GetTrue()
    } else if (IsInt2UInt(sourceTy, targetTy)) {
        let minValue = unsafe { LLVMConstInt(LLVMTypeOf(sourceValue), 0u64, 0) }
        return irBuilder.CreateICmp(LLVMIntPredicate.SLE, minValue, sourceValue, name: "i2ui.lower")
    } else if (IsInt2Int(sourceTy, targetTy)) {
        if (TypeKindIndex(irBuilder.GetTypeKindFromType(targetTy)) >
            TypeKindIndex(irBuilder.GetTypeKindFromType(sourceTy))) {
            return irBuilder.GetTrue()
        }
        let minValue = SignedIntegerConst(unsafe { LLVMTypeOf(sourceValue) },
            GetIntMaxOrMin(irBuilder, targetTy, false))
        return irBuilder.CreateICmp(LLVMIntPredicate.SLE, minValue, sourceValue, name: "i2i.lower")
    }
    CJC_ASSERT_WITH_MSG(IsUInt2UInt(sourceTy, targetTy), "expected UInt-to-UInt conversion")
    return irBuilder.GetTrue()
}

private func NeedsIntToUIntConversion(irBuilder: IRBuilder2, sourceTy: IntType, targetTyKind: TypeKind): Bool {
    let sourceTyKind = irBuilder.GetTypeKindFromType(sourceTy)
    return match (sourceTyKind) {
        case TypeKind.TYPE_INT16 => TypeKindIndex(targetTyKind) >= TypeKindIndex(TypeKind.TYPE_UINT16)
        case TypeKind.TYPE_INT32 => TypeKindIndex(targetTyKind) >= TypeKindIndex(TypeKind.TYPE_UINT32)
        case TypeKind.TYPE_INT64 => TypeKindIndex(targetTyKind) >= TypeKindIndex(TypeKind.TYPE_UINT64)
        case TypeKind.TYPE_INT_NATIVE => TypeKindIndex(targetTyKind) >= TypeKindIndex(TypeKind.TYPE_UINT64)
        case _ => true
    }
}

private func NeedsUIntToIntConversion(irBuilder: IRBuilder2, sourceTy: IntType, targetTyKind: TypeKind): Bool {
    let sourceTyKind = irBuilder.GetTypeKindFromType(sourceTy)
    return match (sourceTyKind) {
        case TypeKind.TYPE_UINT8 => TypeKindIndex(targetTyKind) > TypeKindIndex(TypeKind.TYPE_INT8)
        case TypeKind.TYPE_UINT16 => TypeKindIndex(targetTyKind) > TypeKindIndex(TypeKind.TYPE_INT16)
        case TypeKind.TYPE_UINT32 => TypeKindIndex(targetTyKind) > TypeKindIndex(TypeKind.TYPE_INT32)
        case _ => false
    }
}

private func GenerateCondCheckUpperBound(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: IntType,
    targetTy: IntType): LLVMValueRef {
    let targetTyKind = irBuilder.GetTypeKindFromType(targetTy)
    let sourceTyKind = irBuilder.GetTypeKindFromType(sourceTy)
    if (!IsSignedIntegerLikeType(sourceTy) && IsSignedIntegerLikeType(targetTy)) {
        let targetLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType()
        let needsConversion = NeedsUIntToIntConversion(irBuilder, sourceTy, targetTyKind)
        let maxType = if (needsConversion) { targetLLVMType } else { unsafe { LLVMTypeOf(sourceValue) } }
        let maxVal = SignedIntegerConst(maxType, GetIntMaxOrMin(irBuilder, targetTy, true))
        let valueToCompare = if (needsConversion) {
            irBuilder.CreateZExtOrTrunc(sourceValue, targetLLVMType)
        } else {
            sourceValue
        }
        return irBuilder.CreateICmp(LLVMIntPredicate.ULE, valueToCompare, maxVal, name: "ui2i.upper")
    }
    if (IsSignedIntegerLikeType(sourceTy) && !IsSignedIntegerLikeType(targetTy)) {
        let targetLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType()
        let needsConversion = NeedsIntToUIntConversion(irBuilder, sourceTy, targetTyKind)
        let maxType = if (needsConversion) { targetLLVMType } else { unsafe { LLVMTypeOf(sourceValue) } }
        let maxVal = UnsignedIntegerConst(maxType, GetUIntMax(irBuilder, targetTy))
        let valueToCompare = if (needsConversion) {
            irBuilder.CreateZExtOrTrunc(sourceValue, targetLLVMType)
        } else {
            sourceValue
        }
        return irBuilder.CreateICmp(LLVMIntPredicate.ULE, valueToCompare, maxVal, name: "i2ui.upper")
    }
    if (IsSignedIntegerLikeType(sourceTy) && IsSignedIntegerLikeType(targetTy)) {
        if (TypeKindIndex(targetTyKind) > TypeKindIndex(sourceTyKind)) {
            return irBuilder.GetTrue()
        }
        let maxVal = SignedIntegerConst(unsafe { LLVMTypeOf(sourceValue) },
            GetIntMaxOrMin(irBuilder, targetTy, true))
        return irBuilder.CreateICmp(LLVMIntPredicate.SLE, sourceValue, maxVal, name: "i2i.upper")
    }
    if (TypeKindIndex(targetTyKind) > TypeKindIndex(sourceTyKind)) {
        return irBuilder.GetTrue()
    }
    let maxVal = UnsignedIntegerConst(unsafe { LLVMTypeOf(sourceValue) }, GetUIntMax(irBuilder, targetTy))
    return irBuilder.CreateICmp(LLVMIntPredicate.ULE, sourceValue, maxVal, name: "ui2ui.upper")
}

private func GenerateOverflowSaturatingBasicBlock(irBuilder: IRBuilder2, targetType: CGType,
    checkLowerBound: () -> LLVMValueRef, checkUpperBound: () -> LLVMValueRef,
    typecast: (IRBuilder2) -> LLVMValueRef): LLVMValueRef {
    let targetTy = StaticCast<IntType>(targetType.GetOriginal())
    let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>([
        GenNameForBB("lower.bound.ok"), GenNameForBB("upper.bound.ok"), GenNameForBB("upper.bound.overflow"),
        GenNameForBB("lower.bound.overflow"), GenNameForBB("sat.end")
    ]))
    let lowerBoundOK = blocks[0]
    let upperBoundOK = blocks[1]
    let upperBoundOverflow = blocks[2]
    let lowerBoundOverflow = blocks[3]
    let satEnd = blocks[4]
    irBuilder.CreateCondBr(checkLowerBound(), lowerBoundOK, lowerBoundOverflow)
    irBuilder.SetInsertPoint(lowerBoundOverflow)
    let retMin = if (targetTy.IsSigned()) {
        SignedIntegerConst(targetType.GetLLVMType(), GetIntMaxOrMin(irBuilder, targetTy, false))
    } else {
        unsafe { LLVMConstInt(targetType.GetLLVMType(), 0u64, 0) }
    }
    irBuilder.CreateBr(satEnd)
    irBuilder.SetInsertPoint(lowerBoundOK)
    irBuilder.CreateCondBr(checkUpperBound(), upperBoundOK, upperBoundOverflow)
    irBuilder.SetInsertPoint(upperBoundOverflow)
    let retMax = if (targetTy.IsSigned()) {
        SignedIntegerConst(targetType.GetLLVMType(), GetIntMaxOrMin(irBuilder, targetTy, true))
    } else {
        unsafe { LLVMConstInt(targetType.GetLLVMType(), GetUIntMax(irBuilder, targetTy), 0) }
    }
    irBuilder.CreateBr(satEnd)
    irBuilder.SetInsertPoint(upperBoundOK)
    let typecastValue = typecast(irBuilder)
    irBuilder.CreateBr(satEnd)
    irBuilder.SetInsertPoint(satEnd)
    let result = irBuilder.CreatePHI(targetType.GetLLVMType())
    irBuilder.AddIncoming(result, ArrayList<LLVMValueRef>([typecastValue, retMin, retMax]),
        ArrayList<LLVMBasicBlockRef>([upperBoundOK, lowerBoundOverflow, upperBoundOverflow]))
    return result
}

private func GenerateIntegerConversionExpr(irBuilder: IRBuilder2, strategy: OverflowStrategy,
    sourceValue: LLVMValueRef, targetType: CGType, sourceTy: IntType): LLVMValueRef {
    let targetTy = StaticCast<IntType>(targetType.GetOriginal())
    let typecast = { builder: IRBuilder2 =>
        if (sourceTy.IsSigned()) {
            builder.CreateSExtOrTrunc(sourceValue, targetType.GetLLVMType())
        } else {
            builder.CreateZExtOrTrunc(sourceValue, targetType.GetLLVMType())
        }
    }
    let checkLowerBound = { =>
        GenerateCondCheckLowerBound(irBuilder, targetType, sourceValue, sourceTy)
    }
    let checkUpperBound = { =>
        GenerateCondCheckUpperBound(irBuilder, sourceValue, sourceTy, targetTy)
    }
    if (strategy == OverflowStrategy.SATURATING) {
        return GenerateOverflowSaturatingBasicBlock(irBuilder, targetType, checkLowerBound, checkUpperBound, typecast)
    } else if (strategy == OverflowStrategy.THROWING) {
        return GenerateOverflowThrowingBasicBlock(irBuilder, None, checkLowerBound, checkUpperBound, typecast,
            targetType.GetOriginal().ToString())
    }
    return typecast(irBuilder)
}

private func SignedIntegerConst(llvmType: LLVMTypeRef, value: Int64): LLVMValueRef {
    return unsafe { LLVMConstInt(llvmType, SignedInt64BitsForConst(value), 1) }
}

private func UnsignedIntegerConst(llvmType: LLVMTypeRef, value: UInt64): LLVMValueRef {
    return unsafe { LLVMConstInt(llvmType, value, 0) }
}

private func SignedInt64BitsForConst(value: Int64): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return 0x8000000000000000u64 + UInt64(value - Int64.Min)
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

private func GetNumericBitWidth(ty: Type): Int64 {
    if (let Some(numTy) <- (ty as NumericType)) {
        return Int64(numTy.GetBitness())
    }
    return 0
}
