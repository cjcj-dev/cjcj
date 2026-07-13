package cjcj::codegen

import std.collection.*
import cjcj::chir.ExprKind
import cjcj::chir.Expression
import cjcj::chir.Intrinsic
import cjcj::chir.IntrinsicKind
import cjcj::chir.IntrinsicKindToString
import cjcj::chir.IntrinsicWithException
import cjcj::chir.NeedCheckArrayBound
import cjcj::chir.RawArrayType
import cjcj::chir.Type
import cjcj::chir.Value
import cjcj::utils.CJC_ASSERT

private let IS_SUBTYPE_INTRINSIC_NAME: String = "llvm.cj.is.subtype"
private let LLVM_ARRAY_TYPE_KIND_FOR_INTRINSICS: Int32 = 11
private let LLVM_POINTER_TYPE_KIND_FOR_INTRINSICS: Int32 = 12

public func GenerateIntrinsic(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(intrinsicExpr) <- (chirExpr as Intrinsic)) {
        return GenerateIntrinsic(irBuilder, intrinsicExpr.GetIntrinsicKind(), intrinsicExpr.GetArgs(),
            intrinsicExpr.GetInstantiatedTypeArgs(), intrinsicExpr.GetResultType(),
            chirExpr.Get<NeedCheckArrayBound, Bool>())
    }
    if (let Some(intrinsicWithExceptionExpr) <- (chirExpr as IntrinsicWithException)) {
        return GenerateIntrinsic(irBuilder, intrinsicWithExceptionExpr.GetIntrinsicKind(),
            intrinsicWithExceptionExpr.GetArgs(), intrinsicWithExceptionExpr.GetInstantiatedTypeArgs(),
            intrinsicWithExceptionExpr.GetResultType(), chirExpr.Get<NeedCheckArrayBound, Bool>())
    }
    return LLVMNullValue()
}

