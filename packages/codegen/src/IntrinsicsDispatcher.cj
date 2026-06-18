package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Intrinsic
import cangjie_compiler::chir.IntrinsicKind
import cangjie_compiler::chir.IntrinsicKindToString
import cangjie_compiler::chir.IntrinsicWithException
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value

private let IS_SUBTYPE_INTRINSIC_NAME: String = "llvm.cj.is.subtype"

public func GenerateIntrinsic(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(intrinsicExpr) <- (chirExpr as Intrinsic)) {
        return GenerateIntrinsic(irBuilder, intrinsicExpr.GetIntrinsicKind(), intrinsicExpr.GetArgs(),
            intrinsicExpr.GetInstantiatedTypeArgs(), intrinsicExpr.GetResultType())
    }
    if (let Some(intrinsicWithExceptionExpr) <- (chirExpr as IntrinsicWithException)) {
        return GenerateIntrinsic(irBuilder, intrinsicWithExceptionExpr.GetIntrinsicKind(),
            intrinsicWithExceptionExpr.GetArgs(), intrinsicWithExceptionExpr.GetInstantiatedTypeArgs(),
            intrinsicWithExceptionExpr.GetResultType())
    }
    return LLVMNullValue()
}

private func GenerateIntrinsic(irBuilder: IRBuilder2, kind: IntrinsicKind, args: ArrayList<Value>,
    typeArgs: ArrayList<Type>, resultType: Option<Type>): LLVMValueRef {
    if (IsOverflowIntrinsic(kind)) {
        return GenerateOverflowIntrinsic(irBuilder, kind, args, resultType)
    }
    if (kind == IntrinsicKind.CG_UNSAFE_BEGIN || kind == IntrinsicKind.CG_UNSAFE_END) {
        return UnitOrNull(irBuilder, resultType)
    }
    if (kind == IntrinsicKind.BEGIN_CATCH) {
        if (!args.isEmpty()) {
            let exceptionValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0])
            return irBuilder.CallPostThrowExceptionIntrinsic(exceptionValue.GetRawValue())
        }
        return irBuilder.CallExceptionIntrinsicGetExceptionValue()
    }
    if (kind == IntrinsicKind.OBJECT_REFEQ || kind == IntrinsicKind.RAW_ARRAY_REFEQ ||
        kind == IntrinsicKind.FUNC_REFEQ) {
        if (args.size >= 2) {
            let lhs = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0]).GetRawValue()
            let rhs = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[1]).GetRawValue()
            return irBuilder.CreateICmp(LLVMIntPredicate.EQ, lhs, rhs, name: "refeq")
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.SIZE_OF) {
        if (!typeArgs.isEmpty()) {
            return SizeOfType(irBuilder, typeArgs[0], resultType)
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.ALIGN_OF) {
        if (!typeArgs.isEmpty()) {
            return AlignOfType(irBuilder, typeArgs[0], resultType)
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.GET_TYPE_FOR_TYPE_PARAMETER) {
        if (!typeArgs.isEmpty()) {
            return GenerateGetTypeForTypeParameter(irBuilder, typeArgs[0])
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.IS_SUBTYPE_TYPES) {
        if (typeArgs.size >= 2) {
            return GenerateIsSubtypeTypes(irBuilder, typeArgs[0], typeArgs[1])
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.CPOINTER_INIT0) {
        if (let Some(resultTy) <- resultType) {
            return unsafe { LLVMConstNull(CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType()) }
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.CPOINTER_INIT1 || kind == IntrinsicKind.CSTRING_INIT ||
        kind == IntrinsicKind.CSTRING_CONVERT_CSTR_TO_PTR) {
        if (!args.isEmpty()) {
            let rawArg = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0]).GetRawValue()
            if (let Some(resultTy) <- resultType) {
                let resultLLVMType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType()
                return CastPointerLikeIfNeeded(irBuilder, rawArg, resultLLVMType)
            }
            return rawArg
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.CPOINTER_GET_POINTER_ADDRESS) {
        if (!args.isEmpty()) {
            let pointerValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0]).GetRawValue()
            if (let Some(resultTy) <- resultType) {
                return irBuilder.CreatePtrToInt(pointerValue,
                    CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType(), name: "ptr.addr")
            }
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.CPOINTER_ADD) {
        return GenerateCPointerAdd(irBuilder, args, resultType)
    }
    if (kind == IntrinsicKind.CPOINTER_READ) {
        return GenerateCPointerRead(irBuilder, args, resultType)
    }
    if (kind == IntrinsicKind.CPOINTER_WRITE) {
        return GenerateCPointerWrite(irBuilder, args)
    }
    if (kind == IntrinsicKind.BIT_CAST) {
        if (!args.isEmpty() && resultType.isSome()) {
            let rawArg = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0]).GetRawValue()
            if (let Some(resultTy) <- resultType) {
                return irBuilder.CreateBitCast(rawArg, CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType())
            }
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.INOUT_PARAM) {
        if (!args.isEmpty()) {
            let rawArg = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0]).GetRawValue()
            return CastPointerLikeIfNeeded(irBuilder, rawArg,
                unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) })
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.IS_NULL) {
        if (!args.isEmpty()) {
            let rawArg = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0]).GetRawValue()
            let nullValue = unsafe { LLVMConstNull(LLVMTypeOf(rawArg)) }
            return irBuilder.CreateICmp(LLVMIntPredicate.EQ, rawArg, nullValue, name: "is.null")
        }
        return LLVMNullValue()
    }
    let _ = IntrinsicKindToString(kind)
    return UnitOrTypedNull(irBuilder, resultType)
}

