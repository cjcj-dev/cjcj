package cangjie_compiler::codegen

import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.NumericType
import cangjie_compiler::chir.Type

public func EmitTypeCastExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (chirExpr.GetNumOfOperands() == 0) {
        return LLVMNullValue()
    }
    let sourceOperand = chirExpr.GetOperand(0)
    let sourceCGValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, sourceOperand)
    let sourceValue = sourceCGValue.GetRawValue()
    if (let Some(targetTy) <- chirExpr.GetResultType()) {
        let targetLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), targetTy).GetLLVMType()
        if (let Some(sourceTy) <- sourceOperand.GetType()) {
            if (sourceTy.IsEqual(targetTy)) {
                return sourceValue
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
        }
        return irBuilder.CreateBitCast(sourceValue, targetLLVMType)
    }
    return sourceValue
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