private func GenerateIntrinsic(irBuilder: IRBuilder2, kind: IntrinsicKind, args: ArrayList<Value>,
    typeArgs: ArrayList<Type>, resultType: Option<Type>, needArrayBoundCheck: Bool): LLVMValueRef {
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
    if (kind == IntrinsicKind.FUNC_REFEQ) {
        return GenerateFuncRefEq(irBuilder, args)
    }
    if (kind == IntrinsicKind.OBJECT_REFEQ || kind == IntrinsicKind.RAW_ARRAY_REFEQ) {
        if (args.size >= 2) {
            let lhs = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
            let rhs = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
            return irBuilder.CreateICmp(LLVMIntPredicate.EQ, lhs, rhs, name: "refeq")
        }
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.OBJECT_ZERO_VALUE) {
        return irBuilder.CallIntrinsicForUninitialized(resultType.getOrThrow())
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
        return CPointerAdd(irBuilder, args, resultType)
    }
    if (kind == IntrinsicKind.CPOINTER_READ) {
        return CPointerRead(irBuilder, args, typeArgs, resultType)
    }
    if (kind == IntrinsicKind.CPOINTER_WRITE) {
        return CPointerWrite(irBuilder, args, typeArgs)
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
    if (IsVArrayIntrinsic(kind)) {
        return GenerateVArrayIntrinsic(irBuilder, kind, args, resultType, needArrayBoundCheck)
    }
    if (IsMathIntrinsic(kind)) {
        return irBuilder.CallMathIntrinsics(kind, args)
    }
    if (IsRuntimeIntrinsic(kind)) {
        return irBuilder.CallRuntimeIntrinsics(kind, args, resultType)
    }
    if (IsFutureIntrinsic(kind)) {
        return irBuilder.CallRuntimeIntrinsics(kind, args, resultType)
    }
    if (IsSyncIntrinsic(kind)) {
        return irBuilder.CallSyncIntrinsics(kind, args, typeArgs, resultType)
    }
    if (IsStackTraceIntrinsic(kind)) {
        return irBuilder.CallStackTraceIntrinsic(kind, args, resultType)
    }
    if (IsThreadInfoIntrinsic(kind)) {
        return irBuilder.CallThreadInfoIntrinsic(kind, args, resultType)
    }
    if (IsInteropIntrinsic(kind)) {
        return irBuilder.CallInteropIntrinsics(kind, args, resultType)
    }
    if (kind == IntrinsicKind.EXCLUSIVE_SCOPE) {
        return GenerateExclusiveScope(irBuilder, args, resultType)
    }
    throw IllegalStateException("unsupported intrinsic kind: " + IntrinsicKindToString(kind))
}

private func IsArrayIntrinsic(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.ARRAY_BUILT_IN_COPY_TO ||
        kind == IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA ||
        kind == IntrinsicKind.ARRAY_RELEASE_RAW_DATA ||
        kind == IntrinsicKind.ARRAY_GET ||
        kind == IntrinsicKind.ARRAY_SET ||
        kind == IntrinsicKind.ARRAY_GET_UNCHECKED ||
        kind == IntrinsicKind.ARRAY_GET_REF_UNCHECKED ||
        kind == IntrinsicKind.ARRAY_SET_UNCHECKED ||
        kind == IntrinsicKind.ARRAY_SIZE ||
        kind == IntrinsicKind.ARRAY_CLONE ||
        kind == IntrinsicKind.ARRAY_INIT
}

private func IsFutureIntrinsic(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.FUTURE_INIT ||
        kind == IntrinsicKind.FUTURE_IS_COMPLETE ||
        kind == IntrinsicKind.FUTURE_WAIT ||
        kind == IntrinsicKind.FUTURE_NOTIFYALL ||
        kind == IntrinsicKind.IS_THREAD_OBJECT_INITED ||
        kind == IntrinsicKind.GET_THREAD_OBJECT ||
        kind == IntrinsicKind.SET_THREAD_OBJECT
}

private func IsSyncIntrinsic(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.SLEEP ||
        kind == IntrinsicKind.ATOMIC_LOAD ||
        kind == IntrinsicKind.ATOMIC_STORE ||
        kind == IntrinsicKind.ATOMIC_SWAP ||
        kind == IntrinsicKind.ATOMIC_COMPARE_AND_SWAP ||
        kind == IntrinsicKind.ATOMIC_FETCH_ADD ||
        kind == IntrinsicKind.ATOMIC_FETCH_SUB ||
        kind == IntrinsicKind.ATOMIC_FETCH_AND ||
        kind == IntrinsicKind.ATOMIC_FETCH_OR ||
        kind == IntrinsicKind.ATOMIC_FETCH_XOR ||
        kind == IntrinsicKind.MUTEX_INIT ||
        kind == IntrinsicKind.CJ_MUTEX_LOCK ||
        kind == IntrinsicKind.MUTEX_TRY_LOCK ||
        kind == IntrinsicKind.MUTEX_CHECK_STATUS ||
        kind == IntrinsicKind.MUTEX_UNLOCK ||
        kind == IntrinsicKind.WAITQUEUE_INIT ||
        kind == IntrinsicKind.MONITOR_INIT ||
        kind == IntrinsicKind.MOITIOR_WAIT ||
        kind == IntrinsicKind.MOITIOR_NOTIFY ||
        kind == IntrinsicKind.MOITIOR_NOTIFY_ALL ||
        kind == IntrinsicKind.MULTICONDITION_WAIT ||
        kind == IntrinsicKind.MULTICONDITION_NOTIFY ||
        kind == IntrinsicKind.MULTICONDITION_NOTIFY_ALL
}

private func IsMathIntrinsic(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.ABS ||
        kind == IntrinsicKind.FABS ||
        kind == IntrinsicKind.FLOOR ||
        kind == IntrinsicKind.CEIL ||
        kind == IntrinsicKind.TRUNC ||
        kind == IntrinsicKind.SIN ||
        kind == IntrinsicKind.COS ||
        kind == IntrinsicKind.EXP ||
        kind == IntrinsicKind.EXP2 ||
        kind == IntrinsicKind.LOG ||
        kind == IntrinsicKind.LOG2 ||
        kind == IntrinsicKind.LOG10 ||
        kind == IntrinsicKind.SQRT ||
        kind == IntrinsicKind.ROUND ||
        kind == IntrinsicKind.POW ||
        kind == IntrinsicKind.POWI
}

private func IsStackTraceIntrinsic(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.FILL_IN_STACK_TRACE ||
        kind == IntrinsicKind.DECODE_STACK_TRACE
}

private func IsThreadInfoIntrinsic(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.DUMP_CURRENT_THREAD_INFO ||
        kind == IntrinsicKind.DUMP_ALL_THREADS_INFO
}

private func IsVArrayIntrinsic(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.VARRAY_SET ||
        kind == IntrinsicKind.VARRAY_GET
}

private func IsRuntimeIntrinsic(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.INVOKE_GC ||
        kind == IntrinsicKind.SET_GC_THRESHOLD ||
        kind == IntrinsicKind.DUMP_CJ_HEAP_DATA ||
        kind == IntrinsicKind.GET_GC_COUNT ||
        kind == IntrinsicKind.GET_GC_TIME_US ||
        kind == IntrinsicKind.GET_GC_FREED_SIZE ||
        kind == IntrinsicKind.START_CJ_CPU_PROFILING ||
        kind == IntrinsicKind.STOP_CJ_CPU_PROFILING ||
        kind == IntrinsicKind.BLACK_BOX ||
        kind == IntrinsicKind.GET_MAX_HEAP_SIZE ||
        kind == IntrinsicKind.GET_ALLOCATE_HEAP_SIZE ||
        kind == IntrinsicKind.GET_REAL_HEAP_SIZE ||
        kind == IntrinsicKind.GET_THREAD_NUMBER ||
        kind == IntrinsicKind.GET_BLOCKING_THREAD_NUMBER ||
        kind == IntrinsicKind.GET_NATIVE_THREAD_NUMBER
}

private func IsInteropIntrinsic(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.CROSS_ACCESS_BARRIER ||
        kind == IntrinsicKind.CREATE_EXPORT_HANDLE ||
        kind == IntrinsicKind.GET_EXPORTED_REF ||
        kind == IntrinsicKind.REMOVE_EXPORTED_REF ||
        kind == IntrinsicKind.GET_JSLAMBDA_ADDR
}

private func GeneratePreInitializeIntrinsic(irBuilder: IRBuilder2): LLVMValueRef {
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
    let args = ArrayList<LLVMValueRef>()
    args.add(unsafe { LLVMConstNull(i8PtrType) })
    return irBuilder.CreateIntrinsicCall("llvm.cj.pre.initialize.package", ArrayList<LLVMTypeRef>(), args)
}

private func GenerateFuncRefEq(irBuilder: IRBuilder2, args: ArrayList<Value>): LLVMValueRef {
    let parameters = ArrayList<CGValue>()
    for (arg in args) {
        parameters.add(irBuilder.GetCGModule().GetMappedCGValue(arg))
    }
    return irBuilder.CallIntrinsicFuncRefEq(parameters)
}

private func GenerateExclusiveScope(irBuilder: IRBuilder2, args: ArrayList<Value>,
    resultType: Option<Type>): LLVMValueRef {
    if (args.size < 2 || resultType.isNone()) {
        return LLVMNullValue()
    }
    let parameters = ArrayList<CGValue>()
    parameters.add(irBuilder.GetCGModule().GetMappedCGValue(args[0]))
    parameters.add(irBuilder.GetCGModule().GetMappedCGValue(args[1]))
    let retTy = resultType.getOrThrow()
    return irBuilder.CallIntrinsicFunction(CGType.GetOrCreate(irBuilder.GetCGModule(), retTy).GetLLVMType(),
        PREFIX_OF_BACKEND_SYMS + "ExclusiveScope", parameters, ArrayList<String>())
}

private func GenerateVArrayIntrinsic(irBuilder: IRBuilder2, kind: IntrinsicKind, args: ArrayList<Value>,
    resultType: Option<Type>, needArrayBoundCheck: Bool): LLVMValueRef {
    let parameters = ArrayList<CGValue>()
    for (arg in args) {
        parameters.add(irBuilder.GetCGModule().GetMappedCGValue(arg))
    }
    if (parameters.isEmpty()) {
        return LLVMNullValue()
    }
    let varrPtr = parameters[0]
    let varrLLVMType = varrPtr.GetCGType().getOrThrow().GetPointerElementType().getOrThrow().GetLLVMType()
    if (kind == IntrinsicKind.VARRAY_SET) {
        let indices = ArrayList<LLVMValueRef>()
        var idx: Int64 = 2
        while (idx < parameters.size) {
            indices.add(parameters[idx].GetRawValue())
            idx++
        }
        if (needArrayBoundCheck) {
            irBuilder.CallVArrayIntrinsicIndexCheck(varrPtr, indices)
        }
        let elementPtr = irBuilder.CreateVArrayGEP(varrLLVMType, varrPtr.GetRawValue(), indices,
            name: "varr.idx.set.gep")
        irBuilder.CreateVArrayStore(parameters[1], elementPtr)
        return LLVMNullValue()
    }
    if (kind == IntrinsicKind.VARRAY_GET) {
        let indices = ArrayList<LLVMValueRef>()
        var idx: Int64 = 1
        while (idx < parameters.size) {
            indices.add(parameters[idx].GetRawValue())
            idx++
        }
        irBuilder.CallVArrayIntrinsicIndexCheck(varrPtr, indices)
        let elementPtr = irBuilder.CreateVArrayGEP(varrLLVMType, varrPtr.GetRawValue(), indices,
            name: "varr.idx.get.gep")
        if (let Some(retTy) <- resultType) {
            let retCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), retTy)
            return irBuilder.CreateLoad(retCGType.GetLLVMType(), elementPtr)
        }
        return LLVMNullValue()
    }
    throw IllegalStateException("unimplemented varray intrinsic")
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
    if (kind == IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA) {
        return irBuilder.AcquireRawData(args)
    }
    if (kind == IntrinsicKind.ARRAY_RELEASE_RAW_DATA) {
        return irBuilder.ReleaseRawData(args)
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

private func CPointerAdd(irBuilder: IRBuilder2, args: ArrayList<Value>,
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

private func InstrumentPointerOps(irBuilder: IRBuilder2, instFunc: String, ptr: LLVMValueRef,
    typeSize: LLVMValueRef): Unit {
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
    let castVal = irBuilder.CreateBitCast(ptr, i8PtrType)
    let cgMod = irBuilder.GetCGModule()
    irBuilder.CallIntrinsicFunction(unsafe { LLVMVoidTypeInContext(irBuilder.GetLLVMContext().raw) }, instFunc,
        ArrayList<CGValue>([
            cgMod.CreateGhostCFuncArgValue(castVal, CGType.GetCStringCGType(cgMod)),
            cgMod.CreateGhostCFuncArgValue(typeSize, CGType.GetInt64CGType(cgMod))
        ]), ArrayList<String>([FAST_NATIVE_ATTR]))
}

private func InsertAsanInstrument(irBuilder: IRBuilder2, typeArgs: ArrayList<Type>, gep: LLVMValueRef,
    asanFunc: String): Unit {
    let compileOptions = irBuilder.GetCGModule().GetCGContext().GetCompileOptions()
    if (compileOptions.EnableAsan() || compileOptions.EnableHwAsan()) {
        CJC_ASSERT(typeArgs.size == 1)
        let typeSize = irBuilder.GetSize_64(typeArgs[0])
        InstrumentPointerOps(irBuilder, asanFunc, gep, typeSize)
    }
}

private func CPointerRead(irBuilder: IRBuilder2, args: ArrayList<Value>, typeArgs: ArrayList<Type>,
    resultType: Option<Type>): LLVMValueRef {
    CJC_ASSERT(args.size == 2)
    let resultTy = resultType.getOrThrow()
    let pointerValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
    let indexValue = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
    if (resultTy.IsGeneric()) {
        let typeInfoOfResult = irBuilder.CreateTypeInfo(resultTy)
        let resultTySize = irBuilder.GetLayoutSize_32(resultTy)
        let ret = irBuilder.CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>([typeInfoOfResult, resultTySize]))
        let destPayloadPtr = irBuilder.GetPayloadFromObject(ret)
        let fixedTypeSize = irBuilder.CreateZExtOrTrunc(resultTySize,
            unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }, name: "ptr.read.size")
        let offset = irBuilder.CreateBinary(ExprKind.MUL, fixedTypeSize, indexValue, name: "ptr.read.offset")
        let indices = ArrayList<LLVMValueRef>([offset])
        let gep = irBuilder.CreateInBoundsGEP(unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) },
            pointerValue, indices, name: "ele.ptr")
        InsertAsanInstrument(irBuilder, typeArgs, gep, "CJ_MCC_AsanRead")
        irBuilder.CreateMemCpy(destPayloadPtr, 0u32, gep, 0u32, resultTySize)
        return ret
    }
    let resultCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), resultTy)
    let typedPtr = irBuilder.CreateBitCast(pointerValue,
        unsafe { LLVMPointerType(resultCGType.GetLLVMType(), 0u32) }, name: "ptr.read.cast")
    let indices = ArrayList<LLVMValueRef>([indexValue])
    let addr = irBuilder.CreateInBoundsGEP(resultCGType.GetLLVMType(), typedPtr, indices, name: "ptr.read.addr")
    InsertAsanInstrument(irBuilder, typeArgs, addr, "CJ_MCC_AsanRead")
    return HandleValuePtr(irBuilder, addr)
}

