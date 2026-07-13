package cjcj::codegen

import std.collection.*
import cjcj::chir.Box as ChirBox
import cjcj::chir.Expression
import cjcj::chir.ExprKind
import cjcj::chir.FloatType
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
import cjcj::utils.{CJC_ASSERT, CJC_ASSERT_WITH_MSG, OverflowStrategy, StaticCast}
import cjcj::option.ArchType

private let LLVM_POINTER_TYPE_KIND: Int32 = 12

private let G_FLOAT2INT_BOUND_MAP: HashMap<String, (UInt64, UInt64)> = { =>
    let bounds = HashMap<String, (UInt64, UInt64)>()
    bounds["Float16Int8"] = (0xC060200000000000u64, 0x4060000000000000u64)
    bounds["Float16Int16"] = (0xC0E0040000000000u64, 0x40E0000000000000u64)
    bounds["Float16Int32"] = (0u64, 0u64)
    bounds["Float16Int64"] = (0u64, 0u64)
    bounds["Float16UInt8"] = (0xBFF0000000000000u64, 0x4070000000000000u64)
    bounds["Float16UInt16"] = (0xBFF0000000000000u64, 0x40F0000000000000u64)
    bounds["Float16UInt32"] = (0xBFF0000000000000u64, 0u64)
    bounds["Float16UInt64"] = (0xBFF0000000000000u64, 0u64)
    bounds["Float32Int8"] = (0xC060200000000000u64, 0x4060000000000000u64)
    bounds["Float32Int16"] = (0xC0E0002000000000u64, 0x40E0000000000000u64)
    bounds["Float32Int32"] = (0xC1E0000020000000u64, 0x41E0000000000000u64)
    bounds["Float32Int64"] = (0xC3E0000020000000u64, 0x43E0000000000000u64)
    bounds["Float32UInt8"] = (0xBFF0000000000000u64, 0x4070000000000000u64)
    bounds["Float32UInt16"] = (0xBFF0000000000000u64, 0x40F0000000000000u64)
    bounds["Float32UInt32"] = (0xBFF0000000000000u64, 0x41F0000000000000u64)
    bounds["Float32UInt64"] = (0xBFF0000000000000u64, 0x43F0000000000000u64)
    bounds["Float64Int8"] = (0xC060200000000000u64, 0x4060000000000000u64)
    bounds["Float64Int16"] = (0xC0E0002000000000u64, 0x40E0000000000000u64)
    bounds["Float64Int32"] = (0xC1E0000000200000u64, 0x41E0000000000000u64)
    bounds["Float64Int64"] = (0xC3E0000000000001u64, 0x43E0000000000000u64)
    bounds["Float64UInt8"] = (0xBFF0000000000000u64, 0x4070000000000000u64)
    bounds["Float64UInt16"] = (0xBFF0000000000000u64, 0x40F0000000000000u64)
    bounds["Float64UInt32"] = (0xBFF0000000000000u64, 0x41F0000000000000u64)
    bounds["Float64UInt64"] = (0xBFF0000000000000u64, 0x43F0000000000000u64)
    bounds
}()

private func StringIntX(archType: ArchType, intTy: IntType): String {
    if (archType == ArchType.X86_64 || archType == ArchType.AARCH64) {
        if (intTy.IsIntNative()) {
            return "Int64"
        } else if (intTy.IsUIntNative()) {
            return "UInt64"
        }
        return intTy.ToString()
    } else if (archType == ArchType.ARM32) {
        if (intTy.IsIntNative()) {
            return "Int32"
        } else if (intTy.IsUIntNative()) {
            return "UInt32"
        }
        return intTy.ToString()
    }
    CJC_ASSERT_WITH_MSG(false, "Unsupported ArchType.")
    return intTy.ToString()
}

private func GenerateIntegerToFloatConvExpr(irBuilder: IRBuilder2, sourceValue: LLVMValueRef,
    targetType: LLVMTypeRef, sourceTy: IntType): LLVMValueRef {
    if (sourceTy.IsSigned()) {
        return irBuilder.CreateSIToFP(sourceValue, targetType)
    }
    return irBuilder.CreateUIToFP(sourceValue, targetType)
}

private func GenerateFloatConvExpr(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, targetType: LLVMTypeRef,
    sourceTy: NumericType, targetTy: NumericType): LLVMValueRef {
    if (targetTy.GetBitness() > sourceTy.GetBitness()) {
        return irBuilder.CreateFPExt(sourceValue, targetType)
    }
    return irBuilder.CreateFPTrunc(sourceValue, targetType)
}

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

