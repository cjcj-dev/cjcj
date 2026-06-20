package cangjie_compiler::codegen

import cangjie_compiler::chir.Box as ChirBox
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.NumericType
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.TransformToConcrete
import cangjie_compiler::chir.TransformToGeneric
import cangjie_compiler::chir.UnBox
import cangjie_compiler::chir.UnBoxToRef

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
    let sourceCGValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, sourceOperand)
    let sourceValue = sourceCGValue.GetRawValue()
    if (let Some(targetTy) <- chirExpr.GetResultType()) {
        let targetLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType()
        if (let Some(sourceTy) <- sourceOperand.GetType()) {
            return CastValueToType(irBuilder, sourceValue, sourceTy, targetTy, targetLLVMType)
        }
        return irBuilder.CreateBitCast(sourceValue, targetLLVMType)
    }
    return sourceValue
}

private func EmitBoxExpression(irBuilder: IRBuilder2, boxExpr: ChirBox): LLVMValueRef {
    let sourceValue = boxExpr.GetSourceValue()
    let sourceCGValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, sourceValue)
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
        irBuilder.StoreValueToObjectPayload(objectValue, sourceRawValue, sourceTy)
        return objectValue
    }
    return sourceRawValue
}

private func EmitUnBoxExpression(irBuilder: IRBuilder2, unboxExpr: UnBox): LLVMValueRef {
    let sourceCGValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, unboxExpr.GetSourceValue())
    let sourceRawValue = sourceCGValue.GetRawValue()
    let targetTy = unboxExpr.GetTargetTy() ?? return sourceRawValue
    let targetCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy)
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
    let sourceCGValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, unboxExpr.GetSourceValue())
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
    let sourceCGValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, sourceValue)
    let targetTy = transformExpr.GetTargetTy() ?? return sourceCGValue.GetRawValue()
    let sourceTy = transformExpr.GetSourceTy() ?? return sourceCGValue.GetRawValue()
    return CastValueToType(irBuilder, sourceCGValue.GetRawValue(), sourceTy, targetTy,
        CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType())
}

private func EmitTransformToConcreteExpression(irBuilder: IRBuilder2,
    transformExpr: TransformToConcrete): LLVMValueRef {
    let sourceCGValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, transformExpr.GetSourceValue())
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

public func CastValueToType(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: Type, targetTy: Type,
    targetLLVMType: LLVMTypeRef): LLVMValueRef {
    if (sourceTy.IsEqual(targetTy)) {
        return sourceValue
    }
    if (sourceTy.IsEnum() && targetTy.IsTuple()) {
        return sourceValue
    }
    if (targetTy.IsGeneric()) {
        let sourceCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), sourceTy.StripAllRefs())
        if (sourceCGType.IsReference()) {
            return irBuilder.CreatePointerCast(sourceValue, targetLLVMType)
        }
        let objectValue = irBuilder.CallValueIntrinsicAlloc(sourceTy)
        irBuilder.StoreValueToObjectPayload(objectValue, sourceValue, sourceTy)
        return objectValue
    }
    if (sourceTy.IsGeneric()) {
        let targetCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy)
        if (targetCGType.IsReference()) {
            return irBuilder.CreatePointerCast(sourceValue, targetLLVMType, name: "generic.cast.ref")
        }
        if (targetCGType.GetSize().isSome()) {
            let payload = irBuilder.GetPayloadFromObject(sourceValue)
            let payloadType = unsafe { LLVMPointerType(targetLLVMType, 1u32) }
            let typedPayload = irBuilder.CreateBitCast(payload, payloadType, name: "generic.cast.payload")
            return irBuilder.CreateLoad(targetLLVMType, typedPayload, name: "generic.cast.value")
        }
    }
    if (sourceTy.StripAllRefs().IsValueType() && IsObjectReferenceType(targetTy)) {
        let objectValue = irBuilder.CallValueIntrinsicAlloc(sourceTy)
        irBuilder.StoreValueToObjectPayload(objectValue, sourceValue, sourceTy)
        return objectValue
    }
    if (IsIntegerLikeType(sourceTy) && IsIntegerLikeType(targetTy)) {
        return EmitIntegerCast(irBuilder, sourceValue, sourceTy, targetTy, targetLLVMType)
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
    return irBuilder.CreateBitCast(sourceValue, targetLLVMType)
}

private func EmitIntegerCast(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, sourceTy: Type, targetTy: Type,
    targetLLVMType: LLVMTypeRef): LLVMValueRef {
    let sourceBits = GetIntegerBitWidth(sourceTy)
    let targetBits = GetIntegerBitWidth(targetTy)
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
