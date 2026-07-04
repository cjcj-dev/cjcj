package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Intrinsic
import cangjie_compiler::chir.IntrinsicKind
import cangjie_compiler::chir.IntrinsicKindToString
import cangjie_compiler::chir.IntrinsicWithException
import cangjie_compiler::chir.RawArrayType
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
    if (kind == IntrinsicKind.PREINITIALIZE) {
        return GeneratePreInitializeIntrinsic(irBuilder)
    }
    if (kind == IntrinsicKind.CG_UNSAFE_BEGIN || kind == IntrinsicKind.CG_UNSAFE_END) {
        return UnitOrNull(irBuilder, resultType)
    }
    if (kind == IntrinsicKind.BEGIN_CATCH) {
        let exceptionValue = irBuilder.GetCGModule().GetMappedCGValue(args[0])
        return irBuilder.CallPostThrowExceptionIntrinsic(exceptionValue.GetRawValue())
    }
    if (kind == IntrinsicKind.OBJECT_REFEQ || kind == IntrinsicKind.RAW_ARRAY_REFEQ ||
        kind == IntrinsicKind.FUNC_REFEQ) {
        if (args.size >= 2) {
            let lhs = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
            let rhs = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
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
            let rawArg = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
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
            let pointerValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
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
            let rawArg = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
            if (let Some(resultTy) <- resultType) {
                return irBuilder.CreateBitCast(rawArg, CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy).GetLLVMType())
            }
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.INOUT_PARAM) {
        if (!args.isEmpty()) {
            let rawArg = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
            return CastPointerLikeIfNeeded(irBuilder, rawArg,
                unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) })
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.IS_NULL) {
        if (!args.isEmpty()) {
            let rawArg = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
            let nullValue = unsafe { LLVMConstNull(LLVMTypeOf(rawArg)) }
            return irBuilder.CreateICmp(LLVMIntPredicate.NE, rawArg, nullValue, name: "is.null")
        }
        return LLVMNullValue()
    }
    if (IsArrayIntrinsic(kind)) {
        return GenerateArraySyscall(irBuilder, kind, args, resultType)
    }
    let _ = IntrinsicKindToString(kind)
    return UnitOrTypedNull(irBuilder, resultType)
}

private func IsArrayIntrinsic(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.ARRAY_BUILT_IN_COPY_TO ||
        kind == IntrinsicKind.ARRAY_GET ||
        kind == IntrinsicKind.ARRAY_SET ||
        kind == IntrinsicKind.ARRAY_GET_UNCHECKED ||
        kind == IntrinsicKind.ARRAY_GET_REF_UNCHECKED ||
        kind == IntrinsicKind.ARRAY_SET_UNCHECKED ||
        kind == IntrinsicKind.ARRAY_SIZE ||
        kind == IntrinsicKind.ARRAY_CLONE ||
        kind == IntrinsicKind.ARRAY_INIT
}

private func GeneratePreInitializeIntrinsic(irBuilder: IRBuilder2): LLVMValueRef {
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
    let args = ArrayList<LLVMValueRef>()
    args.add(unsafe { LLVMConstNull(i8PtrType) })
    return irBuilder.CreateIntrinsicCall("llvm.cj.pre.initialize.package", ArrayList<LLVMTypeRef>(), args)
}