public func GenerateTupleTypeCast(irBuilder: IRBuilder2, sourceCGValue: CGValue,
    targetCGType: CGType): LLVMValueRef {
    let sourceLLVMType = sourceCGValue.GetLLVMType()
    let addressSpace = unsafe { LLVMGetPointerAddressSpace(sourceLLVMType) }
    let targetPointerType = unsafe { LLVMPointerType(targetCGType.GetLLVMType(), addressSpace) }
    return irBuilder.CreateBitOrPointerCast(sourceCGValue.GetRawValue(), targetPointerType)
}

public func GenerateTypeCast(irBuilder: IRBuilder2, typeCast: CHIRTypeCastWrapper): LLVMValueRef {
    let targetTyOption = typeCast.GetTargetTy()
    let sourceTyOption = typeCast.GetSourceTy()
    CJC_ASSERT(sourceTyOption.isSome() && targetTyOption.isSome())
    let targetTy = targetTyOption.getOrThrow()
    let sourceTy = sourceTyOption.getOrThrow()

    let cgMod = irBuilder.GetCGModule()
    let sourceCGValue = cgMod.GetMappedCGValue(typeCast.GetSourceValue())
    let sourceValue = sourceCGValue.GetRawValue()
    if (sourceTy == targetTy) {
        return sourceValue
    }

    if (let Some(result) <- GenerateGenericTypeCast(irBuilder, sourceCGValue, sourceTy, targetTy)) {
        return result
    }

    if (sourceTy.IsEnum() && targetTy.IsTuple()) {
        return sourceValue
    }

    let sourceType = CGType.GetOrCreate(cgMod, sourceTy)
    let targetType = CGType.GetOrCreate(cgMod, targetTy)
    if ((targetTy.IsEnum() && sourceTy.IsInteger()) || (targetTy.IsInteger() && sourceTy.IsEnum())) {
        let enumTy = if (targetTy.IsEnum()) { targetTy } else { sourceTy }
        if (StaticCast<CGEnumType>(CGType.GetOrCreate(cgMod, enumTy)).IsTrivial()) {
            return sourceValue
        }
        return irBuilder.CreateNullValue(targetTy)
    }

    if (sourceType.IsPointerType(addrSpace: 1u32) && targetType.IsPointerType(addrSpace: 1u32)) {
        return sourceValue
    }

    if (targetTy.IsFloat() && sourceTy.IsFloat()) {
        return GenerateFloatConvExpr(irBuilder, sourceValue, targetType.GetLLVMType(),
            StaticCast<NumericType>(sourceTy), StaticCast<NumericType>(targetTy))
    } else if (targetTy.IsFloat() && sourceTy.IsInteger()) {
        return GenerateIntegerToFloatConvExpr(irBuilder, sourceValue, targetType.GetLLVMType(),
            StaticCast<IntType>(sourceTy))
    } else if (targetTy.IsInteger() && sourceTy.IsFloat()) {
        return GenerateFloatToIntegerConvExpr(irBuilder, typeCast.GetOverflowStrategy(), sourceValue, targetType,
            StaticCast<FloatType>(sourceTy))
    } else if (irBuilder.GetTypeKindFromType(targetTy) == TypeKind.TYPE_UINT32 && sourceTy.IsRune()) {
        return sourceValue
    } else if (targetTy.IsRune() && sourceTy.IsInteger()) {
        return GenerateIntegerToRuneTypeCast(irBuilder, sourceValue, sourceTy)
    } else if (targetTy.IsInteger() && sourceTy.IsRune()) {
        return irBuilder.CreateZExtOrTrunc(sourceValue, targetType.GetLLVMType())
    } else if (targetTy.IsTuple() && sourceTy.IsTuple()) {
        return GenerateTupleTypeCast(irBuilder, sourceCGValue, targetType)
    } else if (targetTy.IsFunc() && sourceTy.IsFunc()) {
        CJC_ASSERT(targetTy.GetTypeArgs().size == sourceTy.GetTypeArgs().size)
        let functionType = StaticCast<CGFunctionType>(targetType).GetLLVMFunctionType()
        let addressSpace = unsafe { LLVMGetPointerAddressSpace(LLVMTypeOf(sourceValue)) }
        let castedTo = unsafe { LLVMPointerType(functionType, addressSpace) }
        return irBuilder.CreateBitOrPointerCast(sourceValue, castedTo)
    } else if (targetTy.IsInteger() && sourceTy.IsInteger()) {
        return GenerateIntegerConversionExpr(irBuilder, typeCast.GetOverflowStrategy(), sourceValue, targetType,
            StaticCast<IntType>(sourceTy))
    } else if (targetType.GetLLVMType().toUIntNative() == sourceType.GetLLVMType().toUIntNative()) {
        return sourceValue
    } else if (targetTy.IsCFunc() && sourceTy.IsCPointer()) {
        return irBuilder.CreateBitOrPointerCast(sourceValue, targetType.GetLLVMType())
    } else if (targetTy.IsInteger() && sourceTy.IsBoolean()) {
        return irBuilder.CreateZExtOrTrunc(sourceValue, targetType.GetLLVMType())
    }

    if (IsVArrayRef(targetTy) && sourceTy.IsCPointer()) {
        return irBuilder.CreateBitOrPointerCast(sourceValue, targetType.GetLLVMType())
    }

    return irBuilder.CreateNullValue(targetTy)
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
    if (sourceTy.IsFloat() && targetTy.IsInteger()) {
        return GenerateFloatToIntegerConvExpr(irBuilder, overflowStrategy, sourceValue,
            CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy), StaticCast<FloatType>(sourceTy))
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

private func GenerateCondCheckInfiniteOrNaN(irBuilder: IRBuilder2, sourceValue: LLVMValueRef,
    sourceTy: NumericType): LLVMValueRef {
    let llvmContext = irBuilder.GetLLVMContext()
    let floatInIEEE754 = HashMap<TypeKind, (UInt32, UInt64, LLVMTypeRef)>()
    floatInIEEE754[TypeKind.TYPE_FLOAT16] =
        (16u32, 0x7C00u64, unsafe { LLVMInt16TypeInContext(llvmContext.raw) })
    floatInIEEE754[TypeKind.TYPE_FLOAT32] =
        (32u32, 0x7F800000u64, unsafe { LLVMInt32TypeInContext(llvmContext.raw) })
    floatInIEEE754[TypeKind.TYPE_FLOAT64] =
        (64u32, 0x7FF0000000000000u64, unsafe { LLVMInt64TypeInContext(llvmContext.raw) })
    let (_, magicValue, integerType) = floatInIEEE754[irBuilder.GetTypeKindFromType(sourceTy)]
    let integerValue = irBuilder.CreateBitCast(sourceValue, integerType)
    let exponentValue = unsafe { LLVMConstInt(integerType, magicValue, 0) }
    let andValue = irBuilder.CreateAnd(integerValue, exponentValue)
    return irBuilder.CreateICmp(LLVMIntPredicate.NE, andValue, exponentValue, name: "notInfOrNan")
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

private func GenerateCondCheckLowerBound(irBuilder: IRBuilder2, targetType: CGType,
    sourceValue: LLVMValueRef, sourceTy: FloatType): LLVMValueRef {
    let targetTy = StaticCast<IntType>(targetType.GetOriginal())
    let archType = irBuilder.GetCGContext().GetCompileOptions().target.GetArchType()
    let lowerBound = G_FLOAT2INT_BOUND_MAP[sourceTy.ToString() + StringIntX(archType, targetTy)][0]
    if (lowerBound == 0u64) {
        return irBuilder.GetTrue()
    }
    let lowerBoundValue = unsafe { LLVMConstReal(LLVMTypeOf(sourceValue), Float64.fromBits(lowerBound)) }
    return irBuilder.CreateFCmpOLT(lowerBoundValue, sourceValue, name: "f2i.lt.min")
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

private func GenerateCondCheckUpperBound(irBuilder: IRBuilder2, targetType: CGType,
    sourceValue: LLVMValueRef, sourceTy: IntType): LLVMValueRef {
    let targetTy = StaticCast<IntType>(targetType.GetOriginal())
    let targetTyKind = irBuilder.GetTypeKindFromType(targetTy)
    let sourceTyKind = irBuilder.GetTypeKindFromType(sourceTy)
    if (IsUInt2Int(sourceTy, targetTy)) {
        let targetLLVMType = targetType.GetLLVMType()
        let needsConversion = NeedsUIntToIntConversion(irBuilder, sourceTy, targetTyKind)
        let maxType = if (needsConversion) { targetLLVMType } else { unsafe { LLVMTypeOf(sourceValue) } }
        let maxVal = SignedIntegerConst(maxType, GetIntMaxOrMin(irBuilder, targetTy, true))
        let valueToCompare = if (needsConversion) {
            irBuilder.CreateZExtOrTrunc(sourceValue, targetLLVMType)
        } else {
            sourceValue
        }
        return irBuilder.CreateICmp(LLVMIntPredicate.ULE, valueToCompare, maxVal, name: "ui2i.upper")
    } else if (IsInt2UInt(sourceTy, targetTy)) {
        let targetLLVMType = targetType.GetLLVMType()
        let needsConversion = NeedsIntToUIntConversion(irBuilder, sourceTy, targetTyKind)
        let maxType = if (needsConversion) { targetLLVMType } else { unsafe { LLVMTypeOf(sourceValue) } }
        let maxVal = UnsignedIntegerConst(maxType, GetUIntMax(irBuilder, targetTy))
        let valueToCompare = if (needsConversion) {
            irBuilder.CreateZExtOrTrunc(sourceValue, targetLLVMType)
        } else {
            sourceValue
        }
        return irBuilder.CreateICmp(LLVMIntPredicate.ULE, valueToCompare, maxVal, name: "i2ui.upper")
    } else if (IsInt2Int(sourceTy, targetTy)) {
        if (TypeKindIndex(targetTyKind) > TypeKindIndex(sourceTyKind)) {
            return irBuilder.GetTrue()
        }
        let maxVal = SignedIntegerConst(unsafe { LLVMTypeOf(sourceValue) },
            GetIntMaxOrMin(irBuilder, targetTy, true))
        return irBuilder.CreateICmp(LLVMIntPredicate.SLE, sourceValue, maxVal, name: "i2i.upper")
    }
    CJC_ASSERT_WITH_MSG(IsUInt2UInt(sourceTy, targetTy), "expected UInt-to-UInt conversion")
    if (TypeKindIndex(targetTyKind) > TypeKindIndex(sourceTyKind)) {
        return irBuilder.GetTrue()
    }
    let maxVal = UnsignedIntegerConst(unsafe { LLVMTypeOf(sourceValue) }, GetUIntMax(irBuilder, targetTy))
    return irBuilder.CreateICmp(LLVMIntPredicate.ULE, sourceValue, maxVal, name: "ui2ui.upper")
}

private func GenerateCondCheckUpperBound(irBuilder: IRBuilder2, targetType: CGType,
    sourceValue: LLVMValueRef, sourceTy: FloatType): LLVMValueRef {
    let targetTy = StaticCast<IntType>(targetType.GetOriginal())
    let archType = irBuilder.GetCGContext().GetCompileOptions().target.GetArchType()
    let upperBound = G_FLOAT2INT_BOUND_MAP[sourceTy.ToString() + StringIntX(archType, targetTy)][1]
    if (upperBound == 0u64) {
        return irBuilder.GetTrue()
    }
    let upperBoundValue = unsafe { LLVMConstReal(LLVMTypeOf(sourceValue), Float64.fromBits(upperBound)) }
    return irBuilder.CreateFCmpOLT(sourceValue, upperBoundValue, name: "f2i.gt.max")
}

private func GenerateFloatToIntegerConvExpr(irBuilder: IRBuilder2, strategy: OverflowStrategy,
    sourceValue: LLVMValueRef, targetType: CGType, sourceTy: FloatType): LLVMValueRef {
    if (strategy == OverflowStrategy.THROWING) {
        let checkInfOrNaN = { => GenerateCondCheckInfiniteOrNaN(irBuilder, sourceValue, sourceTy) }
        let checkLowerBound = { => GenerateCondCheckLowerBound(irBuilder, targetType, sourceValue, sourceTy) }
        let checkUpperBound = { => GenerateCondCheckUpperBound(irBuilder, targetType, sourceValue, sourceTy) }
        let typecast = { builder: IRBuilder2 =>
            let targetTy = StaticCast<IntType>(targetType.GetOriginal())
            if (targetTy.IsSigned()) {
                builder.CreateFPToSI(sourceValue, targetType.GetLLVMType())
            } else {
                builder.CreateFPToUI(sourceValue, targetType.GetLLVMType())
            }
        }
        return GenerateOverflowThrowingBasicBlock(irBuilder, Some(checkInfOrNaN), checkLowerBound, checkUpperBound,
            typecast, targetType.GetOriginal().ToString())
    }
    let targetTy = StaticCast<IntType>(targetType.GetOriginal())
    return irBuilder.CallIntrinsicFloatToIntegerSat(targetType.GetLLVMType(), sourceValue, targetTy.IsSigned())
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
        GenerateCondCheckUpperBound(irBuilder, targetType, sourceValue, sourceTy)
    }
    if (strategy == OverflowStrategy.SATURATING) {
        return GenerateOverflowSaturatingBasicBlock(irBuilder, targetType, checkLowerBound, checkUpperBound, typecast)
    } else if (strategy == OverflowStrategy.THROWING) {
        return GenerateOverflowThrowingBasicBlock(irBuilder, None, checkLowerBound, checkUpperBound, typecast,
            targetType.GetOriginal().ToString())
    }
    return typecast(irBuilder)
}

private func GenerateUnicodeScalarValueCheck(irBuilder: IRBuilder2, sourceValue: LLVMValueRef,
    sourceTy: Type): Unit {
    let sourceTyKind = irBuilder.GetTypeKindFromType(sourceTy)
    if (sourceTyKind == TypeKind.TYPE_UINT8) {
        return
    }
    let llvmType = CGType.GetOrCreate(irBuilder.GetCGModule(), sourceTy).GetLLVMType()
    let bound1 = unsafe { LLVMConstInt(llvmType, 0u64, 0) }
    let bound2 = unsafe { LLVMConstInt(llvmType, 0xD7FFu64, 0) }
    let bound3 = unsafe { LLVMConstInt(llvmType, 0xE000u64, 0) }
    let bound4 = unsafe { LLVMConstInt(llvmType, 0x10FFFFu64, 0) }

    var compareResult = LLVMNullValue()
    if (sourceTy.IsInteger() && StaticCast<IntType>(sourceTy).IsSigned()) {
        let cond1 = irBuilder.CreateICmp(LLVMIntPredicate.SLT, sourceValue, bound1)
        if (sourceTyKind == TypeKind.TYPE_INT8 || sourceTyKind == TypeKind.TYPE_INT16) {
            compareResult = cond1
        } else {
            let cond2 = irBuilder.CreateICmp(LLVMIntPredicate.SGT, sourceValue, bound2)
            let cond3 = irBuilder.CreateICmp(LLVMIntPredicate.SLT, sourceValue, bound3)
            let cond4 = irBuilder.CreateICmp(LLVMIntPredicate.SGT, sourceValue, bound4)
            let combo1 = irBuilder.CreateAnd(cond2, cond3)
            let combo2 = irBuilder.CreateOr(cond1, combo1)
            compareResult = irBuilder.CreateOr(combo2, cond4)
        }
    } else {
        let cond1 = irBuilder.CreateICmp(LLVMIntPredicate.UGT, sourceValue, bound2)
        let cond2 = irBuilder.CreateICmp(LLVMIntPredicate.ULT, sourceValue, bound3)
        let combo1 = irBuilder.CreateAnd(cond1, cond2)
        if (sourceTyKind == TypeKind.TYPE_UINT16) {
            compareResult = combo1
        } else {
            let cond3 = irBuilder.CreateICmp(LLVMIntPredicate.UGT, sourceValue, bound4)
            compareResult = irBuilder.CreateOr(combo1, cond3)
        }
    }

    let blocks = irBuilder.CreateAndInsertBasicBlocks(
        ArrayList<String>([GenNameForBB("if.else"), GenNameForBB("if.end")]))
    let throwBlock = blocks[0]
    let endBlock = blocks[1]
    irBuilder.CreateCondBr(compareResult, throwBlock, endBlock)
    irBuilder.SetInsertPoint(throwBlock)
    irBuilder.CreateOverflowOrArithmeticException(
        "in Rune(num), num is not a valid Unicode scalar value!", isOverflow: true)
    irBuilder.CreateUnreachable()
    irBuilder.SetInsertPoint(endBlock)
}

private func GenerateIntegerToRuneTypeCast(irBuilder: IRBuilder2, sourceValue: LLVMValueRef,
    sourceTy: Type): LLVMValueRef {
    GenerateUnicodeScalarValueCheck(irBuilder, sourceValue, sourceTy)
    let targetType = CGType.GetUInt32CGType(irBuilder.GetCGModule())
    if (irBuilder.GetTypeKindFromType(sourceTy) == TypeKind.TYPE_UINT32) {
        return sourceValue
    }
    return irBuilder.CreateZExtOrTrunc(sourceValue, targetType.GetLLVMType())
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
