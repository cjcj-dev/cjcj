package cjcj::chir

import std.collection.*
import cjcj::utils.OverflowStrategy

public func IndentToString(indent: Int64): String {
    let unit: Int64 = 2
    var out = ""
    var idx: Int64 = 0
    while (idx < unit * indent) {
        out += " "
        idx++
    }
    return out
}

public func GetGenericTypeConstaintsStr(genericTypeParams: ArrayList<GenericType>): String {
    if (genericTypeParams.isEmpty()) {
        return ""
    }
    let genericTypeStr = ArrayList<String>()
    for (genericTypeParam in genericTypeParams) {
        let upperBounds = genericTypeParam.GetUpperBounds()
        if (upperBounds.isEmpty()) {
            continue
        }
        let constaintStr = TypeVecToString("", upperBounds, "", delimiter: " & ")
        genericTypeStr.add(genericTypeParam.ToString() + " <: " + constaintStr)
    }
    if (genericTypeStr.isEmpty()) {
        return ""
    }
    return "genericConstraints: [" + StringJoin(genericTypeStr, ", ") + "]"
}

public func PackageAccessLevelToString(level: AccessLevel): String {
    return match (level) {
        case AccessLevel.INTERNAL => "internal"
        case AccessLevel.PROTECTED => "protected"
        case AccessLevel.PUBLIC => "public"
        case AccessLevel.INVALID => throw IllegalArgumentException("invalid package access level")
    }
}

public func OverflowToString(ofStrategy: OverflowStrategy): String {
    let overflowStr = match (ofStrategy) {
        case OverflowStrategy.NA => "NA"
        case OverflowStrategy.CHECKED => "CHECKED"
        case OverflowStrategy.WRAPPING => "WRAPPING"
        case OverflowStrategy.THROWING => "THROWING"
        case OverflowStrategy.SATURATING => "SATURATING"
        case OverflowStrategy.OVERFLOW_STRATEGY_END => throw IllegalArgumentException("invalid overflow strategy")
    }
    return "Overflow: " + overflowStr
}

public func StringJoin(candidates: ArrayList<String>, delimiter: String): String {
    var result = ""
    for (candidate in candidates) {
        if (candidate.isEmpty()) {
            continue
        }
        if (!result.isEmpty()) {
            result += delimiter
        }
        result += candidate
    }
    return result
}

public func ValueIdVecToString(prefix: String, values: ArrayList<Value>, suffix: String,
    hasExceptionBranch!: Bool = false): String {
    if (values.isEmpty()) {
        return ""
    }
    let ids = ArrayList<String>()
    for (value in values) {
        if (value.IsLiteral()) {
            ids.add(value.ToString(0))
        } else {
            ids.add(value.GetIdentifier())
        }
    }
    if (hasExceptionBranch) {
        if (ids.size < 2) {
            throw IllegalArgumentException("exception branch value list must contain normal and exception successors")
        }
        ids[ids.size - 2] = "normal: " + ids[ids.size - 2]
        ids[ids.size - 1] = "exception: " + ids[ids.size - 1]
    }
    return prefix + StringJoin(ids, ", ") + suffix
}

public func TypeVecToString<T>(prefix: String, types: ArrayList<T>, suffix: String,
    delimiter!: String = ", "): String where T <: Type {
    if (types.isEmpty()) {
        return ""
    }
    let ids = ArrayList<String>()
    for (ty in types) {
        ids.add(ty.ToString())
    }
    return prefix + StringJoin(ids, delimiter) + suffix
}