private func HandleValuePtr(irBuilder: IRBuilder2, valPtr: LLVMValueRef): LLVMValueRef {
    let valPtrType = unsafe { LLVMTypeOf(valPtr) }
    if (IsStructPtrType(valPtrType) || IsVArrayPtrType(valPtrType)) {
        return valPtr
    }
    return irBuilder.CreateLoad(GetPointerElementType(valPtrType), valPtr, name: "ptr.read")
}

private func IsVArrayPtrType(llvmType: LLVMTypeRef): Bool {
    if (llvmType.isNull() || unsafe { LLVMGetTypeKind(llvmType) } != LLVM_POINTER_TYPE_KIND_FOR_INTRINSICS) {
        return false
    }
    let elementType = GetPointerElementType(llvmType)
    return !elementType.isNull() && unsafe { LLVMGetTypeKind(elementType) } == LLVM_ARRAY_TYPE_KIND_FOR_INTRINSICS
}

private func CPointerWrite(irBuilder: IRBuilder2, args: ArrayList<Value>,
    typeArgs: ArrayList<Type>): LLVMValueRef {
    CJC_ASSERT(args.size == 3)
    let pointerValue = irBuilder.GetCGModule().GetMappedCGValue(args[0]).GetRawValue()
    let indexValue = irBuilder.GetCGModule().GetMappedCGValue(args[1]).GetRawValue()
    let value = irBuilder.GetCGModule().GetMappedCGValue(args[2])
    let valueTy = args[2].GetType().getOrThrow()
    if (valueTy.IsGeneric()) {
        let valueTySize = irBuilder.GetLayoutSize_32(valueTy)
        let fixedTypeSize = irBuilder.CreateZExtOrTrunc(valueTySize,
            unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }, name: "ptr.write.size")
        let offset = irBuilder.CreateBinary(ExprKind.MUL, fixedTypeSize, indexValue, name: "ptr.write.offset")
        let indices = ArrayList<LLVMValueRef>([offset])
        let addr = irBuilder.CreateInBoundsGEP(unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) },
            pointerValue, indices, name: "ele.ptr")
        let payloadPtr = irBuilder.GetPayloadFromObject(value.GetRawValue())
        InsertAsanInstrument(irBuilder, typeArgs, addr, "CJ_MCC_AsanWrite")
        irBuilder.CreateMemCpy(addr, 0u32, payloadPtr, 0u32, valueTySize)
        return LLVMNullValue()
    }
    let rawValue = value.GetRawValue()
    let rawValueType = unsafe { LLVMTypeOf(rawValue) }
    let pointerType = unsafe { LLVMTypeOf(pointerValue) }
    let pointerAddrSpace = unsafe { LLVMGetPointerAddressSpace(pointerType) }
    let paramType = if (IsStructPtrType(rawValueType)) {
        unsafe { LLVMPointerType(GetPointerElementType(rawValueType), pointerAddrSpace) }
    } else {
        unsafe { LLVMPointerType(rawValueType, 0u32) }
    }
    let typedPtr = irBuilder.CreateBitCast(pointerValue, paramType, name: "ptr.write.cast")
    let indices = ArrayList<LLVMValueRef>([indexValue])
    let addr = irBuilder.CreateInBoundsGEP(GetPointerElementType(paramType), typedPtr, indices,
        name: "ptr.write.addr")
    InsertAsanInstrument(irBuilder, typeArgs, addr, "CJ_MCC_AsanWrite")
    if (valueTy.IsStruct() || valueTy.IsUnit()) {
        let elementType = GetPointerElementType(rawValueType)
        let size = unsafe {
            LLVMConstInt(LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw),
                irBuilder.GetCGModule().GetTypeSize(elementType), 0)
        }
        let align = irBuilder.GetCGModule().GetABITypeAlignment(elementType)
        irBuilder.CreateMemCpy(addr, align, rawValue, align, size)
    } else {
        irBuilder.CreateStore(rawValue, addr)
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