private func GenerateArraySyscall(irBuilder: IRBuilder2, kind: IntrinsicKind, args: ArrayList<Value>,
    resultType: Option<Type>): LLVMValueRef {
    if (args.isEmpty()) {
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.ARRAY_GET || kind == IntrinsicKind.ARRAY_SET) {
        return GenerateArrayIndex(irBuilder, args, true)
    }
    if (kind == IntrinsicKind.ARRAY_GET_UNCHECKED || kind == IntrinsicKind.ARRAY_SET_UNCHECKED) {
        return GenerateArrayIndex(irBuilder, args, false)
    }
    if (kind == IntrinsicKind.ARRAY_GET_REF_UNCHECKED) {
        return GenerateArrayGetElemRef(irBuilder, args)
    }
    if (kind == IntrinsicKind.ARRAY_BUILT_IN_COPY_TO) {
        return GenerateArrayCopyTo(irBuilder, args, resultType)
    }
    if (kind == IntrinsicKind.ARRAY_SIZE) {
        let arrayValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
        return irBuilder.CallArrayIntrinsicGetSize(arrayValue)
    }
    if (kind == IntrinsicKind.ARRAY_CLONE) {
        if (let Some(rawArrayTy) <- GetRawArrayTypeFromArrayArg(args[0])) {
            let arrayValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
            return irBuilder.CallArrayIntrinsicCopy(rawArrayTy, arrayValue)
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.ARRAY_INIT) {
        if (args.size == 3) {
            if (let Some(rawArrayTy) <- GetRawArrayTypeFromArrayArg(args[0])) {
                let arrayValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
                let elementValue = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
                let sizeValue = irBuilder.GetCGModule().GetMappedCGValue(args[2]).GetRawValue()
                let _ = irBuilder.CallArrayInit(arrayValue, sizeValue, elementValue, rawArrayTy)
                if (let Some(resultTy) <- resultType) {
                    return irBuilder.CreateNullValue(resultTy)
                }
                return LLVMNullValue()
            }
        }
        return LLVMNullValue()
    }
    return LLVMNullValue()
}

private func GenerateArrayIndex(irBuilder: IRBuilder2, args: ArrayList<Value>, isChecked: Bool): LLVMValueRef {
    if (args.size < 2) {
        return LLVMNullValue()
    }
    if (let Some(rawArrayTy) <- GetRawArrayTypeFromArrayArg(args[0])) {
        let arrayValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
        let indexValue = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
        if (args.size >= 3) {
            let elementValue = irBuilder.GetCGModule().GetMappedCGValue(args[2])
            return irBuilder.CallArrayIntrinsicSet(rawArrayTy, arrayValue, indexValue, elementValue, isChecked)
        }
        return irBuilder.CallArrayIntrinsicGet(rawArrayTy, arrayValue, indexValue, isChecked)
    }
    return LLVMNullValue()
}

private func GenerateArrayGetElemRef(irBuilder: IRBuilder2, args: ArrayList<Value>): LLVMValueRef {
    if (args.size != 2) {
        return LLVMNullValue()
    }
    if (let Some(rawArrayTy) <- GetRawArrayTypeFromArrayArg(args[0])) {
        let arrayValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
        let indexValue = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
        return irBuilder.GetArrayElementAddr(rawArrayTy, arrayValue, indexValue, false)
    }
    return LLVMNullValue()
}

private func GenerateArrayCopyTo(irBuilder: IRBuilder2, args: ArrayList<Value>,
    resultType: Option<Type>): LLVMValueRef {
    if (args.size != 5) {
        return LLVMNullValue()
    }
    if (let Some(rawArrayTy) <- GetRawArrayTypeFromArrayArg(args[0])) {
        let srcArray = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
        let dstArray = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
        let srcStart = irBuilder.GetCGModule().GetMappedCGValue(args[2]).GetRawValue()
        let dstStart = irBuilder.GetCGModule().GetMappedCGValue(args[3]).GetRawValue()
        let copyLen = irBuilder.GetCGModule().GetMappedCGValue(args[4]).GetRawValue()
        let _ = irBuilder.CallArrayIntrinsicCopyTo(rawArrayTy, srcArray, dstArray, srcStart, dstStart, copyLen)
        if (let Some(resultTy) <- resultType) {
            return irBuilder.CreateNullValue(resultTy)
        }
        return LLVMNullValue()
    }
    return LLVMNullValue()
}

private func GetRawArrayTypeFromArrayArg(arg: Value): Option<RawArrayType> {
    if (let Some(argTy) <- arg.GetType()) {
        let typeArgs = argTy.GetTypeArgs()
        if (!typeArgs.isEmpty()) {
            if (let Some(rawArrayTy) <- (typeArgs[0] as RawArrayType)) {
                return rawArrayTy
            }
        }
        if (let Some(rawArrayTy) <- (argTy.StripAllRefs() as RawArrayType)) {
            return rawArrayTy
        }
    }
    return None
}

private func GenerateCPointerAdd(irBuilder: IRBuilder2, args: ArrayList<Value>,
    resultType: Option<Type>): LLVMValueRef {
    if (args.size < 2 || resultType.isNone()) {
        return LLVMNullValue()
    }
    let pointerValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
    let offsetValue = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
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
    let pointerValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
    let indexValue = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
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
    let pointerValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
    let indexValue = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
    let value = irBuilder.GetCGModule().GetMappedCGValue(args[2])
    if (let Some(valueTy) <- args[2].GetType()) {
        if (valueTy.IsGeneric()) {
            let valueTySize = irBuilder.GetLayoutSize_32(valueTy)
            let fixedTypeSize = irBuilder.CreateZExtOrTrunc(valueTySize,
                unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }, name: "ptr.write.size")
            let offset = irBuilder.CreateBinary(ExprKind.MUL, fixedTypeSize, indexValue, name: "ptr.write.offset")
            let i8Type = unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }
            let indices = ArrayList<LLVMValueRef>()
            indices.add(offset)
            let addr = irBuilder.CreateGEP(i8Type, pointerValue, indices, name: "ele.ptr")
            let payloadPtr = irBuilder.GetPayloadFromObject(value.GetRawValue())
            return irBuilder.CreateMemCpy(addr, 0u32, payloadPtr, 0u32, valueTySize)
        }
        let rawValue = value.GetRawValue()
        let rawValueType = unsafe { LLVMTypeOf(rawValue) }
        let pointerType = unsafe { LLVMTypeOf(pointerValue) }
        let pointerAddrSpace = if (!pointerType.isNull() &&
            unsafe { LLVMGetTypeKind(pointerType) } == 12) {
            unsafe { LLVMGetPointerAddressSpace(pointerType) }
        } else {
            0u32
        }
        let paramType = if (IsStructPtrType(rawValueType)) {
            unsafe { LLVMPointerType(GetPointerElementType(rawValueType), pointerAddrSpace) }
        } else {
            unsafe { LLVMPointerType(rawValueType, 0u32) }
        }
        let typedPtr = irBuilder.CreatePointerCast(pointerValue, paramType, name: "ptr.write.cast")
        let indices = ArrayList<LLVMValueRef>()
        indices.add(indexValue)
        let addr = irBuilder.CreateGEP(GetPointerElementType(paramType), typedPtr, indices, name: "ptr.write.addr")
        if (valueTy.IsStruct() || valueTy.IsUnit()) {
            let elementType = GetPointerElementType(rawValueType)
            let size = unsafe {
                LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw),
                    irBuilder.GetCGModule().GetTypeSize(elementType), 0)
            }
            let align = irBuilder.GetCGModule().GetABITypeAlignment(elementType)
            return irBuilder.CreateMemCpy(addr, align, rawValue, align, size)
        }
        return irBuilder.CreateStore(rawValue, addr)
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