public func IntrinsicKindToString(kind: IntrinsicKind): String {
    return match (kind) {
        case IntrinsicKind.NOT_INTRINSIC => "notIntrinsic"
        case IntrinsicKind.NOT_IMPLEMENTED => "notImplemented"
        case IntrinsicKind.ARRAY_INIT => "arrayInit"
        case IntrinsicKind.SIZE_OF => "sizeOfType"
        case IntrinsicKind.ALIGN_OF => "alignOfType"
        case IntrinsicKind.GET_TYPE_FOR_TYPE_PARAMETER => "getTypeForTypeParameter"
        case IntrinsicKind.IS_SUBTYPE_TYPES => "isSubtypeTypes"
        case IntrinsicKind.ARRAY_ACQUIRE_RAW_DATA => "acquireRawData"
        case IntrinsicKind.ARRAY_RELEASE_RAW_DATA => "releaseRawData"
        case IntrinsicKind.ARRAY_BUILT_IN_COPY_TO => "intrinsicBuiltInCopyTo"
        case IntrinsicKind.ARRAY_GET => "arrayGet"
        case IntrinsicKind.ARRAY_SET => "arraySet"
        case IntrinsicKind.ARRAY_GET_UNCHECKED => "arrayGetUnchecked"
        case IntrinsicKind.ARRAY_GET_REF_UNCHECKED => "arrayGetRefUnchecked"
        case IntrinsicKind.ARRAY_SET_UNCHECKED => "arraySetUnchecked"
        case IntrinsicKind.ARRAY_SIZE => "arraySize"
        case IntrinsicKind.ARRAY_CLONE => "arrayClone"
        case IntrinsicKind.ARRAY_SLICE_INIT => "arraySliceInit"
        case IntrinsicKind.ARRAY_SLICE => "arraySlice"
        case IntrinsicKind.ARRAY_SLICE_RAWARRAY => "rawArrayOfArraySlice"
        case IntrinsicKind.ARRAY_SLICE_START => "startOfArraySlice"
        case IntrinsicKind.ARRAY_SLICE_SIZE => "sizeOfArraySlice"
        case IntrinsicKind.ARRAY_SLICE_GET_ELEMENT => "arraySliceGet"
        case IntrinsicKind.ARRAY_SLICE_SET_ELEMENT => "arraySliceSet"
        case IntrinsicKind.ARRAY_SLICE_GET_ELEMENT_UNCHECKED => "arraySliceGetUnchecked"
        case IntrinsicKind.ARRAY_SLICE_SET_ELEMENT_UNCHECKED => "arraySliceSetUnchecked"
        case IntrinsicKind.FILL_IN_STACK_TRACE => "fillInStackTrace"
        case IntrinsicKind.DECODE_STACK_TRACE => "decodeStackTrace"
        case IntrinsicKind.DUMP_CURRENT_THREAD_INFO => "dumpCurrentThreadInfo"
        case IntrinsicKind.DUMP_ALL_THREADS_INFO => "dumpAllThreadsInfo"
        case IntrinsicKind.CHR => "chr"
        case IntrinsicKind.ORD => "ord"
        case IntrinsicKind.CPOINTER_GET_POINTER_ADDRESS => "getPointerAddress"
        case IntrinsicKind.CPOINTER_INIT0 => "pointerInit0"
        case IntrinsicKind.CPOINTER_INIT1 => "pointerInit1"
        case IntrinsicKind.CPOINTER_READ => "readPointer"
        case IntrinsicKind.CPOINTER_WRITE => "writePointer"
        case IntrinsicKind.CPOINTER_ADD => "addPointer"
        case IntrinsicKind.CSTRING_INIT => "_CString_init_"
        case IntrinsicKind.CSTRING_CONVERT_CSTR_TO_PTR => "convertCStr2Ptr"
        case IntrinsicKind.BIT_CAST => "bitCast"
        case IntrinsicKind.INOUT_PARAM => "_inout_"
        case IntrinsicKind.REGISTER_WATCHED_OBJECT => "registerWatchedObject"
        case IntrinsicKind.OBJECT_REFEQ => "intrinsicRefEq"
        case IntrinsicKind.RAW_ARRAY_REFEQ => "intrinsicRefEqRawArray"
        case IntrinsicKind.FUNC_REFEQ => "intrinsicRefEqFunc"
        case IntrinsicKind.OBJECT_ZERO_VALUE => "zeroValue"
        case IntrinsicKind.INVOKE_GC => "invokeGC"
        case IntrinsicKind.SET_GC_THRESHOLD => "setCjGCThreshold"
        case IntrinsicKind.GET_MAX_HEAP_SIZE => "getMaxCjHeapSize"
        case IntrinsicKind.GET_ALLOCATE_HEAP_SIZE => "getAllocatedCjHeapSize"
        case IntrinsicKind.DUMP_CJ_HEAP_DATA => "dumpCjHeapData"
        case IntrinsicKind.GET_GC_COUNT => "getCjGCCount"
        case IntrinsicKind.GET_GC_TIME_US => "getCjGCTime"
        case IntrinsicKind.GET_GC_FREED_SIZE => "getCjGCFreedSize"
        case IntrinsicKind.START_CJ_CPU_PROFILING => "startCjCPUProfiling"
        case IntrinsicKind.STOP_CJ_CPU_PROFILING => "stopCjCPUProfiling"
        case IntrinsicKind.GET_REAL_HEAP_SIZE => "getRealHeapSize"
        case IntrinsicKind.GET_THREAD_NUMBER => "getThreadNumber"
        case IntrinsicKind.GET_BLOCKING_THREAD_NUMBER => "getBlockingThreadNumber"
        case IntrinsicKind.GET_NATIVE_THREAD_NUMBER => "getNativeThreadNumber"
        case IntrinsicKind.VARRAY_SET => "varraySet"
        case IntrinsicKind.VARRAY_GET => "varrayGet"
        case IntrinsicKind.FUTURE_INIT => "futureInit"
        case IntrinsicKind.FUTURE_IS_COMPLETE => "futureIsComplete"
        case IntrinsicKind.FUTURE_WAIT => "futureWait"
        case IntrinsicKind.FUTURE_NOTIFYALL => "futureNotifyAll"
        case IntrinsicKind.IS_THREAD_OBJECT_INITED => "isThreadObjectInited"
        case IntrinsicKind.GET_THREAD_OBJECT => "getThreadObject"
        case IntrinsicKind.SET_THREAD_OBJECT => "setThreadObject"
        case IntrinsicKind.OVERFLOW_CHECKED_ADD => "checkedAdd"
        case IntrinsicKind.OVERFLOW_CHECKED_SUB => "checkedSub"
        case IntrinsicKind.OVERFLOW_CHECKED_MUL => "checkedMul"
        case IntrinsicKind.OVERFLOW_CHECKED_DIV => "checkedDiv"
        case IntrinsicKind.OVERFLOW_CHECKED_MOD => "checkedMod"
        case IntrinsicKind.OVERFLOW_CHECKED_POW => "checkedPow"
        case IntrinsicKind.OVERFLOW_CHECKED_INC => "checkedInc"
        case IntrinsicKind.OVERFLOW_CHECKED_DEC => "checkedDec"
        case IntrinsicKind.OVERFLOW_CHECKED_NEG => "checkedNeg"
        case IntrinsicKind.OVERFLOW_THROWING_ADD => "throwingAdd"
        case IntrinsicKind.OVERFLOW_THROWING_SUB => "throwingSub"
        case IntrinsicKind.OVERFLOW_THROWING_MUL => "throwingMul"
        case IntrinsicKind.OVERFLOW_THROWING_DIV => "throwingDiv"
        case IntrinsicKind.OVERFLOW_THROWING_MOD => "throwingMod"
        case IntrinsicKind.OVERFLOW_THROWING_POW => "throwingPow"
        case IntrinsicKind.OVERFLOW_THROWING_INC => "throwingInc"
        case IntrinsicKind.OVERFLOW_THROWING_DEC => "throwingDec"
        case IntrinsicKind.OVERFLOW_THROWING_NEG => "throwingNeg"
        case IntrinsicKind.OVERFLOW_SATURATING_ADD => "saturatingAdd"
        case IntrinsicKind.OVERFLOW_SATURATING_SUB => "saturatingSub"
        case IntrinsicKind.OVERFLOW_SATURATING_MUL => "saturatingMul"
        case IntrinsicKind.OVERFLOW_SATURATING_DIV => "saturatingDiv"
        case IntrinsicKind.OVERFLOW_SATURATING_MOD => "saturatingMod"
        case IntrinsicKind.OVERFLOW_SATURATING_POW => "saturatingPow"
        case IntrinsicKind.OVERFLOW_SATURATING_INC => "saturatingInc"
        case IntrinsicKind.OVERFLOW_SATURATING_DEC => "saturatingDec"
        case IntrinsicKind.OVERFLOW_SATURATING_NEG => "saturatingNeg"
        case IntrinsicKind.OVERFLOW_WRAPPING_ADD => "wrappingAdd"
        case IntrinsicKind.OVERFLOW_WRAPPING_SUB => "wrappingSub"
        case IntrinsicKind.OVERFLOW_WRAPPING_MUL => "wrappingMul"
        case IntrinsicKind.OVERFLOW_WRAPPING_DIV => "wrappingDiv"
        case IntrinsicKind.OVERFLOW_WRAPPING_MOD => "wrappingMod"
        case IntrinsicKind.OVERFLOW_WRAPPING_POW => "wrappingPow"
        case IntrinsicKind.OVERFLOW_WRAPPING_INC => "wrappingInc"
        case IntrinsicKind.OVERFLOW_WRAPPING_DEC => "wrappingDec"
        case IntrinsicKind.OVERFLOW_WRAPPING_NEG => "wrappingNeg"
        case IntrinsicKind.REFLECTION_INTRINSIC_START_FLAG => "reflectionIntrinsicStart"
        case IntrinsicKind.IS_INTERFACE => "isInterface"
        case IntrinsicKind.IS_CLASS => "isClass"
        case IntrinsicKind.IS_PRIMITIVE => "isPrimitive"
        case IntrinsicKind.IS_STRUCT => "isStruct"
        case IntrinsicKind.IS_GENERIC => "isGeneric"
        case IntrinsicKind.IS_TUPLE => "isTuple"
        case IntrinsicKind.IS_FUNCTION => "isFunction"
        case IntrinsicKind.IS_ENUM => "isEnum"
        case IntrinsicKind.IS_BOX => "isBox"
        case IntrinsicKind.GET_OR_CREATE_TYPEINFO_FOR_REFLECT => "getOrCreateTypeInfoForReflect"
        case IntrinsicKind.GET_TYPETEMPLATE => "getTypeTemplate"
        case IntrinsicKind.CHECK_METHOD_ACTUAL_ARGS => "checkMethodActualArgs"
        case IntrinsicKind.METHOD_ENTRYPOINT_IS_NULL => "methodEntryPointIsNull"
        case IntrinsicKind.IS_RELECT_UNSUPPORTED_TYPE => "isReflectUnsupportedType"
        case IntrinsicKind.GET_TYPE_FOR_ANY => "getTypeForAny"
        case IntrinsicKind.GET_TYPE_BY_MANGLED_NAME => "getTypeByMangledName"
        case IntrinsicKind.GET_TYPE_NAME => "getTypeName"
        case IntrinsicKind.GET_TYPE_BY_QUALIFIED_NAME => "getTypeByQualifiedName"
        case IntrinsicKind.GET_TYPE_QUALIFIED_NAME_LENGTH => "getTypeQualifiedNameLength"
        case IntrinsicKind.GET_TYPE_QUALIFIED_NAME => "getTypeQualifiedName"
        case IntrinsicKind.GET_NUM_OF_INTERFACE => "getNumOfInterface"
        case IntrinsicKind.GET_INTERFACE => "getInterface"
        case IntrinsicKind.IS_SUBTYPE => "isSubType"
        case IntrinsicKind.GET_TYPE_INFO_MODIFIER => "getTypeInfoModifier"
        case IntrinsicKind.GET_TYPE_INFO_ANNOTATIONS => "getTypeInfoAnnotations"
        case IntrinsicKind.GET_OBJ_CLASS => "getObjClass"
        case IntrinsicKind.GET_SUPER_TYPE_INFO => "getSuperTypeInfo"
        case IntrinsicKind.GET_TYPE_ARGS => "getTypeArgs"
        case IntrinsicKind.GET_NUM_OF_INSTANCE_METHOD_INFOS => "getNumOfInstanceMethodInfos"
        case IntrinsicKind.GET_INSTANCE_METHOD_INFO => "getInstanceMethodInfo"
        case IntrinsicKind.GET_NUM_OF_STATIC_METHOD_INFOS => "getNumOfStaticMethodInfos"
        case IntrinsicKind.GET_STATIC_METHOD_INFO => "getStaticMethodInfo"
        case IntrinsicKind.GET_METHOD_NAME => "getMethodName"
        case IntrinsicKind.GET_METHOD_RETURN_TYPE => "getMethodReturnType"
        case IntrinsicKind.GET_METHOD_MODIFIER => "getMethodModifier"
        case IntrinsicKind.GET_METHOD_ANNOTATIONS => "getMethodAnnotations"
        case IntrinsicKind.APPLY_CJ_METHOD => "applyCJInstanceMethod"
        case IntrinsicKind.APPLY_CJ_STATIC_METHOD => "applyCJStaticMethod"
        case IntrinsicKind.APPLY_CJ_GENERIC_METHOD => "applyCJGenericInstanceMethod"
        case IntrinsicKind.APPLY_CJ_GENERIC_STATIC_METHOD => "applyCJGenericStaticMethod"
        case IntrinsicKind.GET_NUM_OF_ACTUAL_PARAMETERS => "getNumOfActualParameters"
        case IntrinsicKind.GET_NUM_OF_GENERIC_PARAMETERS => "getNumOfGenericParameters"
        case IntrinsicKind.GET_ACTUAL_PARAMETER_INFO => "getActualParameterInfo"
        case IntrinsicKind.GET_GENERIC_PARAMETER_INFO => "getGenericParameterInfo"
        case IntrinsicKind.GET_NUM_OF_INSTANCE_FIELD_INFOS => "getNumOfInstanceFieldInfos"
        case IntrinsicKind.GET_INSTANCE_FIELD_INFO => "getInstanceFieldInfo"
        case IntrinsicKind.GET_NUM_OF_STATIC_FIELD_INFOS => "getNumOfStaticFieldInfos"
        case IntrinsicKind.GET_STATIC_FIELD_INFO => "getStaticFieldInfo"
        case IntrinsicKind.GET_STATIC_FIELD_NAME => "getStaticFieldName"
        case IntrinsicKind.GET_STATIC_FIELD_TYPE => "getStaticFieldType"
        case IntrinsicKind.GET_STATIC_FIELD_ANNOTATIONS => "getStaticFieldAnnotations"
        case IntrinsicKind.GET_INSTANCE_FIELD_NAME => "getInstanceFieldName"
        case IntrinsicKind.GET_INSTANCE_FIELD_TYPE => "getInstanceFieldType"
        case IntrinsicKind.GET_INSTANCE_FIELD_ANNOTATIONS => "getInstanceFieldAnnotations"
        case IntrinsicKind.GET_INSTANCE_FIELD_MODIFIER => "getInstanceFieldModifier"
        case IntrinsicKind.GET_STATIC_FIELD_MODIFIER => "getStaticFieldModifier"
        case IntrinsicKind.GET_FIELD_VALUE => "getInstanceFieldValue"
        case IntrinsicKind.SET_FIELD_VALUE => "setInstanceFieldValue"
        case IntrinsicKind.GET_STATIC_FIELD_VALUE => "getStaticFieldValue"
        case IntrinsicKind.SET_STATIC_FIELD_VALUE => "setStaticFieldValue"
        case IntrinsicKind.GET_FIELD_DECLARING_TYPE => "getFieldDeclaringType"
        case IntrinsicKind.GET_PARAMETER_INDEX => "getParameterIndex"
        case IntrinsicKind.GET_PARAMETER_NAME => "getParameterName"
        case IntrinsicKind.GET_PARAMETER_TYPE => "getParameterType"
        case IntrinsicKind.GET_PARAMETER_ANNOTATIONS => "getParameterAnnotations"
        case IntrinsicKind.GET_RELATED_PACKAGE_INF => "getRelatedPackageInfo"
        case IntrinsicKind.GET_PACKAGE_NAME => "getPackageName"
        case IntrinsicKind.GET_PACKAGE_NUM_OF_TYPE_INFOS => "getPackageNumOfTypeInfos"
        case IntrinsicKind.GET_PACKAGE_TYPE_INFO => "getPackageTypeInfo"
        case IntrinsicKind.GET_PACKAGE_NUM_OF_GLOBAL_METHODS => "getPackageNumOfGlobalMethodInfos"
        case IntrinsicKind.GET_PACKAGE_GLOBAL_METHOD_INFO => "getPackageGlobalMethodInfo"
        case IntrinsicKind.GET_PACKAGE_NUM_OF_GLOBAL_FIELD_INFOS => "getPackageNumOfGlobalFieldInfos"
        case IntrinsicKind.GET_PACKAGE_GLOBAL_FIELD_INFO => "getPackageGlobalFieldInfo"
        case IntrinsicKind.LOAD_PACKAGE => "loadPackage"
        case IntrinsicKind.GET_PACKAGE_BY_QUALIFIEDNAME => "getPackageByQualifiedName"
        case IntrinsicKind.GET_PACKAGE_VERSION => "getPackageVersion"
        case IntrinsicKind.GET_SUB_PACKAGES => "getSubPackages"
        case IntrinsicKind.GET_NUM_OF_FIELD_TYPES => "getNumOfFieldTypes"
        case IntrinsicKind.GET_FIELD_TYPES => "getFieldTypes"
        case IntrinsicKind.NEW_AND_INIT_OBJECT => "newAndInitEnumTupleObject"
        case IntrinsicKind.GET_ASSOCIATED_VALUES => "getAssociatedValues"
        case IntrinsicKind.GET_NUM_OF_FUNCTION_SIGNATURETYPES => "getNumOfFunctionSignatureTypes"
        case IntrinsicKind.GET_FUNCTION_SIGNATURE_TYPES => "getFunctionSignatureTypes"
        case IntrinsicKind.GET_NUM_OF_ENUM_CONSTRUCTOR_INFOS => "getNumOfEnumConstructorInfos"
        case IntrinsicKind.GET_ENUM_CONSTRUCTOR_INFO => "getEnumConstructorInfo"
        case IntrinsicKind.GET_ENUM_CONSTRUCTOR_NAME => "getEnumConstructorName"
        case IntrinsicKind.GET_ENUM_CONSTRUCTOR_INFO_FROM_ANY => "getEnumConstructorInfoFromAny"
        case IntrinsicKind.REFLECTION_INTRINSIC_END_FLAG => "reflectionIntrinsicEnd"
        case IntrinsicKind.SLEEP => "intrinsicSleep"
        case IntrinsicKind.SOURCE_FILE => "sourceFile"
        case IntrinsicKind.SOURCE_LINE => "sourceLine"
        case IntrinsicKind.IDENTITY_HASHCODE => "identityHashCodeForRefType"
        case IntrinsicKind.IDENTITY_HASHCODE_FOR_ARRAY => "identityHashCodeForArrayType"
        case IntrinsicKind.ATOMIC_LOAD => "load"
        case IntrinsicKind.ATOMIC_STORE => "store"
        case IntrinsicKind.ATOMIC_SWAP => "swap"
        case IntrinsicKind.ATOMIC_COMPARE_AND_SWAP => "compareAndSwap"
        case IntrinsicKind.ATOMIC_FETCH_ADD => "fetchAdd"
        case IntrinsicKind.ATOMIC_FETCH_SUB => "fetchSub"
        case IntrinsicKind.ATOMIC_FETCH_AND => "fetchAnd"
        case IntrinsicKind.ATOMIC_FETCH_OR => "fetchOr"
        case IntrinsicKind.ATOMIC_FETCH_XOR => "fetchXor"
        case IntrinsicKind.MUTEX_INIT => "mutexInit"
        case IntrinsicKind.CJ_MUTEX_LOCK => "mutexLock"
        case IntrinsicKind.MUTEX_TRY_LOCK => "mutexTryLock"
        case IntrinsicKind.MUTEX_CHECK_STATUS => "mutexCheckStatus"
        case IntrinsicKind.MUTEX_UNLOCK => "mutexUnlock"
        case IntrinsicKind.WAITQUEUE_INIT => "waitQueueInit"
        case IntrinsicKind.MONITOR_INIT => "monitorInit"
        case IntrinsicKind.MOITIOR_WAIT => "monitorWait"
        case IntrinsicKind.MOITIOR_NOTIFY => "monitorNotify"
        case IntrinsicKind.MOITIOR_NOTIFY_ALL => "monitorNotifyAll"
        case IntrinsicKind.MULTICONDITION_WAIT => "multiConditionMonitorWait"
        case IntrinsicKind.MULTICONDITION_NOTIFY => "multiConditionMonitorNotify"
        case IntrinsicKind.MULTICONDITION_NOTIFY_ALL => "multiConditionMonitorNotifyAll"
        case IntrinsicKind.VECTOR_COMPARE_32 => "vectorCompare32"
        case IntrinsicKind.VECTOR_INDEX_BYTE_32 => "vectorIndexByte32"
        case IntrinsicKind.CJ_CORE_CAN_USE_SIMD => "CJ_CORE_CanUseSIMD"
        case IntrinsicKind.CROSS_ACCESS_BARRIER => "CrossAccessBarrier"
        case IntrinsicKind.CREATE_EXPORT_HANDLE => "CreateExportHandle"
        case IntrinsicKind.GET_EXPORTED_REF => "GetExportedRef"
        case IntrinsicKind.REMOVE_EXPORTED_REF => "RemoveExportedRef"
        case IntrinsicKind.GET_JSLAMBDA_ADDR => "GetJSLambdaAddr"
        case IntrinsicKind.CJ_TLS_DYN_SET_SESSION_CALLBACK => "CJ_TLS_DYN_SetSessionCallback"
        case IntrinsicKind.CJ_TLS_DYN_SSL_INIT => "CJ_TLS_DYN_SslInit"
        case IntrinsicKind.CG_UNSAFE_BEGIN => "cgUnsafeBegin"
        case IntrinsicKind.CG_UNSAFE_END => "cgUnsafeEnd"
        case IntrinsicKind.BEGIN_CATCH => "beginCatch"
        case IntrinsicKind.ABS => "abs"
        case IntrinsicKind.FABS => "fabs"
        case IntrinsicKind.FLOOR => "floor"
        case IntrinsicKind.CEIL => "ceil"
        case IntrinsicKind.TRUNC => "trunc"
        case IntrinsicKind.SIN => "sin"
        case IntrinsicKind.COS => "cos"
        case IntrinsicKind.EXP => "exp"
        case IntrinsicKind.EXP2 => "exp2"
        case IntrinsicKind.LOG => "log"
        case IntrinsicKind.LOG2 => "log2"
        case IntrinsicKind.LOG10 => "log10"
        case IntrinsicKind.SQRT => "sqrt"
        case IntrinsicKind.ROUND => "round"
        case IntrinsicKind.POW => "pow"
        case IntrinsicKind.POWI => "powi"
        case IntrinsicKind.PREINITIALIZE => "preinitialize"
        case IntrinsicKind.OBJECT_AS => "object.as"
        case IntrinsicKind.IS_NULL => "isNull"
        case IntrinsicKind.BLACK_BOX => "blackBox"
        case IntrinsicKind.EXCLUSIVE_SCOPE => "exclusiveScopeImpl"
        case _ => throw IllegalArgumentException("invalid intrinsic kind")
    }
}

public func AddNewLineOrNot(message: String): String {
    if (message.isEmpty()) {
        return ""
    }
    return message + "\n"
}

public func CommentToString(message: ArrayList<String>): String {
    return CommentToString(StringJoin(message, ", "))
}

public func CommentToString(message: String): String {
    if (message.isEmpty()) {
        return ""
    }
    return " // " + message
}