private func GenerateCPointerAdd(irBuilder: IRBuilder2, args: ArrayList<Value>,
    resultType: Option<Type>): LLVMValueRef {
    if (args.size < 2 || resultType.isNone()) {
        return LLVMNullValue()
    }
    let pointerValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0]).GetRawValue()
    let offsetValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[1]).GetRawValue()
    if (let Some(resultTy) <- resultType) {
        let elemSize = ElementSizeOfPointerLike(irBuilder, resultTy)
        let ptrAsInt = irBuilder.CreatePtrToInt(pointerValue, unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) },
            name: "ptr.int")
        let int64Ty = unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
        let offsetI64 = CastIntegerValueToType(irBuilder, offsetValue, int64Ty)
        let byteOffset = irBuilder.CreateBinary(ExprKind.MUL, offsetI64,
            unsafe { LLVMConstInt(int64Ty, UInt64(elemSize), 0) }, name: "ptr.byte.offset")
        let newAddress = irBuilder.CreateBinary(ExprKind.ADD, ptrAsInt, byteOffset, name: "ptr.add")
        return irBuilder.CreateIntToPtr(newAddress, CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType(),
            name: "ptr.add.cast")
    }
    return LLVMNullValue()
}

private func CastIntegerValueToType(irBuilder: IRBuilder2, value: LLVMValueRef, targetType: LLVMTypeRef): LLVMValueRef {
    let valueType = unsafe { LLVMTypeOf(value) }
    let valueBits = unsafe { LLVMGetIntTypeWidth(valueType) }
    let targetBits = unsafe { LLVMGetIntTypeWidth(targetType) }
    if (valueBits == targetBits) {
        return value
    }
    if (valueBits < targetBits) {
        return irBuilder.CreateSExt(value, targetType, name: "int.ext")
    }
    return irBuilder.CreateTrunc(value, targetType, name: "int.trunc")
}

private func GenerateCPointerRead(irBuilder: IRBuilder2, args: ArrayList<Value>,
    resultType: Option<Type>): LLVMValueRef {
    if (args.size < 2 || resultType.isNone()) {
        return LLVMNullValue()
    }
    let pointerValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0]).GetRawValue()
    let indexValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[1]).GetRawValue()
    if (let Some(resultTy) <- resultType) {
        let resultCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
        let typedPtr = irBuilder.CreatePointerCast(pointerValue,
            unsafe { LLVMPointerType(resultCGType.GetLLVMType(), 0u32) }, name: "ptr.read.cast")
        let indices = ArrayList<LLVMValueRef>()
        indices.add(indexValue)
        let addr = irBuilder.CreateGEP(resultCGType.GetLLVMType(), typedPtr, indices, name: "ptr.read.addr")
        return irBuilder.CreateLoad(resultCGType.GetLLVMType(), addr, name: "ptr.read")
    }
    return LLVMNullValue()
}

private func GenerateCPointerWrite(irBuilder: IRBuilder2, args: ArrayList<Value>): LLVMValueRef {
    if (args.size < 3) {
        return LLVMNullValue()
    }
    let pointerValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[0]).GetRawValue()
    let indexValue = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[1]).GetRawValue()
    let value = irBuilder.GetCGModule().MaterializeValue(irBuilder, args[2])
    if (let Some(valueTy) <- args[2].GetType()) {
        let valueCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), valueTy)
        let typedPtr = irBuilder.CreatePointerCast(pointerValue,
            unsafe { LLVMPointerType(valueCGType.GetLLVMType(), 0u32) }, name: "ptr.write.cast")
        let indices = ArrayList<LLVMValueRef>()
        indices.add(indexValue)
        let addr = irBuilder.CreateGEP(valueCGType.GetLLVMType(), typedPtr, indices, name: "ptr.write.addr")
        return irBuilder.CreateStore(value.GetRawValue(), addr)
    }
    return LLVMNullValue()
}

private func SizeOfType(irBuilder: IRBuilder2, ty: Type, resultType: Option<Type>): LLVMValueRef {
    let sizeValue = if (let Some(size) <- CGType.GetOrCreate(irBuilder.GetCGModule(), ty).GetSize()) { size } else { 0 }
    return IntegerConstantForResult(irBuilder, sizeValue, resultType)
}

private func AlignOfType(irBuilder: IRBuilder2, ty: Type, resultType: Option<Type>): LLVMValueRef {
    let alignValue = if (let Some(align) <- CGType.GetOrCreate(irBuilder.GetCGModule(), ty).GetAlign()) { align } else { 1 }
    return IntegerConstantForResult(irBuilder, alignValue, resultType)
}

private func GenerateGetTypeForTypeParameter(irBuilder: IRBuilder2, ty: Type): LLVMValueRef {
    let typeInfoValue = CreateStaticTypeInfo(irBuilder, ty)
    let typeInfoType = CGType.GetOrCreateTypeInfoType(irBuilder.GetLLVMContext())
    let namePtr = irBuilder.CreateStructGEP(typeInfoType, typeInfoValue, 0u32, name: "ti.name.ptr")
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
    return irBuilder.CreateLoad(i8PtrType, namePtr, name: "ti.name")
}

private func GenerateIsSubtypeTypes(irBuilder: IRBuilder2, leftTy: Type, rightTy: Type): LLVMValueRef {
    let args = ArrayList<LLVMValueRef>()
    args.add(CreateTypeInfoAsI8Ptr(irBuilder, leftTy))
    args.add(CreateTypeInfoAsI8Ptr(irBuilder, rightTy))
    return irBuilder.CreateIntrinsicCall(IS_SUBTYPE_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args, name: "is.subtype")
}

private func CreateStaticTypeInfo(irBuilder: IRBuilder2, ty: Type): LLVMValueRef {
    return CGType.GetOrCreate(irBuilder.GetCGModule(), ty.StripAllRefs()).GetOrCreateTypeInfo()
}

private func CreateTypeInfoAsI8Ptr(irBuilder: IRBuilder2, ty: Type): LLVMValueRef {
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
    return irBuilder.CreateBitCast(CreateStaticTypeInfo(irBuilder, ty), i8PtrType, name: "ti.i8")
}

private func IntegerConstantForResult(irBuilder: IRBuilder2, value: Int64, resultType: Option<Type>): LLVMValueRef {
    let llvmType = if (let Some(resultTy) <- resultType) {
        CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType()
    } else {
        unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
    }
    return unsafe { LLVMConstInt(llvmType, UInt64(value), 0) }
}

private func ElementSizeOfPointerLike(irBuilder: IRBuilder2, ty: Type): Int64 {
    let typeArgs = ty.GetTypeArgs()
    if (!typeArgs.isEmpty()) {
        if (let Some(size) <- CGType.GetOrCreate(irBuilder.GetCGModule(), typeArgs[0]).GetSize()) {
            if (size > 0) {
                return size
            }
        }
    }
    return 1
}

private func CastPointerLikeIfNeeded(irBuilder: IRBuilder2, value: LLVMValueRef, destType: LLVMTypeRef): LLVMValueRef {
    if (unsafe { LLVMGetTypeKind(LLVMTypeOf(value)) } == 8) {
        return irBuilder.CreateIntToPtr(value, destType)
    }
    return irBuilder.CreatePointerCast(value, destType)
}

private func UnitOrNull(irBuilder: IRBuilder2, resultType: Option<Type>): LLVMValueRef {
    if (let Some(resultTy) <- resultType) {
        if (resultTy.IsUnit()) {
            return irBuilder.GetCGModule().GenerateUnitTypeValue()
        }
    }
    return LLVMNullValue()
}

private func UnitOrTypedNull(irBuilder: IRBuilder2, resultType: Option<Type>): LLVMValueRef {
    if (let Some(resultTy) <- resultType) {
        if (resultTy.IsUnit()) {
            return irBuilder.GetCGModule().GenerateUnitTypeValue()
        }
        return unsafe { LLVMConstNull(CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType()) }
    }
    return LLVMNullValue()
}
