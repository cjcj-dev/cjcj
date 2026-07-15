package cjcj::codegen

import std.collection.*
import cjcj::chir.Apply
import cjcj::chir.ApplyWithException
import cjcj::chir.BoolLiteral
import cjcj::chir.BoxType
import cjcj::chir.ClassType
import cjcj::chir.CPointerType
import cjcj::chir.CustomType
import cjcj::chir.EnumType
import cjcj::chir.Expression
import cjcj::chir.ExprKind
import cjcj::chir.Field
import cjcj::chir.FloatLiteral
import cjcj::chir.FuncType
import cjcj::chir.Function
import cjcj::chir.GenericType
import cjcj::chir.GetMethodIdxInAutoEnvObject
import cjcj::chir.IntLiteral
import cjcj::chir.IntrinsicKind
import cjcj::chir.LiteralValue
import cjcj::chir.Load
import cjcj::chir.LocalVar
import cjcj::chir.RawArrayType
import cjcj::chir.RuneLiteral
import cjcj::chir.StringLiteral
import cjcj::chir.StructType
import cjcj::chir.TupleType
import cjcj::chir.Type
import cjcj::chir.TypeCast
import cjcj::chir.TypeKind
import cjcj::chir.Value
import cjcj::chir.VArrayBuilder
import cjcj::chir.VArrayType
import cjcj::option.{ArchType, EnvironmentType, OptimizationLevel}
import cjcj::utils.{CJC_ABORT, CJC_ASSERT, StaticCast}

private let CREATE_OVERFLOW_EXCEPTION_FUNC_NAME: String = "rt$CreateOverflowException_msg"
private let CREATE_ARITHMETIC_EXCEPTION_FUNC_NAME: String = "rt$CreateArithmeticException_msg"
private let THROW_EXCEPTION_FUNC_NAME: String = PREFIX_OF_BACKEND_SYMS + "ThrowException"
private let THROW_NEGATIVE_ARRAY_SIZE_EXCEPTION_FUNC_NAME: String = "rt$ThrowNegativeArraySizeException"
private let THROW_EXCEPTION_INTRINSIC_NAME: String = "llvm.cj.throw.exception"
private let GET_EXCEPTION_WRAPPER_INTRINSIC_NAME: String = "llvm.cj.get.exception.wrapper"
private let POST_THROW_EXCEPTION_INTRINSIC_NAME: String = "llvm.cj.post.throw.exception"
private let MALLOC_ARRAY_INTRINSIC_NAME: String = "llvm.cj.malloc.array"
private let MALLOC_ARRAY_GENERIC_INTRINSIC_NAME: String = "llvm.cj.malloc.array.generic"
private let ARRAY_COPY_REF_INTRINSIC_NAME: String = "llvm.cj.array.copy.ref"
private let ARRAY_COPY_STRUCT_INTRINSIC_NAME: String = "llvm.cj.array.copy.struct"
private let ARRAY_COPY_GENERIC_INTRINSIC_NAME: String = "llvm.cj.array.copy.generic"
private let ALLOCA_GENERIC_INTRINSIC_NAME: String = "llvm.cj.alloca.generic"
private let ASSIGN_GENERIC_INTRINSIC_NAME: String = "llvm.cj.assign.generic"
private let GET_TYPE_INFO_INTRINSIC_NAME: String = "llvm.cj.get.type.info"
private let IS_REFERENCE_INTRINSIC_NAME: String = "llvm.cj.is.reference"
private let GET_FIELD_OFFSET_INTRINSIC_NAME: String = "llvm.cj.get.field.offset"
private let GCREAD_GENERIC_INTRINSIC_NAME: String = "llvm.cj.gcread.generic"
private let GCWRITE_GENERIC_INTRINSIC_NAME: String = "llvm.cj.gcwrite.generic"
private let GCWRITE_GENERIC_PAYLOAD_INTRINSIC_NAME: String = "llvm.cj.gcwrite.generic.payload"
private let MALLOC_OBJECT_INTRINSIC_NAME: String = "llvm.cj.malloc.object"
private let CJ_MEMSET_INTRINSIC_NAME: String = "llvm.cj.memset"
private let GCWRITE_REF_INTRINSIC_NAME: String = "llvm.cj.gcwrite.ref"
private let GCREAD_WEAK_REF_INTRINSIC_NAME: String = "llvm.cj.gcread.weakref"
private let GCREAD_STATIC_REF_INTRINSIC_NAME: String = "llvm.cj.gcread.static.ref"
private let GCWRITE_STATIC_REF_INTRINSIC_NAME: String = "llvm.cj.gcwrite.static.ref"
private let SET_LOCATION_INTRINSIC_NAME: String = "llvm.cj.set.location"
private let FILL_IN_STACK_TRACE_INTRINSIC_NAME: String = "llvm.cj.fill.in.stack.trace"
private let NEW_CJ_THREAD_FUNC_NAME: String = PREFIX_OF_BACKEND_SYMS + "NewCJThread"
private let NEW_CJ_THREAD_NO_RETURN_FUNC_NAME: String = PREFIX_OF_BACKEND_SYMS + "NewCJThreadNoReturn"
private let MIN_ANDROID_ARM32_ENUM_ALIGN: UInt32 = 4u32
private let SEQ_CST_AS_INT32: Int64 = 5
private let LLVM_INTEGER_TYPE_KIND: Int32 = 8
private let LLVM_FUNCTION_TYPE_KIND: Int32 = 9
private let LLVM_STRUCT_TYPE_KIND: Int32 = 10
private let LLVM_ARRAY_TYPE_KIND: Int32 = 11
private let LLVM_POINTER_TYPE_KIND: Int32 = 12
private let LLVM_VECTOR_TYPE_KIND: Int32 = 13
private let LLVM_SCALABLE_VECTOR_TYPE_KIND: Int32 = 17

foreign {
    func LLVMGetElementType(valueType: LLVMTypeRef): LLVMTypeRef
}

private func SignedInt64Bits(value: Int64): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return 0x8000000000000000u64 + UInt64(value - Int64.Min)
}

private func IsLoadExprForAllocatedGenericRef(chirExpression: Expression): Bool {
    if (chirExpression.GetExprKind() != ExprKind.LOAD) {
        return false
    }
    let loadExpression = (chirExpression as Load).getOrThrow()
    let location = loadExpression.GetLocation()
    if (!location.IsLocalVar() || !IsGenericRef(location.GetType().getOrThrow())) {
        return false
    }
    let locationExpr = (location as LocalVar).getOrThrow().GetExpr().getOrThrow()
    let locationExprKind = locationExpr.GetExprKind()
    return locationExprKind == ExprKind.ALLOCATE || locationExprKind == ExprKind.ALLOCATE_WITH_EXCEPTION
}

private func IntrinsicRuntimeFunctionName(kind: IntrinsicKind): Option<String> {
    return match (kind) {
        case IntrinsicKind.FUTURE_INIT => Some("CJ_MCC_FutureInit")
        case IntrinsicKind.FUTURE_IS_COMPLETE => Some("CJ_MCC_FutureIsComplete")
        case IntrinsicKind.FUTURE_WAIT => Some("CJ_MCC_FutureWait")
        case IntrinsicKind.FUTURE_NOTIFYALL => Some("CJ_MCC_FutureNotifyAll")
        case IntrinsicKind.IS_THREAD_OBJECT_INITED => Some("CJ_MCC_IsThreadObjectInited")
        case IntrinsicKind.GET_THREAD_OBJECT => Some("CJ_MCC_GetCurrentCJThreadObject")
        case IntrinsicKind.SET_THREAD_OBJECT => Some("CJ_MCC_SetCurrentCJThreadObject")
        case IntrinsicKind.MUTEX_INIT => Some("CJ_MCC_MutexInit")
        case IntrinsicKind.CJ_MUTEX_LOCK => Some("CJ_MCC_MutexLock")
        case IntrinsicKind.MUTEX_TRY_LOCK => Some("CJ_MCC_MutexTryLock")
        case IntrinsicKind.MUTEX_CHECK_STATUS => Some("CJ_MCC_MutexCheckStatus")
        case IntrinsicKind.MUTEX_UNLOCK => Some("CJ_MCC_MutexUnlock")
        case IntrinsicKind.WAITQUEUE_INIT => Some("CJ_MCC_WaitQueueInit")
        case IntrinsicKind.MONITOR_INIT => Some("CJ_MCC_WaitQueueForMonitorInit")
        case IntrinsicKind.MOITIOR_WAIT => Some("CJ_MCC_MonitorWait")
        case IntrinsicKind.MOITIOR_NOTIFY => Some("CJ_MCC_MonitorNotify")
        case IntrinsicKind.MOITIOR_NOTIFY_ALL => Some("CJ_MCC_MonitorNotifyAll")
        case IntrinsicKind.MULTICONDITION_WAIT => Some("CJ_MCC_MultiConditionMonitorWait")
        case IntrinsicKind.MULTICONDITION_NOTIFY => Some("CJ_MCC_MultiConditionMonitorNotify")
        case IntrinsicKind.MULTICONDITION_NOTIFY_ALL => Some("CJ_MCC_MultiConditionMonitorNotifyAll")
        case IntrinsicKind.SLEEP => Some("CJ_MRT_Sleep")
        case _ => None
    }
}

private func IntrinsicHasFastNativeAttr(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.FUTURE_INIT ||
        kind == IntrinsicKind.FUTURE_IS_COMPLETE ||
        kind == IntrinsicKind.FUTURE_NOTIFYALL ||
        kind == IntrinsicKind.IS_THREAD_OBJECT_INITED ||
        kind == IntrinsicKind.GET_THREAD_OBJECT ||
        kind == IntrinsicKind.SET_THREAD_OBJECT ||
        kind == IntrinsicKind.MUTEX_INIT ||
        kind == IntrinsicKind.MUTEX_TRY_LOCK ||
        kind == IntrinsicKind.MUTEX_CHECK_STATUS ||
        kind == IntrinsicKind.MUTEX_UNLOCK ||
        kind == IntrinsicKind.WAITQUEUE_INIT ||
        kind == IntrinsicKind.MONITOR_INIT ||
        kind == IntrinsicKind.MOITIOR_NOTIFY ||
        kind == IntrinsicKind.MOITIOR_NOTIFY_ALL ||
        kind == IntrinsicKind.MULTICONDITION_NOTIFY ||
        kind == IntrinsicKind.MULTICONDITION_NOTIFY_ALL
}

private func IntrinsicFunctionAttributes(kind: IntrinsicKind): ArrayList<String> {
    let attributes = ArrayList<String>()
    if (IntrinsicHasFastNativeAttr(kind)) {
        attributes.add(FAST_NATIVE_ATTR)
    }
    return attributes
}

private func IntrinsicLLVMName(kind: IntrinsicKind): Option<String> {
    return match (kind) {
        case IntrinsicKind.GET_MAX_HEAP_SIZE => Some("llvm.cj.get.max.heap.size")
        case IntrinsicKind.GET_ALLOCATE_HEAP_SIZE => Some("llvm.cj.get.allocated.heap.size")
        case IntrinsicKind.GET_REAL_HEAP_SIZE => Some("llvm.cj.get.real.heap.size")
        case IntrinsicKind.GET_THREAD_NUMBER => Some("llvm.cj.get.thread.number")
        case IntrinsicKind.GET_BLOCKING_THREAD_NUMBER => Some("llvm.cj.get.blocking.thread.number")
        case IntrinsicKind.GET_NATIVE_THREAD_NUMBER => Some("llvm.cj.get.native.thread.number")
        case IntrinsicKind.DUMP_CJ_HEAP_DATA => Some("llvm.cj.dump.heap.data")
        case IntrinsicKind.GET_GC_COUNT => Some("llvm.cj.get.gc.count")
        case IntrinsicKind.GET_GC_TIME_US => Some("llvm.cj.get.gc.time.us")
        case IntrinsicKind.GET_GC_FREED_SIZE => Some("llvm.cj.get.gc.freed.size")
        case IntrinsicKind.START_CJ_CPU_PROFILING => Some("llvm.cj.start.cpu.profiling")
        case IntrinsicKind.STOP_CJ_CPU_PROFILING => Some("llvm.cj.stop.cpu.profiling")
        case IntrinsicKind.INVOKE_GC => Some("llvm.cj.invoke.gc")
        case IntrinsicKind.SET_GC_THRESHOLD => Some("llvm.cj.set.gc.threshold")
        case IntrinsicKind.CROSS_ACCESS_BARRIER => Some("llvm.cj.cross.access.barrier")
        case IntrinsicKind.CREATE_EXPORT_HANDLE => Some("llvm.cj.create.export.handle")
        case IntrinsicKind.GET_EXPORTED_REF => Some("llvm.cj.get.exported.ref")
        case IntrinsicKind.REMOVE_EXPORTED_REF => Some("llvm.cj.remove.exported.ref")
        case IntrinsicKind.GET_JSLAMBDA_ADDR => Some("llvm.cj.get.lambda.addr")
        case IntrinsicKind.ABS => Some("llvm.abs")
        case IntrinsicKind.FABS => Some("llvm.fabs")
        case IntrinsicKind.FLOOR => Some("llvm.floor")
        case IntrinsicKind.CEIL => Some("llvm.ceil")
        case IntrinsicKind.TRUNC => Some("llvm.trunc")
        case IntrinsicKind.SIN => Some("llvm.sin")
        case IntrinsicKind.COS => Some("llvm.cos")
        case IntrinsicKind.EXP => Some("llvm.exp")
        case IntrinsicKind.EXP2 => Some("llvm.exp2")
        case IntrinsicKind.LOG => Some("llvm.log")
        case IntrinsicKind.LOG2 => Some("llvm.log2")
        case IntrinsicKind.LOG10 => Some("llvm.log10")
        case IntrinsicKind.SQRT => Some("llvm.sqrt")
        case IntrinsicKind.ROUND => Some("llvm.round")
        case IntrinsicKind.POW => Some("llvm.pow")
        case IntrinsicKind.POWI => Some("llvm.powi")
        case IntrinsicKind.ATOMIC_STORE => Some("llvm.cj.atomic.store")
        case IntrinsicKind.ATOMIC_COMPARE_AND_SWAP => Some("llvm.cj.atomic.compare.swap")
        case IntrinsicKind.ATOMIC_LOAD => Some("llvm.cj.atomic.load")
        case IntrinsicKind.ATOMIC_SWAP => Some("llvm.cj.atomic.swap")
        case IntrinsicKind.BLACK_BOX => Some("llvm.cj.blackhole")
        case _ => None
    }
}

private func IsPlatformDependent(kind: IntrinsicKind): Bool {
    return kind == IntrinsicKind.GET_MAX_HEAP_SIZE ||
        kind == IntrinsicKind.GET_ALLOCATE_HEAP_SIZE ||
        kind == IntrinsicKind.GET_REAL_HEAP_SIZE ||
        kind == IntrinsicKind.GET_THREAD_NUMBER ||
        kind == IntrinsicKind.GET_BLOCKING_THREAD_NUMBER ||
        kind == IntrinsicKind.GET_NATIVE_THREAD_NUMBER ||
        kind == IntrinsicKind.GET_GC_COUNT ||
        kind == IntrinsicKind.GET_GC_FREED_SIZE
}

private func IsReflectIntrinsicFunctionName(name: String): Bool {
    return name == "CJ_MCC_ApplyCJInstanceMethod" ||
        name == "CJ_MCC_ApplyCJStaticMethod" ||
        name == "CJ_MCC_ApplyCJGenericInstanceMethod" ||
        name == "CJ_MCC_ApplyCJGenericStaticMethod" ||
        name == "CJ_MCC_CheckMethodActualArgs" ||
        name == "CJ_MCC_GetOrCreateTypeInfoForReflect" ||
        name == "CJ_MCC_NewAndInitEnumTupleObject"
}

private class ByteArrayInfo {
    public let arrPtr: LLVMValueRef
    public let arrType: LLVMTypeRef
    public let dataSize: LLVMValueRef
    public let index: LLVMValueRef

    public init(arrPtr: LLVMValueRef, arrType: LLVMTypeRef, dataSize: LLVMValueRef, index: LLVMValueRef) {
        this.arrPtr = arrPtr
        this.arrType = arrType
        this.dataSize = dataSize
        this.index = index
    }
}

private func CreateArrayMemSet(irBuilder: IRBuilder2, arrInfo: ByteArrayInfo, value: LLVMValueRef): Unit {
    let valueType = unsafe { LLVMTypeOf(value) }
    let isInputValid = irBuilder.GetCGModule().GetTypeSize(valueType) == 1u64
    CJC_ASSERT(isInputValid)
    let memSetValue = if (unsafe { LLVMGetTypeKind(valueType) } == LLVM_INTEGER_TYPE_KIND &&
        unsafe { LLVMGetIntTypeWidth(valueType) } == 8u32) {
        value
    } else {
        irBuilder.CreateZExt(value, unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) })
    }
    let dataPtr = irBuilder.CreateGEP(arrInfo.arrType, arrInfo.arrPtr, ArrayList<LLVMValueRef>(
        [irBuilder.GetInt32(0), irBuilder.GetInt32(1), arrInfo.index]))
    let _ = irBuilder.CreateMemSet(dataPtr, memSetValue, arrInfo.dataSize, align: 1u32)
}

private func InitByteArrayData(irBuilder: IRBuilder2, arrPtr: LLVMValueRef, arrayLen: LLVMValueRef,
    value: LLVMValueRef, arrayType: LLVMTypeRef): Unit {
    let arrayPtr = irBuilder.CreateBitCast(irBuilder.GetPayloadFromObject(arrPtr),
        unsafe { LLVMPointerType(arrayType, 1u32) })
    let valType = unsafe { LLVMTypeOf(value) }
    let initValue = if (unsafe { LLVMGetTypeKind(valType) } == LLVM_POINTER_TYPE_KIND) {
        let i8Type = unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) }
        let addressSpace = unsafe { LLVMGetPointerAddressSpace(valType) }
        irBuilder.CreateLoad(i8Type, irBuilder.CreateBitCast(value, unsafe { LLVMPointerType(i8Type, addressSpace) }))
    } else {
        value
    }
    if (unsafe { LLVMSelfhostIsConstantInt(arrayLen) } != 0 &&
        unsafe { LLVMConstIntGetZExtValue(arrayLen) } <= 2147483647u64) {
        CreateArrayMemSet(irBuilder, ByteArrayInfo(arrayPtr, arrayType, arrayLen, irBuilder.GetInt64(0)), initValue)
        return
    }

    let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>([GenNameForBB("byte.arr.init.start"),
        GenNameForBB("byte.arr.init.body"), GenNameForBB("byte.arr.init.end")]))
    CJC_ASSERT(blocks.size >= 3)
    let whileLoopHeader = blocks[0]
    let whileLoopBody = blocks[1]
    let afterWhileLoop = blocks[2]
    let sizeOf2G = irBuilder.GetInt64(2147483647)
    let i64Ty = unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
    let iterator = irBuilder.CreateEntryAlloca(i64Ty, name: "iterator")
    irBuilder.CreateStore(irBuilder.GetInt64(0), iterator)
    irBuilder.CreateBr(whileLoopHeader)

    irBuilder.SetInsertPoint(whileLoopHeader)
    let iteratorPlus2G = irBuilder.CreateBinary(ExprKind.ADD, irBuilder.CreateLoad(i64Ty, iterator), sizeOf2G)
    let cmpResult = irBuilder.CreateICmp(LLVMIntPredicate.SLT, iteratorPlus2G, arrayLen, name: "max.size")
    irBuilder.CreateCondBr(cmpResult, whileLoopBody, afterWhileLoop)

    irBuilder.SetInsertPoint(whileLoopBody)
    let iteratorIndex = irBuilder.CreateLoad(i64Ty, iterator)
    CreateArrayMemSet(irBuilder, ByteArrayInfo(arrayPtr, arrayType, sizeOf2G, iteratorIndex), initValue)
    let newIterator = irBuilder.CreateBinary(ExprKind.ADD, iteratorIndex, sizeOf2G)
    irBuilder.CreateStore(newIterator, iterator)
    irBuilder.CreateBr(whileLoopHeader)

    irBuilder.SetInsertPoint(afterWhileLoop)
    let index = irBuilder.CreateLoad(i64Ty, iterator)
    let residualSize = irBuilder.CreateBinary(ExprKind.SUB, arrayLen, index)
    CreateArrayMemSet(irBuilder, ByteArrayInfo(arrayPtr, arrayType, residualSize, index), initValue)
}

private func InitArrayDataUG(irBuilder: IRBuilder2, arrPtr: LLVMValueRef, arrayLen: LLVMValueRef,
    value: LLVMValueRef, arrayType: LLVMTypeRef, arrTy: RawArrayType): Unit {
    let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>([GenNameForBB("arr.init.start"),
        GenNameForBB("arr.init.body"), GenNameForBB("arr.init.end")]))
    CJC_ASSERT(blocks.size >= 3)
    let startBB = blocks[0]
    let bodyBB = blocks[1]
    let endBB = blocks[2]
    let isNotZeroLen = irBuilder.GenerateCallExpectFunction(irBuilder.CreateICmp(LLVMIntPredicate.NE, arrayLen,
        irBuilder.GetInt64(0)), irBuilder.GetTrue())
    irBuilder.CreateCondBr(isNotZeroLen, startBB, endBB)
    irBuilder.SetInsertPoint(startBB)
    let i64Ty = unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
    let iterator = irBuilder.CreateEntryAlloca(i64Ty, name: "iterator")
    irBuilder.CreateStore(irBuilder.GetInt64(0), iterator, isVolatile: true)
    irBuilder.CreateBr(bodyBB)

    irBuilder.SetInsertPoint(bodyBB)
    let index = irBuilder.CreateLoad(i64Ty, iterator)
    var offset = irBuilder.CallIntrinsicGetFieldOffset(ArrayList<LLVMValueRef>([
        irBuilder.CreateTypeInfo(arrTy), index, irBuilder.GetInt32(8)]))
    offset = irBuilder.CreateBinary(ExprKind.ADD, offset, unsafe {
        LLVMConstInt(LLVMTypeOf(offset), irBuilder.GetPayloadOffset(), 0)
    })
    let fieldType = arrTy.GetElementType()
    var fieldAddr = irBuilder.CreateInBoundsGEP(unsafe { LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw) },
        arrPtr, ArrayList<LLVMValueRef>([offset]))
    let fieldAddrCGType = CGType.GetOrCreate(irBuilder.GetCGModule(),
        CGType.GetRefTypeOf(irBuilder.GetCGContext().GetCHIRBuilder(), fieldType))
    let fieldCGType = CGType.GetOrCreate(irBuilder.GetCGModule(), fieldType)
    if (!fieldType.IsGeneric()) {
        fieldAddr = irBuilder.CreateBitCast(fieldAddr, unsafe { LLVMPointerType(fieldCGType.GetLLVMType(), 1u32) })
    }
    irBuilder.GetCGContext().SetBasePtr(fieldAddr, arrPtr)
    irBuilder.CreateStore(CGValue(value, fieldCGType), CGValue(fieldAddr, fieldAddrCGType))
    let incremented = irBuilder.CreateBinary(ExprKind.ADD, index, irBuilder.GetInt64(1))
    irBuilder.CreateStore(incremented, iterator)
    let cmpResult = irBuilder.CreateICmp(LLVMIntPredicate.SLT, incremented, arrayLen, name: "iterator.size.cmp")
    irBuilder.CreateCondBr(cmpResult, bodyBB, endBB)
    irBuilder.SetInsertPoint(endBB)
}

private func InitArrayData(irBuilder: IRBuilder2, arrPtr: LLVMValueRef, arrayLen: LLVMValueRef,
    value: LLVMValueRef, arrayType: LLVMTypeRef): Unit {
    let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>([GenNameForBB("arr.init.start"),
        GenNameForBB("arr.init.body"), GenNameForBB("arr.init.end")]))
    CJC_ASSERT(blocks.size >= 3)
    let startBB = blocks[0]
    let bodyBB = blocks[1]
    let endBB = blocks[2]
    irBuilder.CreateBr(startBB)
    irBuilder.SetInsertPoint(startBB)
    let i64Ty = unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
    let iterator = irBuilder.CreateEntryAlloca(i64Ty, name: "iterator")
    irBuilder.CreateStore(irBuilder.GetInt64(0), iterator)
    irBuilder.CreateBr(bodyBB)

    irBuilder.SetInsertPoint(bodyBB)
    let index = irBuilder.CreateLoad(i64Ty, iterator)
    let arrHead = irBuilder.CreateBitCast(irBuilder.GetPayloadFromObject(arrPtr),
        unsafe { LLVMPointerType(arrayType, 1u32) })
    let dataPtr = irBuilder.CreateGEP(arrayType, arrHead, ArrayList<LLVMValueRef>([
        irBuilder.GetInt32(0), irBuilder.GetInt32(1), irBuilder.GetInt32(0)]))
    var elemType = LLVMNullType()
    let structElementCount = unsafe { LLVMCountStructElementTypes(arrayType) }
    CJC_ASSERT(structElementCount > 1u32)
    try (elementTypes = LibC.malloc<LLVMTypeRef>(count: Int64(structElementCount)).asResource()) {
        unsafe { LLVMGetStructElementTypes(arrayType, elementTypes.value) }
        elemType = unsafe { LLVMGetElementType((elementTypes.value + 1).read()) }
    }
    let elemPtr = irBuilder.CreateGEP(elemType, dataPtr, ArrayList<LLVMValueRef>([index]))
    let elemKind = unsafe { LLVMGetTypeKind(elemType) }
    if (elemKind == LLVM_STRUCT_TYPE_KIND) {
        let size = irBuilder.GetInt64(Int64(irBuilder.GetCGModule().GetTypeSize(elemType)))
        if (irBuilder.IsLLVMTypeContainsRef(elemType)) {
            irBuilder.CallGCWriteAgg(elemType, ArrayList<LLVMValueRef>([arrPtr, elemPtr, value, size]))
        } else {
            let align = irBuilder.GetCGModule().GetABITypeAlignment(elemType)
            irBuilder.CreateMemCpy(elemPtr, align, value, align, size)
        }
    } else if (elemKind == LLVM_ARRAY_TYPE_KIND) {
        let size = irBuilder.GetInt64(Int64(irBuilder.GetCGModule().GetTypeSize(elemType)))
        irBuilder.CallGCWriteAgg(arrayType, ArrayList<LLVMValueRef>([arrPtr, elemPtr, value, size]))
    } else if (elemType.toUIntNative() == CGType.GetRefType(irBuilder.GetLLVMContext()).toUIntNative()) {
        irBuilder.CallGCWrite(value, arrPtr, elemPtr)
    } else {
        irBuilder.CreateStore(value, elemPtr)
    }
    let incremented = irBuilder.CreateBinary(ExprKind.ADD, index, irBuilder.GetInt64(1))
    irBuilder.CreateStore(incremented, iterator)
    let cmpResult = irBuilder.CreateICmp(LLVMIntPredicate.SLT, incremented, arrayLen, name: "iterator.size.cmp")
    irBuilder.CreateCondBr(cmpResult, bodyBB, endBB)
    irBuilder.SetInsertPoint(endBB)
}

// Mirrors CodeGen/IRBuilder.h:267-286 IRBuilder2::CodeGenFieldInfo.
public class CodeGenFieldInfo {
    public var className: String
    public var qualifiedName: String
    public var fieldName: String
    public var fieldChirType: Option<Type>
    public var fieldType: Option<CGType>
    public var instance: LLVMValueRef
    public let baseTy: Type

    public init(className: String, qualifiedName: String, fieldName: String, fieldChirType: Option<Type>,
        fieldType: Option<CGType>, instance: LLVMValueRef, baseTy: Type) {
        this.className = className
        this.qualifiedName = qualifiedName
        this.fieldName = fieldName
        this.fieldChirType = fieldChirType
        this.fieldType = fieldType
        this.instance = instance
        this.baseTy = baseTy
    }
}

public class IRBuilder2 <: Resource {
    private let cgMod: CGModule
    private let builder: LLVMBuilderHandle
    private var chirExpr: Option<CHIRExprWrapper> = None
    private var cgFunction: Option<CGFunction> = None
    private let basePtrs: HashMap<UIntNative, LLVMValueRef> = HashMap<UIntNative, LLVMValueRef>()
    private var closed: Bool = false

    public init(cgMod: CGModule) {
        this.cgMod = cgMod
        builder = LLVMBuilderHandle.Create(cgMod.GetLLVMContext())
    }

    public init(cgMod: CGModule, theBB: LLVMBasicBlockRef) {
        this.cgMod = cgMod
        builder = LLVMBuilderHandle.Create(cgMod.GetLLVMContext())
        unsafe { LLVMPositionBuilderAtEnd(builder.raw, theBB) }
    }

    public func SetCHIRExpr(chirExprWrapper: CHIRExprWrapper): Unit {
        chirExpr = chirExprWrapper
        if (let Some(topLevelFunc) <- chirExprWrapper.GetTopLevelFunc()) {
            cgFunction = cgMod.GetOrInsertCGFunction(topLevelFunc)
        }
    }

    public func EmitLocation(debugNode: CHIRExprWrapper, removable!: Bool = false): Unit {
        if (!cgMod.GetCGContext().IsLineInfoEnabled()) {
            return
        }
        if (let Some(diBuilder) <- cgMod.GetDIBuilder()) {
            let diLoc = diBuilder.CreateDILoc(debugNode, removable: removable)
            unsafe { LLVMSetCurrentDebugLocation2(builder.raw, diLoc) }
        }
    }

    public func SetInsertCGFunction(cgFunc: CGFunction): Unit {
        cgFunction = cgFunc
    }

    public func GetInsertCGFunction(): Option<CGFunction> { return cgFunction }
    public func GetCGModule(): CGModule { return cgMod }
    public func GetCGContext(): CGContext { return cgMod.GetCGContext() }
    public func GetLLVMContext(): LLVMContextHandle { return cgMod.GetLLVMContext() }
    public func GetBuilder(): LLVMBuilderHandle { return builder }

    public func CheckNoHeapAlloc(operation: String): Unit {
        let currentFunction = cgFunction ?? return
        let chirFunction = (currentFunction.GetOriginal() as Function) ?? return
        var currentExpression: Option<Expression> = None
        if (let Some(exprWrapper) <- chirExpr) {
            currentExpression = Some(exprWrapper.GetExpression())
        }
        GetCGContext().GetCGPkgContext().GetNoHeapAllocChecker().CheckFunction(
            chirFunction, currentExpression, operation)
    }

    public func CheckNoWriteBarrierRec(): Unit {
        let currentFunction = cgFunction ?? return
        let chirFunction = (currentFunction.GetOriginal() as Function) ?? return
        var currentExpression: Option<Expression> = None
        if (let Some(exprWrapper) <- chirExpr) {
            currentExpression = Some(exprWrapper.GetExpression())
        }
        GetCGContext().GetCGPkgContext().GetNoWriteBarrierRecChecker().CheckFunction(
            chirFunction, currentExpression)
    }

    public func GetPtrSize(): UInt64 {
        return if (GetCGContext().GetCompileOptions().target.arch == ArchType.ARM32) { 4u64 } else { 8u64 }
    }

    public func GetSizetLLVMType(): LLVMTypeRef {
        return if (GetCGContext().GetCompileOptions().target.arch == ArchType.ARM32) {
            unsafe { LLVMInt32TypeInContext(GetLLVMContext().raw) }
        } else {
            unsafe { LLVMInt64TypeInContext(GetLLVMContext().raw) }
        }
    }

    public func GetTypeKindFromType(ty: Type): TypeKind {
        var typeKind = ty.GetTypeKind()
        let isArm32 = GetCGContext().GetCompileOptions().target.arch == ArchType.ARM32
        if (typeKind == TypeKind.TYPE_UINT_NATIVE) {
            typeKind = if (isArm32) { TypeKind.TYPE_UINT32 } else { TypeKind.TYPE_UINT64 }
        } else if (typeKind == TypeKind.TYPE_INT_NATIVE) {
            typeKind = if (isArm32) { TypeKind.TYPE_INT32 } else { TypeKind.TYPE_INT64 }
        }
        return typeKind
    }

    public func GetPayloadOffset(): UInt64 {
        return if (GetCGContext().GetCompileOptions().target.arch == ArchType.ARM32) {
            GetPtrSize() + 4u64
        } else {
            GetPtrSize()
        }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        builder.close()
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }

    public func GetTrue(): LLVMValueRef {
        return unsafe { LLVMConstInt(LLVMInt1TypeInContext(GetLLVMContext().raw), 1u64, 0) }
    }

    public func GetFalse(): LLVMValueRef {
        return unsafe { LLVMConstInt(LLVMInt1TypeInContext(GetLLVMContext().raw), 0u64, 0) }
    }

    public func GetInt32(value: Int64): LLVMValueRef {
        return unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), SignedInt64Bits(value), 1) }
    }

    public func GetInt64(value: Int64): LLVMValueRef {
        return unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), SignedInt64Bits(value), 1) }
    }

    public func CreateEntryAlloca(valueType: LLVMTypeRef, name!: String = ""): LLVMValueRef {
        CJC_ASSERT(!valueType.isNull())
        let currentBlock = unsafe { LLVMGetInsertBlock(builder.raw) }
        CJC_ASSERT(!currentBlock.isNull())
        let currentInsertPoint = unsafe { LLVMSelfhostGetInsertPointInstruction(builder.raw) }
        let currentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
        CJC_ASSERT(!currentFunction.isNull())
        let currentLocation = unsafe { LLVMGetCurrentDebugLocation2(builder.raw) }
        SetInsertPointToAllocas(currentFunction)
        let result = CreateAllocaAtCurrentPoint(valueType, name)
        RestoreInsertPoint(currentBlock, currentInsertPoint)
        unsafe { LLVMSetCurrentDebugLocation2(builder.raw, currentLocation) }
        return result
    }

    private func CreateAllocaAtCurrentPoint(valueType: LLVMTypeRef, name: String): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildAlloca(builder.raw, valueType, nameCString.value) }
        }
        return result
    }

    public func CreateEntryAlloca(cgType: CGType, name!: String = ""): LLVMValueRef {
        if (cgType.GetSize().isSome()) {
            let allocatedType = if (let Some(functionCGType) <- (cgType as CGFunctionType)) {
                unsafe { LLVMPointerType(functionCGType.GetLLVMFunctionType(), 0u32) }
            } else {
                cgType.GetLLVMType()
            }
            let allocaInst = CreateEntryAlloca(allocatedType, name: name)
            let options = cgMod.GetCGContext().GetCompileOptions()
            let isOptionLikeNonRef = if (let Some(enumCGType) <- (cgType as CGEnumType)) {
                enumCGType.IsOptionLikeNonRef()
            } else {
                false
            }
            let isAllAssociatedValuesAreNonRef = if (let Some(enumCGType) <- (cgType as CGEnumType)) {
                enumCGType.IsAllAssociatedValuesAreNonRef()
            } else {
                false
            }
            if ((unsafe { LLVMGetTypeKind(allocatedType) } == LLVM_STRUCT_TYPE_KIND && options.enableCompileDebug &&
                options.optimizationLevel == OptimizationLevel.O0) || (options.cjdbMode && isOptionLikeNonRef)) {
                CreateMemsetStructWith0(allocaInst)
            }
            let target = GetCGContext().GetCompileOptions().target
            if (target.arch == ArchType.ARM32 && target.env == EnvironmentType.ANDROID &&
                isAllAssociatedValuesAreNonRef) {
                unsafe { LLVMSetAlignment(allocaInst, MIN_ANDROID_ARM32_ENUM_ALIGN) }
            }
            return allocaInst
        }

        if (cgType.GetOriginal().IsGeneric()) {
            let refType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 1u32) }
            return CreateEntryAlloca(refType, name: name)
        }

        let typeInfoValue = CreateTypeInfo(cgType.GetOriginal())
        let size = GetLayoutSize32(cgType.GetOriginal(), cgType)
        var allocaInst = LLVMNullValue()
        try (debugLocGuard = TemporarilySetDebugLocInThisScope(this, LLVMNullMetadata())) {
            allocaInst = CallAllocaGenericWithTypeInfoAndSize(cgType.GetOriginal(), typeInfoValue, size)
        }
        return allocaInst
    }

    public func CreateAnonymousStructType(elementTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        if (elementTypes.isEmpty()) {
            return unsafe { LLVMStructTypeInContext(GetLLVMContext().raw, CPointer<LLVMTypeRef>(), 0u32, 0) }
        }
        var result = LLVMNullType()
        try (typePtr = LibC.malloc<LLVMTypeRef>(count: elementTypes.size).asResource()) {
            var idx: Int64 = 0
            while (idx < elementTypes.size) {
                unsafe { (typePtr.value + idx).write(elementTypes[idx]) }
                idx++
            }
            result = unsafe {
                LLVMStructTypeInContext(GetLLVMContext().raw, typePtr.value, UInt32(elementTypes.size), 0)
            }
        }
        return result
    }

    public func CreateLoad(elementType: LLVMTypeRef, addr: LLVMValueRef, name!: String = ""): LLVMValueRef {
        let buildLoad = { rawElementType: LLVMTypeRef, rawAddr: LLVMValueRef, rawName: String =>
            var loadResult = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(rawName) }.asResource()) {
                loadResult = unsafe { LLVMBuildLoad2(builder.raw, rawElementType, rawAddr, nameCString.value) }
            }
            loadResult
        }
        if (IsGlobalVariableBasePtr(addr) && IsLLVMTypeContainsRef(elementType)) {
            if (unsafe { LLVMGetTypeKind(elementType) } == LLVM_STRUCT_TYPE_KIND) {
                let tempVal = CreateEntryAlloca(elementType)
                let size = unsafe {
                    LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), cgMod.GetTypeSize(elementType), 0)
                }
                CallGCReadStaticAgg(elementType, ArrayList<LLVMValueRef>([tempVal, addr, size]))
                return tempVal
            }
            return CallGCReadStaticRef(addr)
        }
        if (unsafe { LLVMGetTypeKind(elementType) } == LLVM_STRUCT_TYPE_KIND) {
            let structName = LLVMCStringToString(unsafe { LLVMGetStructName(elementType) }) ?? ""
            if (structName == UNIT_TYPE_STR) {
                return cgMod.GenerateUnitTypeValue()
            }
            let tempVal = CreateEntryAlloca(elementType)
            let sizeInBytes = cgMod.GetTypeSize(elementType)
            let size = unsafe {
                LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), sizeInBytes, 0)
            }
            if (let Some(baseObject) <- GetTrackedManagedBase(addr)) {
                if (IsLLVMTypeContainsRef(elementType)) {
                    CallGCReadAgg(elementType, ArrayList<LLVMValueRef>([tempVal, baseObject, addr, size]))
                    return tempVal
                }
            }
            if (sizeInBytes != 0u64) {
                let align = cgMod.GetABITypeAlignment(elementType)
                CreateMemCpy(tempVal, align, addr, align, size)
            }
            return tempVal
        }
        if (unsafe { LLVMGetTypeKind(elementType) } == LLVM_ARRAY_TYPE_KIND) {
            let tempVal = CreateEntryAlloca(elementType)
            let size = unsafe {
                LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), cgMod.GetTypeSize(elementType), 0)
            }
            let align = cgMod.GetABITypeAlignment(elementType)
            CreateMemCpy(tempVal, align, addr, align, size)
            return tempVal
        }
        if (unsafe { LLVMGetTypeKind(elementType) } == LLVM_FUNCTION_TYPE_KIND) {
            return addr
        }
        if (let Some(currentExpr) <- chirExpr) {
            let expr = currentExpr.GetExpression()
            let exprKind = expr.GetExprKind()
            if (exprKind == ExprKind.INTRINSIC || exprKind == ExprKind.LOAD || exprKind == ExprKind.FIELD) {
                let elemCHIRType = expr.GetResult().getOrThrow().GetType().getOrThrow()
                let baseElemTy = DeRef(elemCHIRType)
                if (baseElemTy.IsGeneric()) {
                    if (IsLoadExprForAllocatedGenericRef(expr)) {
                        return buildLoad(elementType, addr, name)
                    }
                    let blocks = CreateAndInsertBasicBlocks(ArrayList<String>(
                        ["handle_load_ref", "handle_load_non_ref", "load_exit"]))
                    if (blocks.size == 3) {
                        let typeInfo = CreateTypeInfo(baseElemTy)
                        CreateCondBr(CreateTypeInfoIsReferenceCall(baseElemTy), blocks[0], blocks[1])
                        SetInsertPoint(blocks[0])
                        let refVal = if (let Some(baseObject) <- GetTrackedManagedBase(addr)) {
                            CallGCRead(ArrayList<LLVMValueRef>([baseObject, addr]))
                        } else {
                            let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 1u32) }
                            let addrSpace = GetPointerAddressSpace(addr) ?? 0u32
                            let addrFixedType = unsafe { LLVMPointerType(i8PtrTy, addrSpace) }
                            let castedAddr = CreateBitCast(addr, addrFixedType)
                            buildLoad(i8PtrTy, castedAddr, "")
                        }
                        CreateBr(blocks[2])
                        SetInsertPoint(blocks[1])
                        let typeInfoSize = GetLayoutSize_32(baseElemTy)
                        let valueVal = CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>([typeInfo, typeInfoSize]))
                        if (let Some(baseObject) <- GetTrackedManagedBase(addr)) {
                            CallGCReadGeneric(valueVal, baseObject, addr, typeInfoSize)
                        } else {
                            let addrType = unsafe { LLVMTypeOf(addr) }
                            let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
                            if (addrType.toUIntNative() == i8PtrTy.toUIntNative()) {
                                CallGCWriteGenericPayload(valueVal, addr, typeInfoSize)
                            } else {
                                let i8PtrTy1 = unsafe {
                                    LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 1u32)
                                }
                                CallIntrinsicAssignGeneric(ArrayList<LLVMValueRef>(
                                    [valueVal, buildLoad(i8PtrTy1, addr, ""), typeInfo]))
                            }
                        }
                        CreateBr(blocks[2])
                        SetInsertPoint(blocks[2])
                        let phi = CreatePHI(elementType)
                        AddIncoming(phi, ArrayList<LLVMValueRef>([refVal, valueVal]),
                            ArrayList<LLVMBasicBlockRef>([blocks[0], blocks[1]]))
                        return phi
                    }
                } else if (CGType.GetOrCreate(cgMod, elemCHIRType).GetSize().isNone()) {
                    let typeInfoOfElement = CreateTypeInfo(elemCHIRType)
                    let typeInfoSize = GetSizeFromTypeInfo(typeInfoOfElement)
                    let valueVal = CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>(
                        [typeInfoOfElement, typeInfoSize]))
                    if (let Some(baseObject) <- GetTrackedManagedBase(addr)) {
                        CallGCReadGeneric(valueVal, baseObject, addr, typeInfoSize)
                    } else {
                        let addrType = unsafe { LLVMTypeOf(addr) }
                        let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
                        if (addrType.toUIntNative() == i8PtrTy.toUIntNative()) {
                            CallGCWriteGenericPayload(valueVal, addr, typeInfoSize)
                        } else {
                            let i8PtrTy1 = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 1u32) }
                            CallIntrinsicAssignGeneric(ArrayList<LLVMValueRef>(
                                [valueVal, buildLoad(i8PtrTy1, addr, ""), typeInfoOfElement]))
                        }
                    }
                    return valueVal
                }
            }
        }
        if (let Some(baseObject) <- GetTrackedManagedBase(addr)) {
            if (elementType.toUIntNative() == CGType.GetRefType(GetLLVMContext()).toUIntNative()) {
                return CallGCRead(ArrayList<LLVMValueRef>([baseObject, addr]))
            }
        }
        return buildLoad(elementType, addr, name)
    }

    public func CreateLoad(cgVal: CGValue, name!: String = ""): LLVMValueRef {
        let pointerCGType = cgVal.GetCGType().getOrThrow()
        let elementCGType = pointerCGType.GetPointerElementType().getOrThrow()
        let elementType = elementCGType.GetLLVMType()
        let originalType = elementCGType.GetOriginal()
        if (elementCGType.GetSize().isNone() && !originalType.IsGeneric()) {
            let typeInfo = CreateTypeInfo(originalType)
            let payloadSize = GetLayoutSize32(originalType, elementCGType)
            let tempVal = CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>([typeInfo, payloadSize]))
            let basePtr = GetTrackedManagedBase(cgVal.GetRawValue())
            let addrSpace = GetPointerAddressSpace(cgVal.GetRawValue()) ?? 0u32
            if (basePtr.isNone()) {
                if (addrSpace == 1u32) {
                    CallIntrinsicAssignGeneric(ArrayList<LLVMValueRef>([tempVal, cgVal.GetRawValue(), typeInfo]))
                } else {
                    CallGCWriteGenericPayload(tempVal, cgVal.GetRawValue(), payloadSize)
                }
            } else {
                CJC_ASSERT(addrSpace == 1u32)
                CallGCReadGeneric(tempVal, basePtr.getOrThrow(), cgVal.GetRawValue(), payloadSize)
            }
            return tempVal
        }
        let loaded = CreateLoad(elementType, cgVal.GetRawValue(), name: name)
        if (originalType.IsEnum()) {
            LLVMSetInstructionMetadata(GetLLVMContext(), loaded, "untrusted_ref",
                LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>()))
        }
        return loaded
    }

    public func CreateStore(value: LLVMValueRef, addr: LLVMValueRef, isVolatile!: Bool = false): LLVMValueRef {
        let store = unsafe { LLVMBuildStore(builder.raw, value, addr) }
        if (isVolatile) {
            unsafe { LLVMSetVolatile(store, 1) }
        }
        return store
    }

    public func CreateStore(value: LLVMValueRef, dest: CGValue): LLVMValueRef {
        return CreateStore(value, dest.GetRawValue())
    }

    public func CreateStore(value: CGValue, dest: CGValue): LLVMValueRef {
        return CreateTypedStoreForAddress(this, value, dest)
    }

    public func CreateStore(value: LLVMValueRef, dest: LLVMValueRef, elementType: Type): LLVMValueRef {
        let refType = GetCGContext().GetCHIRBuilder().context.GetRefTy(elementType)
        let refCGType = CGType.GetOrCreate(cgMod, refType)
        return CreateStore(CGValue(value, refCGType), CGValue(dest, refCGType))
    }

    public func CreateStore(value: CGValue, dest: CGValue, elementType: Type): LLVMValueRef {
        return CreateTypedStoreForAddress(this, value, dest, boxType: Some(elementType))
    }

    public func IsGlobalVariableBasePtr(value: LLVMValueRef): Bool {
        return !unsafe { LLVMIsAGlobalVariable(LLVMSelfhostStripInBoundsOffsets(value)) }.isNull()
    }

    public func TryCreateGenericStore(value: CGValue, dest: CGValue, boxType!: Option<Type> = None): Option<LLVMValueRef> {
        let valueCGType = value.GetCGType() ?? return None
        let destCGType = dest.GetCGType() ?? return None
        let destElementCGType = destCGType.GetPointerElementType() ?? return None
        if (!(valueCGType.GetOriginal().IsGeneric() && valueCGType.GetSize().isNone() &&
            destElementCGType.GetOriginal().IsGeneric() && destElementCGType.GetSize().isNone())) {
            return None
        }

        let rawValue = value.GetRawValue()
        let rawDest = dest.GetRawValue()
        if (GetTrackedBasePtr(rawDest).isSome()) {
            return None
        }
        let destTy = destElementCGType.GetOriginal()
        let typeInfoTy = boxType ?? destTy
        let typeInfo = CreateTypeInfo(typeInfoTy)
        let managedBase = GetTrackedManagedBase(rawDest)
        let i8PtrTy1 = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 1u32) }
        let rawDestType = unsafe { LLVMTypeOf(rawDest) }
        let rawDestAddrSpace = if (!rawDestType.isNull() && unsafe { LLVMGetTypeKind(rawDestType) } == LLVM_POINTER_TYPE_KIND) {
            unsafe { LLVMGetPointerAddressSpace(rawDestType) }
        } else {
            0u32
        }
        let genericDest = CreateBitCast(rawDest, unsafe { LLVMPointerType(i8PtrTy1, rawDestAddrSpace) },
            name: "generic.store.dest")
        let genericSize = if (managedBase.isSome()) { GetSize32(typeInfoTy, valueCGType) } else { LLVMNullValue() }
        let blockNames = ArrayList<String>()
        blockNames.add("handle_store_ref")
        blockNames.add("handle_store_non_ref")
        blockNames.add("store_exit")
        let blocks = CreateAndInsertBasicBlocks(blockNames)
        if (blocks.size < 3) {
            return Some(LLVMNullValue())
        }
        let baseTypeInfoTy = typeInfoTy.StripAllRefs()
        if (baseTypeInfoTy.IsGeneric()) {
            CreateCondBr(CreateTypeInfoIsReferenceCall(typeInfoTy), blocks[0], blocks[1])
        } else if (CGType.GetOrCreate(cgMod, baseTypeInfoTy).IsReference()) {
            CreateBr(blocks[0])
        } else {
            CreateBr(blocks[1])
        }

        SetInsertPoint(blocks[0])
        if (let Some(baseObject) <- managedBase) {
            CallGCWrite(rawValue, baseObject, rawDest)
        } else {
            CreateStore(rawValue, genericDest)
        }
        CreateBr(blocks[2])

        SetInsertPoint(blocks[1])
        if (let Some(baseObject) <- managedBase) {
            CallGCWriteGeneric(baseObject, rawDest, rawValue, genericSize)
        } else {
            let destStorage = if (dest.IsSRetArg() && IsLLVMArgument(rawDest)) {
                CreateLoad(destElementCGType.GetLLVMType(), rawDest, name: "generic.store.sret")
            } else {
                let tmp = CallAllocaGenericWithTypeInfo(typeInfoTy, typeInfo)
                CreateStore(tmp, genericDest)
                tmp
            }
            CallAssignGeneric(destStorage, rawValue, typeInfo)
        }
        CreateBr(blocks[2])

        SetInsertPoint(blocks[2])
        return Some(LLVMNullValue())
    }

    public func StoreGenericMemberValue(baseObject: LLVMValueRef, dest: LLVMValueRef, value: CGValue,
        baseTy: Type, fieldTy: Option<Type>): LLVMValueRef {
        let valueCGType = value.GetCGType() ?? return LLVMNullValue()
        let valueTy = valueCGType.GetOriginal().StripAllRefs()
        let rawValue = value.GetRawValue()
        let typeInfo = GetGenericFieldTypeInfo(baseTy, fieldTy) ?? CreateTypeInfo(valueTy)
        let source = if (valueCGType.GetSize().isSome() && !valueCGType.IsReference()) {
            let tmp = CallAllocaGenericWithTypeInfo(valueTy, typeInfo)
            StoreValueToObjectPayload(tmp, rawValue, valueTy)
            tmp
        } else {
            rawValue
        }
        let blockNames = ArrayList<String>()
        blockNames.add("gcwrite_ref")
        blockNames.add("gcwrite_non_ref")
        blockNames.add("gcwrite_exit")
        let blocks = CreateAndInsertBasicBlocks(blockNames)
        if (blocks.size < 3) {
            return LLVMNullValue()
        }
        CreateCondBr(CreateTypeInfoIsReferenceCall(typeInfo), blocks[0], blocks[1])

        SetInsertPoint(blocks[0])
        CallGCWrite(source, baseObject, dest)
        CreateBr(blocks[2])

        SetInsertPoint(blocks[1])
        CallGCWriteGeneric(baseObject, dest, source, GetSize32(valueTy, valueCGType))
        CreateBr(blocks[2])

        SetInsertPoint(blocks[2])
        return LLVMNullValue()
    }

    public func LoadGenericFieldValue(baseObject: LLVMValueRef, source: LLVMValueRef, elementType: CGType,
        baseTy: Type, fieldTy: Option<Type>): LLVMValueRef {
        let valueTy = elementType.GetOriginal().StripAllRefs()
        let typeInfo = GetGenericFieldTypeInfo(baseTy, fieldTy) ?? CreateTypeInfo(valueTy)
        let blockNames = ArrayList<String>()
        blockNames.add("handle_load_ref")
        blockNames.add("handle_load_non_ref")
        blockNames.add("load_exit")
        let blocks = CreateAndInsertBasicBlocks(blockNames)
        if (blocks.size < 3) {
            return LLVMNullValue()
        }
        CreateCondBr(CreateTypeInfoIsReferenceCall(typeInfo), blocks[0], blocks[1])

        SetInsertPoint(blocks[0])
        let refValue = CallGCReadRef(baseObject, source)
        CreateBr(blocks[2])

        SetInsertPoint(blocks[1])
        let size = GetLayoutSize32ForAllocaGeneric(elementType, typeInfo)
        let value = CallAllocaGenericWithTypeInfoAndSize(valueTy, typeInfo, size)
        CallGCReadGeneric(value, baseObject, source, size)
        CreateBr(blocks[2])

        SetInsertPoint(blocks[2])
        let phi = CreatePHI(elementType.GetLLVMType(), name: "load.generic")
        let values = ArrayList<LLVMValueRef>()
        values.add(refValue)
        values.add(value)
        let incomingBlocks = ArrayList<LLVMBasicBlockRef>()
        incomingBlocks.add(blocks[0])
        incomingBlocks.add(blocks[1])
        AddIncoming(phi, values, incomingBlocks)
        return phi
    }

    private func GetGenericFieldTypeInfo(baseTy: Type, fieldTy: Option<Type>): Option<LLVMValueRef> {
        let genericFieldTy = (fieldTy ?? return None).StripAllRefs()
        if (!genericFieldTy.IsGeneric()) {
            return None
        }
        let customTy = (baseTy.StripAllRefs() as CustomType) ?? return None
        var idx: Int64 = 0
        for (arg in customTy.GetGenericArgs()) {
            if (arg.StripAllRefs().IsEqual(genericFieldTy)) {
                return Some(GetTypeInfoFromTypeInfoArgs(CreateTypeInfo(customTy), idx))
            }
            idx++
        }
        return None
    }

    private func IsLLVMArgument(value: LLVMValueRef): Bool {
        return !value.isNull() && !unsafe { LLVMIsAArgument(value) }.isNull()
    }

    private func TrackBasePtr(value: LLVMValueRef, baseObject: LLVMValueRef): Unit {
        if (value.isNull()) {
            return
        }
        basePtrs[value.toUIntNative()] = baseObject
        GetCGContext().SetBasePtr(value, baseObject)
    }

    public func GetTrackedBasePtr(value: LLVMValueRef): Option<LLVMValueRef> {
        if (value.isNull()) {
            return None
        }
        if (let Some(basePtr) <- GetCGContext().GetBasePtrOf(value)) {
            return basePtr
        }
        let key = value.toUIntNative()
        if (basePtrs.contains(key)) {
            return basePtrs[key]
        }
        return None
    }

    private func GetPointerAddressSpace(value: LLVMValueRef): Option<UInt32> {
        let valueType = unsafe { LLVMTypeOf(value) }
        if (valueType.isNull() || unsafe { LLVMGetTypeKind(valueType) } != 12) {
            return None
        }
        return Some(unsafe { LLVMGetPointerAddressSpace(valueType) })
    }

    public func GetTrackedManagedBase(value: LLVMValueRef): Option<LLVMValueRef> {
        let baseObject = GetTrackedBasePtr(value) ?? return None
        if ((GetPointerAddressSpace(baseObject) ?? 0u32) == 1u32) {
            return Some(baseObject)
        }
        return None
    }

    public func TryCreateManagedMemberStore(value: CGValue, dest: CGValue): Option<LLVMValueRef> {
        let baseObject = GetTrackedManagedBase(dest.GetRawValue()) ?? return None
        let valueCGType = value.GetCGType() ?? return None
        let destCGType = dest.GetCGType() ?? return None
        let destElementCGType = destCGType.GetPointerElementType() ?? return None
        if (destElementCGType.GetSize().isNone()) {
            return Some(StoreUnknownSizeManagedMemberValue(baseObject, dest.GetRawValue(), value, valueCGType,
                destElementCGType))
        }
        if (valueCGType.IsStructPtrType()) {
            return Some(StoreStructManagedMemberValue(baseObject, dest.GetRawValue(), value, valueCGType))
        }
        if (IsVArrayPtrValue(valueCGType) && destElementCGType.IsVArrayType()) {
            return Some(StoreVArrayManagedMemberValue(baseObject, dest.GetRawValue(), value, valueCGType))
        }
        if (valueCGType.IsReference() || IsOptionLikeRefValue(valueCGType)) {
            return Some(CallGCWriteRef(value.GetRawValue(), baseObject, dest.GetRawValue()))
        }
        return None
    }

    private func StoreUnknownSizeManagedMemberValue(baseObject: LLVMValueRef, dest: LLVMValueRef, value: CGValue,
        valueCGType: CGType, destElementCGType: CGType): LLVMValueRef {
        let destTy = destElementCGType.GetOriginal()
        let blockNames = ArrayList<String>()
        blockNames.add("gcwrite_ref")
        blockNames.add("gcwrite_non_ref")
        blockNames.add("gcwrite_exit")
        let blocks = CreateAndInsertBasicBlocks(blockNames)
        if (blocks.size < 3) {
            return LLVMNullValue()
        }
        let size = GetSize32(valueCGType.GetOriginal(), valueCGType)
        CreateCondBr(CreateTypeInfoIsReferenceCall(destTy), blocks[0], blocks[1])

        SetInsertPoint(blocks[0])
        CallGCWriteRef(value.GetRawValue(), baseObject, dest)
        CreateBr(blocks[2])

        SetInsertPoint(blocks[1])
        CallGCWriteGeneric(baseObject, dest, value.GetRawValue(), size)
        CreateBr(blocks[2])

        SetInsertPoint(blocks[2])
        return LLVMNullValue()
    }

    private func StoreStructManagedMemberValue(baseObject: LLVMValueRef, dest: LLVMValueRef, value: CGValue,
        valueCGType: CGType): LLVMValueRef {
        let structCGType = valueCGType.GetPointerElementType() ?? return CreateStore(value.GetRawValue(), dest)
        let structType = structCGType.GetLLVMType()
        let size = unsafe {
            LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), cgMod.GetTypeSize(structType), 0)
        }
        if (IsLLVMTypeContainsRef(structType)) {
            let source = ReadManagedAggregateSourceIfNeeded(value.GetRawValue(), structCGType, size)
            return CallGCWriteStruct(baseObject, dest, source, size, structCGType.GetOriginal().ToString())
        }
        let align = cgMod.GetABITypeAlignment(structType)
        return CreateMemCpy(dest, align, value.GetRawValue(), align, size)
    }

    private func StoreVArrayManagedMemberValue(baseObject: LLVMValueRef, dest: LLVMValueRef, value: CGValue,
        valueCGType: CGType): LLVMValueRef {
        let varrayCGType = valueCGType.GetPointerElementType() ?? return CreateStore(value.GetRawValue(), dest)
        let varrayType = varrayCGType.GetLLVMType()
        let size = unsafe {
            LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), cgMod.GetTypeSize(varrayType), 0)
        }
        if (IsLLVMTypeContainsRef(varrayType)) {
            return CallGCWriteStruct(baseObject, dest, value.GetRawValue(), size, varrayCGType.GetOriginal().ToString())
        }
        let align = cgMod.GetABITypeAlignment(varrayType)
        return CreateMemCpy(dest, align, value.GetRawValue(), align, size)
    }

    private func ReadManagedAggregateSourceIfNeeded(source: LLVMValueRef, sourceCGType: CGType,
        size: LLVMValueRef): LLVMValueRef {
        if ((GetPointerAddressSpace(source) ?? 0u32) != 1u32) {
            return source
        }
        let sourceBase = GetTrackedManagedBase(source) ?? source
        let temp = CreateEntryAlloca(sourceCGType.GetLLVMType(), name: "gcwrite.agg.tmp")
        CallGCReadStruct(temp, sourceBase, source, size, sourceCGType.GetOriginal().ToString())
        return temp
    }

    private func IsVArrayPtrValue(cgType: CGType): Bool {
        if (!cgType.IsPointerType()) {
            return false
        }
        let elementType = cgType.GetPointerElementType() ?? return false
        return elementType.IsVArrayType()
    }

    private func PropagateBasePtr(source: LLVMValueRef, result: LLVMValueRef): Unit {
        if (source.isNull() || result.isNull()) {
            return
        }
        if (let Some(baseObject) <- GetTrackedBasePtr(source)) {
            TrackBasePtr(result, baseObject)
            return
        }
        if ((GetPointerAddressSpace(source) ?? 0u32) == 1u32) {
            TrackBasePtr(result, source)
        }
    }

    public func CreateMemSet(pointer: LLVMValueRef, value: LLVMValueRef, len: LLVMValueRef,
        align!: UInt32 = 0u32): LLVMValueRef {
        return unsafe { LLVMBuildMemSet(builder.raw, pointer, value, len, align) }
    }

    public func CreateMemCpy(dest: LLVMValueRef, destAlign: UInt32, src: LLVMValueRef, srcAlign: UInt32,
        size: LLVMValueRef): LLVMValueRef {
        return unsafe { LLVMBuildMemCpy(builder.raw, dest, destAlign, src, srcAlign, size) }
    }

    public func CreateMemMove(dest: LLVMValueRef, destAlign: UInt32, src: LLVMValueRef, srcAlign: UInt32,
        size: LLVMValueRef): LLVMValueRef {
        return unsafe { LLVMBuildMemMove(builder.raw, dest, destAlign, src, srcAlign, size) }
    }

    public func CreateCJMemSetStructWith0(addr: LLVMValueRef): LLVMValueRef {
        let allocatedType = unsafe { LLVMGetAllocatedType(addr) }
        CJC_ASSERT(unsafe { LLVMGetTypeKind(allocatedType) } == LLVM_STRUCT_TYPE_KIND)
        let currentLocation = unsafe { LLVMGetCurrentDebugLocation2(builder.raw) }
        unsafe { LLVMSetCurrentDebugLocation2(builder.raw, LLVMNullMetadata()) }
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let pointerType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let dest = CreateBitCast(addr, pointerType, name: "cj.memset.addr")
        let overloadedTypes = ArrayList<LLVMTypeRef>()
        overloadedTypes.add(pointerType)
        let len = unsafe {
            LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), cgMod.GetTypeSize(allocatedType), 0)
        }
        let align = cgMod.GetABITypeAlignment(allocatedType)
        let memsetCall = CreateMemSet(dest, unsafe { LLVMConstInt(i8Type, 0u64, 0) }, len, align: align)
        let cjMemset = GetOrInsertIntrinsicDeclaration(CJ_MEMSET_INTRINSIC_NAME, overloadedTypes)
        let operandCount = unsafe { LLVMGetNumOperands(memsetCall) }
        if (!cjMemset.isNull() && operandCount > 0) {
            unsafe { LLVMSetOperand(memsetCall, UInt32(operandCount - 1), cjMemset) }
        }
        unsafe { LLVMSetCurrentDebugLocation2(builder.raw, currentLocation) }
        return memsetCall
    }

    public func CreateMemsetStructWith0(addr: LLVMValueRef, allocatedType: LLVMTypeRef): LLVMValueRef {
        let currentBlock = unsafe { LLVMGetInsertBlock(builder.raw) }
        CJC_ASSERT(!currentBlock.isNull())
        let currentInsertPoint = unsafe { LLVMSelfhostGetInsertPointInstruction(builder.raw) }
        let currentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
        CJC_ASSERT(!currentFunction.isNull())
        let currentLocation = unsafe { LLVMGetCurrentDebugLocation2(builder.raw) }
        SetInsertPointToAllocas(currentFunction)
        let entryBlock = unsafe { LLVMGetEntryBasicBlock(currentFunction) }
        let terminator = unsafe { LLVMGetBasicBlockTerminator(entryBlock) }
        CJC_ASSERT(!terminator.isNull())
        SetInsertPointBefore(terminator)

        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let pointerType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let dest = CreateBitCast(addr, pointerType, name: "memset.addr")
        let len = unsafe {
            LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), cgMod.GetTypeSize(allocatedType), 0)
        }
        let align = cgMod.GetABITypeAlignment(allocatedType)
        let result = CreateMemSet(dest, unsafe { LLVMConstInt(i8Type, 0u64, 0) }, len, align: align)

        RestoreInsertPoint(currentBlock, currentInsertPoint)
        unsafe { LLVMSetCurrentDebugLocation2(builder.raw, currentLocation) }
        return result
    }

    // Mirrors CodeGen/CJNative/CJNativeIRBuilder.cpp:899-921 IRBuilder2::CreateMemsetStructWith0.
    public func CreateMemsetStructWith0(addr: LLVMValueRef): LLVMValueRef {
        let allocatedType = unsafe { LLVMGetAllocatedType(addr) }
        CJC_ASSERT(unsafe { LLVMGetTypeKind(allocatedType) } == LLVM_STRUCT_TYPE_KIND)
        return CreateMemsetStructWith0(addr, allocatedType)
    }

    public func CreateBr(dest: LLVMBasicBlockRef): LLVMValueRef {
        return unsafe { LLVMBuildBr(builder.raw, dest) }
    }

    public func CreateCondBr(cond: LLVMValueRef, trueBranch: LLVMBasicBlockRef, falseBranch: LLVMBasicBlockRef): LLVMValueRef {
        return unsafe { LLVMBuildCondBr(builder.raw, cond, trueBranch, falseBranch) }
    }

    public func CreateSwitch(cond: LLVMValueRef, defaultDest: LLVMBasicBlockRef, caseCountHint: UInt32): LLVMValueRef {
        return unsafe { LLVMBuildSwitch(builder.raw, cond, defaultDest, caseCountHint) }
    }

    public func AddSwitchCase(switchValue: LLVMValueRef, caseValue: LLVMValueRef, dest: LLVMBasicBlockRef): Unit {
        unsafe { LLVMAddCase(switchValue, caseValue, dest) }
    }

    public func CreateICmp(predicate: LLVMIntPredicate, left: LLVMValueRef, right: LLVMValueRef,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(predicate), left, right, nameCString.value) }
        }
        return result
    }

    public func CreateAnd(left: LLVMValueRef, right: LLVMValueRef): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString("") }.asResource()) {
            result = unsafe { LLVMBuildAnd(builder.raw, left, right, nameCString.value) }
        }
        return result
    }

    public func CreateOr(left: LLVMValueRef, right: LLVMValueRef): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString("") }.asResource()) {
            result = unsafe { LLVMBuildOr(builder.raw, left, right, nameCString.value) }
        }
        return result
    }

    public func CreateFCmpOLT(left: LLVMValueRef, right: LLVMValueRef, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OLT), left, right,
                    nameCString.value)
            }
        }
        return result
    }

    public func CreateFCmpUNE(left: LLVMValueRef, right: LLVMValueRef, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.UNE), left, right,
                    nameCString.value)
            }
        }
        return result
    }

    public func CreateRetVoid(): LLVMValueRef {
        return unsafe { LLVMBuildRetVoid(builder.raw) }
    }

    public func CreateRet(value: LLVMValueRef): LLVMValueRef {
        return unsafe { LLVMBuildRet(builder.raw, value) }
    }

    public func CreateEntryBasicBlock(parent: LLVMValueRef, name: String): LLVMBasicBlockRef {
        return CreateEntryBasicBlockBeforeFirst(parent, name)
    }

    public func CreateBasicBlockAtEnd(parent: LLVMValueRef, name: String): LLVMBasicBlockRef {
        var result = LLVMNullBasicBlock()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMAppendBasicBlockInContext(GetLLVMContext().raw, parent, nameCString.value) }
        }
        return result
    }

    public func CreateEntryBasicBlockBeforeFirst(parent: LLVMValueRef, name: String): LLVMBasicBlockRef {
        var result = LLVMNullBasicBlock()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            let oldEntry = unsafe { LLVMGetFirstBasicBlock(parent) }
            if (oldEntry.isNull()) {
                result = unsafe { LLVMAppendBasicBlockInContext(GetLLVMContext().raw, parent, nameCString.value) }
            } else {
                result = unsafe { LLVMInsertBasicBlockInContext(GetLLVMContext().raw, oldEntry, nameCString.value) }
            }
        }
        return result
    }

    private func SetInsertPointToAllocas(currentFunction: LLVMValueRef): Unit {
        var entryBlock = unsafe { LLVMGetEntryBasicBlock(currentFunction) }
        if (!IsBasicBlockNamed(entryBlock, "allocas")) {
            let allocaBlock = CreateEntryBasicBlock(currentFunction, "allocas")
            SetInsertPoint(allocaBlock)
            let savedLocation = unsafe { LLVMGetCurrentDebugLocation2(builder.raw) }
            unsafe { LLVMSetCurrentDebugLocation2(builder.raw, LLVMNullMetadata()) }
            CreateBr(entryBlock)
            unsafe { LLVMSetCurrentDebugLocation2(builder.raw, savedLocation) }
            entryBlock = allocaBlock
        }
        let terminator = unsafe { LLVMGetBasicBlockTerminator(entryBlock) }
        CJC_ASSERT(!terminator.isNull())
        SetInsertPointBefore(terminator)
    }

    private func RestoreInsertPoint(block: LLVMBasicBlockRef, insertPoint: LLVMValueRef): Unit {
        if (insertPoint.isNull()) {
            unsafe { LLVMPositionBuilderAtEnd(builder.raw, block) }
        } else {
            unsafe { LLVMPositionBuilderBefore(builder.raw, insertPoint) }
        }
    }

    public func CreateAndInsertBasicBlock(name: String): LLVMBasicBlockRef {
        let currentBlock = GetInsertBlock()
        if (currentBlock.isNull()) {
            return LLVMNullBasicBlock()
        }
        let currentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
        if (currentFunction.isNull()) {
            return LLVMNullBasicBlock()
        }
        let inserted = CreateEntryBasicBlock(currentFunction, name)
        unsafe { LLVMMoveBasicBlockAfter(inserted, currentBlock) }
        return inserted
    }

    public func CreateAndInsertBasicBlocks(names: ArrayList<String>): ArrayList<LLVMBasicBlockRef> {
        let result = ArrayList<LLVMBasicBlockRef>()
        let currentBlock = GetInsertBlock()
        if (currentBlock.isNull()) {
            return result
        }
        let currentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
        if (currentFunction.isNull()) {
            return result
        }
        var insertAfter = currentBlock
        for (name in names) {
            let created = CreateEntryBasicBlock(currentFunction, name)
            unsafe { LLVMMoveBasicBlockAfter(created, insertAfter) }
            result.add(created)
            insertAfter = created
        }
        return result
    }

    public func SetInsertPoint(block: LLVMBasicBlockRef): Unit {
        if (block.isNull()) {
            ClearInsertionPoint()
            return
        }
        unsafe { LLVMPositionBuilderAtEnd(builder.raw, block) }
    }

    public func SetInsertPoint(block: LLVMBasicBlockRef, insertPoint: LLVMValueRef): Unit {
        RestoreInsertPoint(block, insertPoint)
    }

    public func GetInsertBlock(): LLVMBasicBlockRef {
        return unsafe { LLVMGetInsertBlock(builder.raw) }
    }

    public func GetInsertFunction(): LLVMValueRef {
        let block = GetInsertBlock()
        if (block.isNull()) {
            return LLVMNullValue()
        }
        return unsafe { LLVMGetBasicBlockParent(block) }
    }

    public func SetInsertPointBefore(inst: LLVMValueRef): Unit {
        if (inst.isNull()) {
            ClearInsertionPoint()
            return
        }
        unsafe { LLVMPositionBuilderBefore(builder.raw, inst) }
    }

    public func SetInsertPointForPreparingTypeInfo(): Unit {
        let currentBlock = GetInsertBlock()
        if (currentBlock.isNull()) {
            return
        }
        let currentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
        if (currentFunction.isNull()) {
            return
        }
        let firstBlock = unsafe { LLVMGetFirstBasicBlock(currentFunction) }
        if (firstBlock.isNull()) {
            return
        }
        let prepBlock = if (IsBasicBlockNamed(firstBlock, "prepTi")) {
            firstBlock
        } else if (IsBasicBlockNamed(firstBlock, "allocas")) {
            FindOrCreatePrepTiAfterAllocas(currentFunction, firstBlock)
        } else {
            let created = CreateEntryBasicBlock(currentFunction, "prepTi")
            SetInsertPoint(created)
            CreateBr(firstBlock)
            created
        }
        let terminator = unsafe { LLVMGetBasicBlockTerminator(prepBlock) }
        if (terminator.isNull()) {
            SetInsertPoint(prepBlock)
        } else {
            SetInsertPointBefore(terminator)
        }
    }

    public func ClearInsertionPoint(): Unit {
        unsafe { LLVMClearInsertionPosition(builder.raw) }
    }

    public func CreateBinary(kind: ExprKind, left: LLVMValueRef, right: LLVMValueRef, name!: String = ""): LLVMValueRef {
        return CreateBinaryTyped(kind, left, right, None, None, name: name)
    }

    public func CreateBinaryTyped(kind: ExprKind, left: LLVMValueRef, right: LLVMValueRef,
        operandType: Option<Type>, resultType: Option<Type>, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            let compareType = if (operandType.isSome()) { operandType } else { resultType }
            if (IsFloatOperand(compareType)) {
                result = match (kind) {
                    case ExprKind.ADD => unsafe { LLVMBuildFAdd(builder.raw, left, right, nameCString.value) }
                    case ExprKind.SUB => unsafe { LLVMBuildFSub(builder.raw, left, right, nameCString.value) }
                    case ExprKind.MUL => unsafe { LLVMBuildFMul(builder.raw, left, right, nameCString.value) }
                    case ExprKind.DIV => unsafe { LLVMBuildFDiv(builder.raw, left, right, nameCString.value) }
                    case ExprKind.MOD => unsafe { LLVMBuildFRem(builder.raw, left, right, nameCString.value) }
                    case ExprKind.EQUAL => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OEQ), left, right, nameCString.value) }
                    case ExprKind.NOTEQUAL => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.ONE), left, right, nameCString.value) }
                    case ExprKind.LT => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OLT), left, right, nameCString.value) }
                    case ExprKind.LE => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OLE), left, right, nameCString.value) }
                    case ExprKind.GT => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OGT), left, right, nameCString.value) }
                    case ExprKind.GE => unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OGE), left, right, nameCString.value) }
                    case _ => LLVMNullValue()
                }
            } else {
                result = match (kind) {
                    case ExprKind.ADD => unsafe { LLVMBuildAdd(builder.raw, left, right, nameCString.value) }
                    case ExprKind.SUB => unsafe { LLVMBuildSub(builder.raw, left, right, nameCString.value) }
                    case ExprKind.MUL => unsafe { LLVMBuildMul(builder.raw, left, right, nameCString.value) }
                    case ExprKind.DIV => if (IsUnsignedOperand(compareType)) {
                        unsafe { LLVMBuildUDiv(builder.raw, left, right, nameCString.value) }
                    } else {
                        unsafe { LLVMBuildSDiv(builder.raw, left, right, nameCString.value) }
                    }
                    case ExprKind.MOD => if (IsUnsignedOperand(compareType)) {
                        unsafe { LLVMBuildURem(builder.raw, left, right, nameCString.value) }
                    } else {
                        unsafe { LLVMBuildSRem(builder.raw, left, right, nameCString.value) }
                    }
                    case ExprKind.LSHIFT => unsafe { LLVMBuildShl(builder.raw, left, right, nameCString.value) }
                    case ExprKind.RSHIFT => if (IsUnsignedOperand(compareType)) {
                        unsafe { LLVMBuildLShr(builder.raw, left, right, nameCString.value) }
                    } else {
                        unsafe { LLVMBuildAShr(builder.raw, left, right, nameCString.value) }
                    }
                    case ExprKind.BITAND | ExprKind.AND => unsafe { LLVMBuildAnd(builder.raw, left, right, nameCString.value) }
                    case ExprKind.BITOR | ExprKind.OR => unsafe { LLVMBuildOr(builder.raw, left, right, nameCString.value) }
                    case ExprKind.BITXOR => unsafe { LLVMBuildXor(builder.raw, left, right, nameCString.value) }
                    case ExprKind.EQUAL => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(LLVMIntPredicate.EQ), left, right, nameCString.value) }
                    case ExprKind.NOTEQUAL => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(LLVMIntPredicate.NE), left, right, nameCString.value) }
                    case ExprKind.LT => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(SelectLessThanPredicate(compareType)), left, right, nameCString.value) }
                    case ExprKind.LE => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(SelectLessEqualPredicate(compareType)), left, right, nameCString.value) }
                    case ExprKind.GT => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(SelectGreaterThanPredicate(compareType)), left, right, nameCString.value) }
                    case ExprKind.GE => unsafe { LLVMBuildICmp(builder.raw, LLVMIntPredicateValue(SelectGreaterEqualPredicate(compareType)), left, right, nameCString.value) }
                    case _ => LLVMNullValue()
                }
            }
        }
        return ApplyFastMathIfNeeded(result)
    }

    public func CreateUnary(kind: ExprKind, value: LLVMValueRef, name!: String = ""): LLVMValueRef {
        return CreateUnaryTyped(kind, value, None, name: name)
    }

    public func CreateUnaryTyped(kind: ExprKind, value: LLVMValueRef, operandType: Option<Type>, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = match (kind) {
                case ExprKind.NEG => if (IsFloatOperand(operandType)) {
                    unsafe { LLVMBuildFNeg(builder.raw, value, nameCString.value) }
                } else {
                    unsafe { LLVMBuildNeg(builder.raw, value, nameCString.value) }
                }
                case ExprKind.NOT | ExprKind.BITNOT => unsafe { LLVMBuildNot(builder.raw, value, nameCString.value) }
                case _ => LLVMNullValue()
            }
        }
        return ApplyFastMathIfNeeded(result)
    }

    public func CreateNullValue(ty: Type): LLVMValueRef {
        let cgType = CGType.GetOrCreate(cgMod, ty)
        let llvmTy = cgType.GetLLVMType()
        if (GetInsertBlock().isNull()) {
            return unsafe { LLVMConstNull(llvmTy) }
        }
        if (cgType.GetSize().isNone()) {
            let typeInfo = CreateTypeInfo(ty)
            return CallAllocaGenericWithTypeInfoAndSize(ty, typeInfo, GetLayoutSize_32(ty))
        }
        if (ty.IsUnit()) {
            return cgMod.GenerateUnitTypeValue()
        }
        let llvmKind = unsafe { LLVMGetTypeKind(llvmTy) }
        if (llvmKind == LLVM_STRUCT_TYPE_KIND) {
            let allocaInst = CreateEntryAlloca(llvmTy)
            if (!IsLLVMTypeContainsRef(llvmTy)) {
                CreateMemsetStructWith0(allocaInst)
            }
            return allocaInst
        }
        if (llvmKind == LLVM_ARRAY_TYPE_KIND) {
            let allocaInst = CreateEntryAlloca(llvmTy)
            let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
            let sizeOf2G: UInt64 = 2147483647u64
            let typeSize = cgMod.GetTypeSize(llvmTy)
            var idx: UInt64 = 0u64
            while (idx + sizeOf2G < typeSize) {
                let dataPtr = CreateGEP(llvmTy, allocaInst,
                    ArrayList<LLVMValueRef>([GetInt64(0), unsafe {
                        LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), idx, 0)
                    }]))
                CreateMemSet(dataPtr, unsafe { LLVMConstInt(i8Type, 0u64, 0) },
                    unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), sizeOf2G, 0) }, align: 1u32)
                idx += sizeOf2G
            }
            let dataPtr = CreateGEP(llvmTy, allocaInst,
                ArrayList<LLVMValueRef>([GetInt64(0), unsafe {
                    LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), idx, 0)
                }]))
            CreateMemSet(dataPtr, unsafe { LLVMConstInt(i8Type, 0u64, 0) },
                unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), typeSize - idx, 0) }, align: 1u32)
            return allocaInst
        }
        return unsafe { LLVMConstNull(llvmTy) }
    }

    public func CreateLiteralValue(literal: LiteralValue, resultType: Type): LLVMValueRef {
        if (literal.IsUnitLit()) {
            return cgMod.GenerateUnitTypeValue()
        }
        if (literal.IsNullLit()) {
            return CreateNullValue(resultType)
        }
        if (let Some(boolLiteral) <- (literal as BoolLiteral)) {
            return if (boolLiteral.value) { GetTrue() } else { GetFalse() }
        }
        if (let Some(intLiteral) <- (literal as IntLiteral)) {
            let intTy = CGType.GetOrCreate(cgMod, resultType).GetLLVMType()
            return unsafe { LLVMConstInt(intTy, SignedInt64Bits(intLiteral.value), 1) }
        }
        if (let Some(floatLiteral) <- (literal as FloatLiteral)) {
            let floatTy = CGType.GetOrCreate(cgMod, resultType).GetLLVMType()
            return unsafe { LLVMConstReal(floatTy, floatLiteral.value) }
        }
        if (let Some(runeLiteral) <- (literal as RuneLiteral)) {
            let runeTy = CGType.GetOrCreate(cgMod, resultType).GetLLVMType()
            return unsafe { LLVMConstInt(runeTy, UInt64(UInt32(runeLiteral.value)), 0) }
        }
        if (let Some(stringLiteral) <- (literal as StringLiteral)) {
            return CreateStringLiteral(stringLiteral.value)
        }
        CJC_ABORT()
        return LLVMNullValue()
    }

    public func CreateDefaultLiteralValue(literal: LiteralValue): LLVMValueRef {
        if (let Some(boolLiteral) <- (literal as BoolLiteral)) {
            return if (boolLiteral.value) { GetTrue() } else { GetFalse() }
        }
        if (let Some(intLiteral) <- (literal as IntLiteral)) {
            return unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), SignedInt64Bits(intLiteral.value), 1) }
        }
        if (let Some(floatLiteral) <- (literal as FloatLiteral)) {
            return unsafe { LLVMConstReal(LLVMDoubleTypeInContext(GetLLVMContext().raw), floatLiteral.value) }
        }
        if (let Some(runeLiteral) <- (literal as RuneLiteral)) {
            return unsafe {
                LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), UInt64(UInt32(runeLiteral.value)), 0)
            }
        }
        if (let Some(stringLiteral) <- (literal as StringLiteral)) {
            return CreateStringLiteral(stringLiteral.value)
        }
        return unsafe { LLVMConstNull(LLVMInt8TypeInContext(GetLLVMContext().raw)) }
    }

    public func CreateCall(callee: LLVMValueRef, calleeType: LLVMTypeRef, args: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (args.isEmpty()) {
                result = unsafe {
                    LLVMSelfhostCreateCall(builder.raw, calleeType, callee, CPointer<LLVMValueRef>(), 0u32,
                        nameCString.value)
                }
            } else {
                try (argPtr = LibC.malloc<LLVMValueRef>(count: args.size).asResource()) {
                    var idx: Int64 = 0
                    while (idx < args.size) {
                        unsafe { (argPtr.value + idx).write(args[idx]) }
                        idx++
                    }
                    result = unsafe {
                        LLVMSelfhostCreateCall(builder.raw, calleeType, callee, argPtr.value, UInt32(args.size),
                            nameCString.value)
                    }
                }
            }
        }
        return result
    }

    public func CreateInvoke(callee: LLVMValueRef, calleeType: LLVMTypeRef, normalDest: LLVMBasicBlockRef,
        unwindDest: LLVMBasicBlockRef, args: ArrayList<LLVMValueRef>, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (args.isEmpty()) {
                result = unsafe {
                    LLVMBuildInvoke2(builder.raw, calleeType, callee, CPointer<LLVMValueRef>(), 0u32,
                        normalDest, unwindDest, nameCString.value)
                }
            } else {
                try (argPtr = LibC.malloc<LLVMValueRef>(count: args.size).asResource()) {
                    var idx: Int64 = 0
                    while (idx < args.size) {
                        unsafe { (argPtr.value + idx).write(args[idx]) }
                        idx++
                    }
                    result = unsafe {
                        LLVMBuildInvoke2(builder.raw, calleeType, callee, argPtr.value, UInt32(args.size),
                            normalDest, unwindDest, nameCString.value)
                    }
                }
            }
        }
        return result
    }

    public func CreateCallOrInvoke(callee: LLVMValueRef, calleeType: LLVMTypeRef, args: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        if (let Some(unwindBlock) <- GetCGContext().TopUnwindBlockStack()) {
            let currentBlock = unsafe { LLVMGetInsertBlock(builder.raw) }
            if (!currentBlock.isNull()) {
                let parentFunction = unsafe { LLVMGetBasicBlockParent(currentBlock) }
                if (!parentFunction.isNull()) {
                    let normalDest = CreateEntryBasicBlock(parentFunction, "normalDest")
                    unsafe { LLVMMoveBasicBlockAfter(normalDest, currentBlock) }
                    let invokeValue = CreateInvoke(callee, calleeType, normalDest, unwindBlock, args, name: name)
                    SetInsertPoint(normalDest)
                    return invokeValue
                }
            }
        }
        return CreateCall(callee, calleeType, args, name: name)
    }

    public func CreateCallOrInvoke(callee: LLVMValueRef, args: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        let callBase = CreateCallOrInvoke(callee, unsafe { LLVMGlobalGetValueType(callee) }, args, name: name)
        if (unsafe { LLVMSelfhostFunctionHasStructRetAttr(callee) } != 0) {
            AddNoAliasAttribute(callBase)
            AddSRetAttribute(callBase, GetTypeAttributeValueAtIndex(callee, 1u32, "sret").getOrThrow())
        }
        return callBase
    }

    public func CreateCallOrInvoke(calleeType: CGFunctionType, callee: LLVMValueRef, args: ArrayList<CGValue>,
        name!: String = ""): LLVMValueRef {
        return CreateCallOrInvokeWithMethodTypeInfo(calleeType, callee, args, None, name: name)
    }

    public func CreateCallOrInvokeWithMethodTypeInfo(calleeType: CGFunctionType, callee: LLVMValueRef,
        args: ArrayList<CGValue>, methodTypeInfoArg: Option<LLVMValueRef>, name!: String = ""): LLVMValueRef {
        return CreateCallOrInvokeWithMethodTypeInfo(calleeType, callee, args, methodTypeInfoArg,
            ArrayList<Type>(), name: name)
    }

    public func CreateCallOrInvokeWithMethodTypeInfo(calleeType: CGFunctionType, callee: LLVMValueRef,
        args: ArrayList<CGValue>, methodTypeInfoArg: Option<LLVMValueRef>, instTypeArgs: ArrayList<Type>,
        thisTypeInfoArg!: Option<LLVMValueRef> = None, name!: String = ""): LLVMValueRef {
        return CreateCallOrInvokeWithMethodTypeInfo(calleeType, callee, args, methodTypeInfoArg, instTypeArgs,
            None, thisTypeInfoArg, name: name)
    }

    public func CreateCallOrInvokeWithMethodTypeInfoAndSRetTypeInfo(calleeType: CGFunctionType, callee: LLVMValueRef,
        args: ArrayList<CGValue>, methodTypeInfoArg: Option<LLVMValueRef>, sretTypeInfoArg: Option<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        return CreateCallOrInvokeWithMethodTypeInfo(calleeType, callee, args, methodTypeInfoArg,
            ArrayList<Type>(), sretTypeInfoArg, None, name: name)
    }

    private func CreateCallOrInvokeWithMethodTypeInfo(calleeType: CGFunctionType, callee: LLVMValueRef,
        args: ArrayList<CGValue>, methodTypeInfoArg: Option<LLVMValueRef>, instTypeArgs: ArrayList<Type>,
        sretTypeInfoArg: Option<LLVMValueRef>, thisTypeInfoArg: Option<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        let callArgs = TransformFuncArgs(calleeType, args, methodTypeInfoArg, instTypeArgs, sretTypeInfoArg,
            thisTypeInfoArg, name: name)
        let llvmCallArgs = TransformLLVMCallArgs(calleeType, callArgs, name: name)
        CallSetLocation()
        if (let Some(funcType) <- (calleeType.GetOriginal() as FuncType)) {
            let retTy = funcType.GetReturnType()
            let callName = if (retTy.IsUnit() || retTy.IsNothing() || retTy.IsVoid() || calleeType.HasSRet()) {
                ""
            } else {
                name
            }
            let callBase = CreateCallOrInvoke(callee, calleeType.GetLLVMFunctionType(), llvmCallArgs, name: callName)
            if (!unsafe { LLVMIsAFunction(callee) }.isNull() &&
                HasAttributeAtIndex(callee, UInt32.Max, HAS_WITH_TI_WRAPPER_ATTR)) {
                let currentExpression = chirExpr.getOrThrow().GetExpression()
                var applyExprWrapper: Option<CHIRApplyWrapper> = None
                if (let Some(applyExpr) <- (currentExpression as Apply)) {
                    applyExprWrapper = Some(CHIRApplyWrapper(applyExpr))
                } else if (let Some(applyWithExceptionExpr) <- (currentExpression as ApplyWithException)) {
                    applyExprWrapper = Some(CHIRApplyWrapper(applyWithExceptionExpr))
                }
                let applyWrapper = applyExprWrapper.getOrThrow()
                let caller = cgMod.GetOrInsertCGFunction(applyWrapper.GetTopLevelFunc().getOrThrow())
                let calleeFunc = cgMod.GetOrInsertCGFunction(applyWrapper.GetCallee())
                let thisParamType = applyWrapper.GetThisParam().getOrThrow().GetType().getOrThrow()
                cgMod.GetCGContext().AddCallBaseToReplace(CallBaseToReplaceInfo(callBase, caller, calleeFunc,
                    thisParamType, applyWrapper.IsCalleeStructMutOrCtorMethod()))
            }
            if (funcType.IsCFunc()) {
                SetZExtAttrForCFunc(callBase, calleeType.GetLLVMFunctionType())
            }
            return GetReturnValue(calleeType, callBase, callArgs)
        }
        return CreateCallOrInvoke(callee, calleeType.GetLLVMFunctionType(), llvmCallArgs, name: name)
    }

    public func CreateCallOrInvoke(callee: CGFunction, args!: ArrayList<CGValue> = ArrayList<CGValue>(),
        name!: String = ""): LLVMValueRef {
        if (let Some(functionType) <- callee.GetCGFunctionType()) {
            return CreateCallOrInvoke(functionType, callee.GetRawFunction(), args, name: name)
        }
        return LLVMNullValue()
    }

    private func TransformLLVMCallArgs(calleeType: CGFunctionType, callArgs: ArrayList<LLVMValueRef>,
        name!: String = ""): ArrayList<LLVMValueRef> {
        if (!calleeType.HasSRet() || callArgs.isEmpty()) {
            return callArgs
        }
        let fixedArgs = ArrayList<LLVMValueRef>()
        for (arg in callArgs) {
            fixedArgs.add(arg)
        }
        if (let Some(sretParamType) <- GetLLVMFunctionParamType(calleeType.GetLLVMFunctionType(), 0u32)) {
            let castName = if (name.isEmpty()) { "sret.arg" } else { name + ".sret.arg" }
            fixedArgs[0] = CreatePointerCast(fixedArgs[0], sretParamType, name: castName)
        }
        return fixedArgs
    }

    private func GetLLVMFunctionParamType(functionType: LLVMTypeRef, paramIndex: UInt32): Option<LLVMTypeRef> {
        if (functionType.isNull()) {
            return None
        }
        let paramCount = unsafe { LLVMCountParamTypes(functionType) }
        if (paramIndex >= paramCount) {
            return None
        }
        var result: Option<LLVMTypeRef> = None
        try (paramTypes = LibC.malloc<LLVMTypeRef>(count: Int64(paramCount)).asResource()) {
            unsafe { LLVMGetParamTypes(functionType, paramTypes.value) }
            result = Some(unsafe { (paramTypes.value + Int64(paramIndex)).read() })
        }
        return result
    }

    private func TransformFuncArgs(calleeType: CGFunctionType, args: ArrayList<CGValue>,
        methodTypeInfoArg: Option<LLVMValueRef>, instTypeArgs: ArrayList<Type>,
        sretTypeInfoArg: Option<LLVMValueRef>, thisTypeInfoArg: Option<LLVMValueRef>,
        name!: String = ""): ArrayList<LLVMValueRef> {
        let callArgs = ArrayList<LLVMValueRef>()
        var applyExprWrapper: Option<CHIRApplyWrapper> = None
        var callExprWrapper: Option<CHIRCallExpr> = None
        if (let Some(exprWrapper) <- chirExpr) {
            let currentExpression = exprWrapper.GetExpression()
            if (let Some(applyExpr) <- (currentExpression as Apply)) {
                applyExprWrapper = Some(CHIRApplyWrapper(applyExpr))
            } else if (let Some(applyWithExceptionExpr) <- (currentExpression as ApplyWithException)) {
                applyExprWrapper = Some(CHIRApplyWrapper(applyWithExceptionExpr))
            }
            if (let Some(callExpr) <- (exprWrapper as CHIRCallExpr)) {
                callExprWrapper = Some(callExpr)
            }
        }
        if (calleeType.HasSRet()) {
            if (let Some(funcType) <- (calleeType.GetOriginal() as FuncType)) {
                let retCGType = CGType.GetOrCreate(cgMod, funcType.GetReturnType())
                callArgs.add(CreateSRetAlloca(funcType.GetReturnType(), retCGType, sretTypeInfoArg, name: name))
            }
        }
        if (let Some(funcType) <- (calleeType.GetOriginal() as FuncType)) {
            let paramTys = funcType.GetParamTypes()
            var idx: Int64 = 0
            for (arg in args) {
                let fixedArg = if (idx < paramTys.size) {
                    let paramType = calleeType.GetParamType(idx)
                    let isThis = idx == 0 && applyExprWrapper.isSome() &&
                        applyExprWrapper.getOrThrow().IsCalleeStructInstanceMethod()
                    var llvmVal = if (isThis) {
                        DoSimpleCast(arg, paramType, name)
                    } else {
                        FixFuncArg(arg, paramType, name: name)
                    }
                    llvmVal
                } else {
                    arg.GetRawValue()
                }
                callArgs.add(fixedArg)
                if (idx < paramTys.size && calleeType.HasBasePtr() && IsRefStructParam(paramTys[idx])) {
                    callArgs.add(unsafe { LLVMConstNull(CGType.GetRefType(GetLLVMContext())) })
                }
                idx++
            }
            if (callExprWrapper.isNone() && chirExpr.isSome() &&
                chirExpr.getOrThrow().GetExpression().GetExprKind() == ExprKind.VARRAY_BUILDER) {
                let varrayBuilder = (chirExpr.getOrThrow().GetExpression() as VArrayBuilder).getOrThrow()
                let autoEnvOfInitFunc = varrayBuilder.GetInitFunc()
                let autoEnvVal = cgMod.GetMappedCGValue(autoEnvOfInitFunc).GetRawValue()
                let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())
                let typeInfo = CreateBitCast(GetTypeInfoFromObject(autoEnvVal), typeInfoPtrType)
                callArgs.add(typeInfo)
                return callArgs
            }
            let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())
            for (instTy in instTypeArgs) {
                let typeInfo = CreateTypeInfo(instTy)
                callArgs.add(CreateBitCast(typeInfo, typeInfoPtrType,
                    name: if (name.isEmpty()) { "generic.ti" } else { name + ".generic.ti" }))
            }
            if (calleeType.IsMethodType()) {
                if (let Some(callExpr) <- callExprWrapper) {
                    callArgs.add(CreateOuterTypeInfo(callExpr, thisTypeInfoArg))
                } else if (let Some(overrideTypeInfo) <- methodTypeInfoArg) {
                    if (calleeType.IsConstructorType() && !args.isEmpty()) {
                        callArgs.add(CreateOuterTypeInfoArg(args[0]) ?? overrideTypeInfo)
                    } else {
                        callArgs.add(overrideTypeInfo)
                    }
                } else if (!args.isEmpty()) {
                    if (let Some(thisTypeInfo) <- CreateOuterTypeInfoArg(args[0])) {
                        callArgs.add(thisTypeInfo)
                    }
                }
            }
            if (calleeType.IsStaticMethodType()) {
                var staticThisTypeInfoArg = thisTypeInfoArg
                if (staticThisTypeInfoArg.isNone()) {
                    staticThisTypeInfoArg = methodTypeInfoArg
                }
                if (let Some(staticThisTypeInfo) <- staticThisTypeInfoArg) {
                    callArgs.add(staticThisTypeInfo)
                } else {
                    callArgs.add(unsafe { LLVMConstNull(CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())) })
                }
            }
            return callArgs
        }
        for (arg in args) {
            callArgs.add(arg.GetRawValue())
        }
        return callArgs
    }

    private func CreateOuterTypeInfo(callExprWrapper: CHIRCallExpr,
        thisTypeInfo: Option<LLVMValueRef>): LLVMValueRef {
        let outerCHIRType = callExprWrapper.GetOuterType(GetCGContext().GetCHIRBuilder())
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())

        let callExpression = callExprWrapper.GetExpression()
        if ((callExpression as Apply).isSome() || (callExpression as ApplyWithException).isSome()) {
            return CreateBitCast(CreateTypeInfo(outerCHIRType), typeInfoPtrType)
        }

        let outerCHIRClassType = (outerCHIRType as ClassType).getOrThrow()
        if (callExprWrapper.IsCalleeStatic()) {
            if (GetCGContext().GetCGPkgContext().NeedOuterTypeInfo(outerCHIRClassType)) {
                let invokeStaticWrapper = (callExprWrapper as CHIRInvokeStaticWrapper).getOrThrow()
                let backupBB = GetInsertBlock()
                let prepForVirtualCallBB = invokeStaticWrapper.GetPrepForVirtualCallBB()
                if (!prepForVirtualCallBB.isNull()) {
                    SetInsertPointBefore(unsafe { LLVMGetBasicBlockTerminator(prepForVirtualCallBB) })
                }
                let typeInfo = if (DeRef(callExprWrapper.GetThisType().getOrThrow()).IsThis()) {
                    thisTypeInfo.getOrThrow()
                } else {
                    CreateBitCast(CreateTypeInfo(callExprWrapper.GetThisType().getOrThrow()), typeInfoPtrType)
                }
                let methodOuterTypeArgs = ArrayList<LLVMValueRef>()
                methodOuterTypeArgs.add(typeInfo)
                methodOuterTypeArgs.add(CreateTypeInfo(outerCHIRType))
                methodOuterTypeArgs.add(GetInt64(Int64(invokeStaticWrapper.GetVirtualMethodOffset())))
                let outerType = CallIntrinsicMethodOuterType(methodOuterTypeArgs)
                if (!prepForVirtualCallBB.isNull()) {
                    GetCGContext().SetGetOuterTypeInst(GetInsertCGFunction().getOrThrow(), prepForVirtualCallBB,
                        outerType)
                    SetInsertPoint(backupBB)
                }
                return CreateBitCast(outerType, typeInfoPtrType)
            } else {
                return unsafe { LLVMConstNull(typeInfoPtrType) }
            }
        }

        let invokeWrapper = (callExprWrapper as CHIRInvokeWrapper).getOrThrow()
        if (DeRef(invokeWrapper.GetObject().GetType().getOrThrow()).IsAutoEnv()) {
            return GetTypeInfoFromObject(cgMod.GetMappedCGValue(callExprWrapper.GetThisParam().getOrThrow()).GetRawValue())
        } else if (GetCGContext().GetCGPkgContext().NeedOuterTypeInfo(outerCHIRClassType)) {
            let backupBB = GetInsertBlock()
            let prepForVirtualCallBB = invokeWrapper.GetPrepForVirtualCallBB()
            if (!prepForVirtualCallBB.isNull()) {
                SetInsertPointBefore(unsafe { LLVMGetBasicBlockTerminator(prepForVirtualCallBB) })
            }
            let typeInfo = GetTypeInfoFromObject(
                cgMod.GetMappedCGValue(callExprWrapper.GetThisParam().getOrThrow()).GetRawValue())
            let methodOuterTypeArgs = ArrayList<LLVMValueRef>()
            methodOuterTypeArgs.add(typeInfo)
            methodOuterTypeArgs.add(CreateTypeInfo(outerCHIRType))
            methodOuterTypeArgs.add(GetInt64(Int64(invokeWrapper.GetVirtualMethodOffset())))
            let outerType = CallIntrinsicMethodOuterType(methodOuterTypeArgs)
            if (!prepForVirtualCallBB.isNull()) {
                GetCGContext().SetGetOuterTypeInst(GetInsertCGFunction().getOrThrow(), prepForVirtualCallBB, outerType)
                SetInsertPoint(backupBB)
            }
            return CreateBitCast(outerType, typeInfoPtrType)
        } else {
            return unsafe { LLVMConstNull(typeInfoPtrType) }
        }
    }

    private func IsOptionLikeRefValue(argCGType: CGType): Bool {
        if (let Some(enumCGType) <- (CGType.GetOrCreate(cgMod, argCGType.GetOriginal()) as CGEnumType)) {
            return enumCGType.IsOptionLikeRef()
        }
        return false
    }

    private func DoSimpleCast(arg: CGValue, destType: CGType, name: String): LLVMValueRef {
        let raw = arg.GetRawValue()
        let argCGType = arg.GetCGType() ?? return raw
        let rawTy = unsafe { LLVMTypeOf(raw) }
        if (!argCGType.IsStructPtrType() && !argCGType.IsVArrayPtrType()) {
            return raw
        }
        let destPtrTy = destType.GetLLVMType()
        if (rawTy.isNull() || unsafe { LLVMGetTypeKind(rawTy) } != LLVM_POINTER_TYPE_KIND ||
            unsafe { LLVMGetTypeKind(destPtrTy) } != LLVM_POINTER_TYPE_KIND) {
            return raw
        }
        let rawAddrspace = unsafe { LLVMGetPointerAddressSpace(rawTy) }
        let destAddrspace = destType.GetAddrspace()
        if (rawAddrspace != destAddrspace) {
            return CreateAddrSpaceCast(raw, destPtrTy,
                name: if (name.isEmpty()) { "arg.cast" } else { name + ".arg.cast" })
        }
        return CreateBitCast(raw, destPtrTy, name: if (name.isEmpty()) { "arg.cast" } else { name + ".arg.cast" })
    }

    private func FixFuncArg(arg: CGValue, destType: CGType, name!: String = ""): LLVMValueRef {
        let raw = arg.GetRawValue()
        let rawTy = unsafe { LLVMTypeOf(raw) }
        let argCGType = arg.GetCGType() ?? return raw
        let destDerefType = CGType.GetOrCreate(cgMod, destType.GetOriginal().StripAllRefs())
        let isValueOrAddr0 = rawTy.isNull() || unsafe { LLVMGetTypeKind(rawTy) } != LLVM_POINTER_TYPE_KIND ||
            unsafe { LLVMGetPointerAddressSpace(rawTy) } == 0u32
        if ((isValueOrAddr0 || IsOptionLikeRefValue(argCGType)) && destDerefType.GetSize().isNone()) {
            let argTy = argCGType.GetOriginal().StripAllRefs()
            let objectValue = CallAllocaGeneric(argTy)
            let payloadPtr = GetPayloadFromObject(objectValue)
            let argDerefCGType = CGType.GetOrCreate(cgMod, argTy)
            if (argTy.IsStruct()) {
                let size = GetLayoutSize_64(argTy)
                if (IsLLVMTypeContainsRef(argDerefCGType.GetLLVMType())) {
                    CallGCWriteAgg(argDerefCGType.GetLayoutType(),
                        ArrayList<LLVMValueRef>([objectValue, payloadPtr, raw, size]))
                } else {
                    CreateMemCpy(payloadPtr, 0u32, raw, 0u32, size)
                }
            } else {
                let addr = CreateBitCast(payloadPtr, unsafe { LLVMPointerType(argDerefCGType.GetLLVMType(), 1u32) })
                let addrType = CGType.GetOrCreate(cgMod, GetCGContext().GetCHIRBuilder().context.GetRefTy(argTy),
                    extraInfo: TypeExtraInfo(1u32))
                CreateStore(arg, CGValue(addr, addrType))
            }
            return objectValue
        }
        return DoSimpleCast(arg, destType, name)
    }

    private func StoreAggregateArgToSlot(raw: LLVMValueRef, slot: LLVMValueRef): LLVMValueRef {
        return CreateStore(raw, slot)
    }

    private func IsRefStructParam(paramTy: Type): Bool {
        if (!paramTy.IsRef()) {
            return false
        }
        let derefTy = paramTy.StripAllRefs()
        return derefTy.IsStruct() || derefTy.IsTuple()
    }

    private func CreateOuterTypeInfoArg(thisArg: CGValue): Option<LLVMValueRef> {
        if (let Some(thisCGType) <- thisArg.GetCGType()) {
            let thisTy = thisCGType.GetOriginal().StripAllRefs()
            if (thisTy.IsStruct() || thisTy.IsTuple() || thisTy.IsClass() || thisTy.IsEnum()) {
                if (CGType.GetOrCreate(cgMod, thisTy).IsDynamicGI()) {
                    return Some(CreatePointerCast(CreateTypeInfo(thisTy),
                        CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext()), name: "this.ti"))
                }
                return Some(CGType.GetOrCreate(cgMod, thisTy).GetOrCreateTypeInfo())
            }
        }
        return None
    }

    private func CreateSRetAlloca(retTy: Type, retCGType: CGType, sretTypeInfoArg: Option<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        let allocaName = if (name.isEmpty()) { "sret" } else { name + ".sret" }
        let resultTy = CurrentExpressionResultType() ?? retTy
        if (retCGType.GetSize().isSome()) {
            return CreateEntryAlloca(retCGType, name: allocaName)
        }
        return CreateSRetForUnknownSize(retTy, resultTy, sretTypeInfoArg, name: allocaName)
    }

    private func CurrentExpressionResultType(): Option<Type> {
        if (let Some(exprWrapper) <- chirExpr) {
            if (let Some(resultTy) <- exprWrapper.GetExpression().GetResultType()) {
                return Some(resultTy)
            }
        }
        return None
    }

    private func CreateSRetForUnknownSize(returnTy: Type, resultTy: Type, sretTypeInfoArg: Option<LLVMValueRef>,
        name!: String = "sret"): LLVMValueRef {
        let returnCGType = CGType.GetOrCreate(cgMod, returnTy)
        if (let Some(genericResultTy) <- GetGenericSRetRuntimeType(returnTy, resultTy)) {
            return CreateSRetGeneric(returnCGType, genericResultTy, sretTypeInfoArg, name: name)
        }
        if (returnTy.IsGeneric()) {
            let slot = CreateEntryAlloca(returnCGType, name: name)
            CreateStore(unsafe { LLVMConstNull(CGType.GetRefType(GetLLVMContext())) }, slot)
            let resultCGType = CGType.GetOrCreate(cgMod, resultTy)
            if (!resultCGType.IsReference()) {
                let storage = if (let Some(typeInfo) <- sretTypeInfoArg) {
                    CallAllocaGenericWithTypeInfo(resultTy, typeInfo)
                } else {
                    CallAllocaGeneric(resultTy)
                }
                CreateStore(storage, slot)
            }
            return slot
        }
        if (returnTy.IsStruct() || returnTy.IsTuple() || returnTy.IsEnum()) {
            return CallAllocaGeneric(resultTy)
        }
        return CreateEntryAlloca(returnCGType.GetLLVMType(), name: name)
    }

    private func GetGenericSRetRuntimeType(returnTy: Type, resultTy: Type): Option<Type> {
        if (returnTy.IsGeneric() && resultTy.IsRef()) {
            if (let Some(boxTy) <- (resultTy.StripAllRefs() as BoxType)) {
                return Some(boxTy.GetBaseType())
            }
        }
        if (resultTy.IsGeneric()) {
            return Some(resultTy)
        }
        return None
    }

    private func CreateSRetGeneric(returnCGType: CGType, resultTy: Type, sretTypeInfoArg: Option<LLVMValueRef>,
        name!: String = "sret"): LLVMValueRef {
        let slot = CreateEntryAlloca(returnCGType, name: name)
        CreateStore(unsafe { LLVMConstNull(CGType.GetRefType(GetLLVMContext())) }, slot)
        let typeInfo = if (let Some(overrideTypeInfo) <- sretTypeInfoArg) {
            overrideTypeInfo
        } else {
            CreateTypeInfo(resultTy)
        }
        let blockNames = ArrayList<String>()
        blockNames.add("prepNRSRet")
        blockNames.add("end")
        let blocks = CreateAndInsertBasicBlocks(blockNames)
        if (blocks.size < 2) {
            return slot
        }
        CreateCondBr(CreateTypeInfoIsReferenceCall(resultTy), blocks[1], blocks[0])
        SetInsertPoint(blocks[0])
        CreateStore(CallAllocaGenericWithTypeInfo(resultTy, typeInfo), slot)
        CreateBr(blocks[1])
        SetInsertPoint(blocks[1])
        return slot
    }

    public func CallAllocaGeneric(chirTy: Type): LLVMValueRef {
        let tyForInfo = chirTy.StripAllRefs()
        let typeInfoValue = CreateTypeInfo(tyForInfo)
        return CallAllocaGenericWithTypeInfo(tyForInfo, typeInfoValue)
    }

    private func CallAllocaGenericWithTypeInfo(chirTy: Type, typeInfoValue: LLVMValueRef): LLVMValueRef {
        let tyForInfo = chirTy.StripAllRefs()
        let cgTy = CGType.GetOrCreate(cgMod, tyForInfo)
        return CallAllocaGenericWithTypeInfoAndSize(tyForInfo, typeInfoValue,
            GetLayoutSize32ForAllocaGeneric(cgTy, typeInfoValue))
    }

    public func CallAllocaGenericWithTypeInfoAndSize(chirTy: Type, typeInfoValue: LLVMValueRef,
        size: LLVMValueRef): LLVMValueRef {
        let tyForInfo = chirTy.StripAllRefs()
        EnsureAllocaGenericLayoutMetadata(tyForInfo, typeInfoValue)
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let typeInfoArg = CreateBitCast(typeInfoValue, i8PtrType, name: "sret.ti")
        let args = ArrayList<LLVMValueRef>()
        args.add(typeInfoArg)
        args.add(size)
        CheckNoHeapAlloc(ALLOCA_GENERIC_INTRINSIC_NAME)
        return CreateIntrinsicCall(ALLOCA_GENERIC_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args,
            name: "sret.generic")
    }

    public func CallIntrinsicAllocaGeneric(parameters: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(parameters.size == 2)
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreateBitCast(parameters[0], i8PtrType, name: "alloca.generic.ti"))
        args.add(parameters[1])
        CheckNoHeapAlloc(ALLOCA_GENERIC_INTRINSIC_NAME)
        return CreateIntrinsicCall(ALLOCA_GENERIC_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args,
            name: "sret.generic")
    }

    private func GetLayoutSize32ForAllocaGeneric(cgTy: CGType, typeInfoValue: LLVMValueRef): LLVMValueRef {
        if (let Some(staticSize) <- cgTy.GetSize()) {
            return unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), UInt64(staticSize), 0) }
        }
        return GetSizeFromTypeInfo(typeInfoValue)
    }

    private func EnsureAllocaGenericLayoutMetadata(chirTy: Type, typeInfoValue: LLVMValueRef): Unit {
        if (typeInfoValue.isNull() || chirTy.IsGeneric()) {
            return
        }
        let cgType = CGType.GetOrCreate(cgMod, chirTy)
        let layoutType = cgType.GetLayoutType()
        let layoutName = if (!layoutType.isNull() && unsafe { LLVMGetTypeKind(layoutType) } == LLVM_STRUCT_TYPE_KIND) {
            LLVMCStringToString(unsafe { LLVMGetStructName(layoutType) }) ?? ""
        } else if (chirTy.IsClass()) {
            GetClassObjLayoutName(chirTy.ToString())
        } else if (chirTy.IsRawArray()) {
            ARRAY_LAYOUT_PREFIX + chirTy.ToString()
        } else if (chirTy.IsString()) {
            STRUCT_TYPE_PREFIX + "std.core:String"
        } else if (chirTy.IsStruct() || chirTy.IsTuple() || chirTy.IsEnum()) {
            STRUCT_TYPE_PREFIX + chirTy.ToString()
        } else {
            return
        }
        if (layoutName.isEmpty()) {
            return
        }
        LLVMSetGlobalStringMetadata(GetLLVMContext(), typeInfoValue, GC_TYPE_META_NAME, layoutName)
    }

    private func GetReturnValue(calleeType: CGFunctionType, callBase: LLVMValueRef,
        callArgs: ArrayList<LLVMValueRef>): LLVMValueRef {
        let funcType = (calleeType.GetOriginal() as FuncType).getOrThrow()
        let returnTy = funcType.GetReturnType()
        let returnCGType = CGType.GetOrCreate(cgMod, returnTy)
        var retValue = callBase
        if (calleeType.HasSRet()) {
            AddNoAliasAttribute(callBase)
            AddSRetAttribute(callBase, GetSRetAttributeType(returnTy, returnCGType))
            retValue = callArgs[0]
            if (returnCGType.GetSize().isNone()) {
                let expression = chirExpr.getOrThrow().GetExpression()
                let resultTy = if (expression.GetExprKind() == ExprKind.VARRAY_BUILDER) {
                    let varrayBuilder = (expression as VArrayBuilder).getOrThrow()
                    let varrayType = (varrayBuilder.GetResult().getOrThrow().GetType().getOrThrow() as
                        VArrayType).getOrThrow()
                    varrayType.GetElementType()
                } else {
                    expression.GetResult().getOrThrow().GetType().getOrThrow()
                }
                let resultCGType = CGType.GetOrCreate(cgMod, resultTy)
                if (returnTy.IsGeneric()) {
                    retValue = CreateLoad(returnCGType.GetLLVMType(), retValue, name: "sret.load")
                }
                if (resultCGType.GetSize().isNone() && !resultTy.IsGeneric()) {
                    retValue = CopyUnknownSizeSRetReturn(retValue, resultTy)
                } else if (resultCGType.GetSize().isSome() && !resultCGType.IsReference()) {
                    let elementType = resultCGType.GetLLVMType()
                    let payload = GetPayloadFromObject(retValue)
                    let payloadType = unsafe { LLVMPointerType(elementType, 1u32) }
                    let typedPayload = CreateBitCast(payload, payloadType, name: "sret.payload")
                    return CreateLoad(elementType, typedPayload)
                }
            }
        }
        if (returnTy.IsUnit()) {
            retValue = cgMod.GenerateUnitTypeValue()
        }
        return retValue
    }

    private func CopyUnknownSizeSRetReturn(retValue: LLVMValueRef, resultTy: Type): LLVMValueRef {
        let typeInfo = CreateTypeInfo(resultTy)
        let tmp = CallAllocaGenericWithTypeInfo(resultTy, typeInfo)
        CallAssignGeneric(tmp, retValue, typeInfo)
        return tmp
    }

    private func GetSRetAttributeType(retType: Type, retCGType: CGType): LLVMTypeRef {
        if (retCGType.GetSize().isNone() && !retType.IsGeneric()) {
            return unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        }
        return retCGType.GetLLVMType()
    }

    public func GetOrInsertIntrinsicDeclaration(intrinsicName: String): LLVMValueRef {
        return GetOrInsertIntrinsicDeclaration(intrinsicName, ArrayList<LLVMTypeRef>())
    }

    public func GetOrInsertIntrinsicDeclaration(intrinsicName: String,
        overloadedTypes: ArrayList<LLVMTypeRef>): LLVMValueRef {
        let intrinsicID = LookupIntrinsicID(intrinsicName)
        if (intrinsicID == 0u32) {
            return LLVMNullValue()
        }
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            if (overloadedTypes.isEmpty()) {
                return unsafe {
                    LLVMGetIntrinsicDeclaration(moduleHandle.raw, intrinsicID, CPointer<LLVMTypeRef>(), 0)
                }
            }
            var result = LLVMNullValue()
            try (typePtr = LibC.malloc<LLVMTypeRef>(count: overloadedTypes.size).asResource()) {
                var typeIdx: Int64 = 0
                while (typeIdx < overloadedTypes.size) {
                    unsafe { (typePtr.value + typeIdx).write(overloadedTypes[typeIdx]) }
                    typeIdx++
                }
                result = unsafe {
                    LLVMGetIntrinsicDeclaration(moduleHandle.raw, intrinsicID, typePtr.value,
                        UIntNative(overloadedTypes.size))
                }
            }
            return result
        }
        return LLVMNullValue()
    }

    public func GetIntrinsicFunctionType(intrinsicName: String): LLVMTypeRef {
        return GetIntrinsicFunctionType(intrinsicName, ArrayList<LLVMTypeRef>())
    }

    public func GetIntrinsicFunctionType(intrinsicName: String, overloadedTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        let intrinsicID = LookupIntrinsicID(intrinsicName)
        if (intrinsicID == 0u32) {
            return LLVMNullType()
        }
        if (overloadedTypes.isEmpty()) {
            return unsafe { LLVMIntrinsicGetType(GetLLVMContext().raw, intrinsicID, CPointer<LLVMTypeRef>(), 0) }
        }
        var result = LLVMNullType()
        try (typePtr = LibC.malloc<LLVMTypeRef>(count: overloadedTypes.size).asResource()) {
            var typeIdx: Int64 = 0
            while (typeIdx < overloadedTypes.size) {
                unsafe { (typePtr.value + typeIdx).write(overloadedTypes[typeIdx]) }
                typeIdx++
            }
            result = unsafe {
                LLVMIntrinsicGetType(GetLLVMContext().raw, intrinsicID, typePtr.value, UIntNative(overloadedTypes.size))
            }
        }
        return result
    }

    public func CallIntrinsicFloatToIntegerSat(destTy: LLVMTypeRef, sourceValue: LLVMValueRef,
        isSigned: Bool): LLVMValueRef {
        let intrinsicName = if (isSigned) { "llvm.fptosi.sat" } else { "llvm.fptoui.sat" }
        let overloadedTypes = ArrayList<LLVMTypeRef>([destTy, unsafe { LLVMTypeOf(sourceValue) }])
        let function = GetOrInsertIntrinsicDeclaration(intrinsicName, overloadedTypes)
        return CreateCall(function, unsafe { LLVMGlobalGetValueType(function) },
            ArrayList<LLVMValueRef>([sourceValue]))
    }

    public func CreateIntrinsicCall(intrinsicName: String, overloadedTypes: ArrayList<LLVMTypeRef>,
        args: ArrayList<LLVMValueRef>, name!: String = ""): LLVMValueRef {
        let callee = GetOrInsertIntrinsicDeclaration(intrinsicName, overloadedTypes)
        if (callee.isNull()) {
            return LLVMNullValue()
        }
        let calleeType = GetIntrinsicFunctionType(intrinsicName, overloadedTypes)
        if (calleeType.isNull()) {
            return LLVMNullValue()
        }
        return CreateCallOrInvoke(callee, args, name: name)
    }

    public func CreateIntrinsicCallNoInvoke(intrinsicName: String, overloadedTypes: ArrayList<LLVMTypeRef>,
        args: ArrayList<LLVMValueRef>, name!: String = ""): LLVMValueRef {
        let callee = GetOrInsertIntrinsicDeclaration(intrinsicName, overloadedTypes)
        if (callee.isNull()) {
            return LLVMNullValue()
        }
        let calleeType = GetIntrinsicFunctionType(intrinsicName, overloadedTypes)
        if (calleeType.isNull()) {
            return LLVMNullValue()
        }
        return CreateCall(callee, calleeType, args, name: name)
    }

    public func CallSetLocation(): LLVMValueRef {
        if (!GetCGContext().GetCompileOptions().enableCompileDebug) {
            return LLVMNullValue()
        }
        let callInst = CreateIntrinsicCallNoInvoke(SET_LOCATION_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(),
            ArrayList<LLVMValueRef>())
        if (!callInst.isNull() && GetCGContext().GetCompileOptions().target.arch != ArchType.ARM32) {
            unsafe { LLVMSelfhostSetAnyRegCallingConv(callInst) }
        }
        return callInst
    }

    public func CallRuntimeIntrinsics(kind: IntrinsicKind, args: ArrayList<Value>,
        resultType: Option<Type>): LLVMValueRef {
        return CallMappedIntrinsic(kind, args, resultType)
    }

    public func CallInteropIntrinsics(kind: IntrinsicKind, args: ArrayList<Value>,
        resultType: Option<Type>): LLVMValueRef {
        return CallMappedIntrinsic(kind, args, resultType)
    }

    public func CallSyncIntrinsics(kind: IntrinsicKind, args: ArrayList<Value>, typeArgs: ArrayList<Type>,
        resultType: Option<Type>): LLVMValueRef {
        if (IsAtomicIntrinsicKind(kind)) {
            return CallAtomicIntrinsics(kind, MapIntrinsicArguments(args), typeArgs, resultType)
        }
        return CallMappedIntrinsic(kind, args, resultType)
    }

    public func CallStackTraceIntrinsic(kind: IntrinsicKind, args: ArrayList<Value>,
        resultType: Option<Type>): LLVMValueRef {
        let parameters = MapIntrinsicArguments(args)
        if (kind == IntrinsicKind.FILL_IN_STACK_TRACE) {
            CJC_ASSERT(!parameters.isEmpty())
            let retTy = resultType.getOrThrow()
            let uint64ArrayTy = (DeRef(retTy) as RawArrayType).getOrThrow()
            let funcArgs = RawValuesOfCGValues(parameters)
            let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
            funcArgs[0] = CreateBitCast(CreateTypeInfo(uint64ArrayTy), i8PtrTy)
            return CreateIntrinsicCallNoInvoke(FILL_IN_STACK_TRACE_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(),
                funcArgs)
        }
        if (kind == IntrinsicKind.DECODE_STACK_TRACE) {
            let retTy = resultType.getOrThrow()
            let retCGType = CGType.GetOrCreate(cgMod, retTy)
            let resultStructTy = (retTy as StructType).getOrThrow()
            let uint8ArrayTy = (DeRef(resultStructTy.GetStructDef().GetInstanceVar(0).ty) as RawArrayType)
                .getOrThrow()
            parameters.add(CreateTypeInfoAsInt8RefCGValue(uint8ArrayTy))
            return CallIntrinsicFunction(retCGType.GetLLVMType(), "CJ_MCC_DecodeStackTrace", parameters,
                ArrayList<String>())
        }
        throw IllegalStateException("unsupported stack trace intrinsic")
    }

    public func CallThreadInfoIntrinsic(kind: IntrinsicKind, args: ArrayList<Value>,
        resultType: Option<Type>): LLVMValueRef {
        let parameters = MapIntrinsicArguments(args)
        let retTy = resultType.getOrThrow()
        let retCGType = CGType.GetOrCreate(cgMod, retTy)
        if (kind == IntrinsicKind.DUMP_CURRENT_THREAD_INFO) {
            let snapshotInfoDef = (retTy as StructType).getOrThrow().GetStructDef()
            let stackTraceArrayTy = (DeRef(snapshotInfoDef.GetInstanceVar(2).ty) as RawArrayType).getOrThrow()
            parameters.add(CreateTypeInfoAsInt8RefCGValue(stackTraceArrayTy))
            let charArrayTy = (DeRef(snapshotInfoDef.GetInstanceVar(0).ty) as RawArrayType).getOrThrow()
            parameters.add(CreateTypeInfoAsInt8RefCGValue(charArrayTy))
            return CallIntrinsicFunction(retCGType.GetLLVMType(), "CJ_MCC_GetCurrentThreadSnapshot", parameters,
                ArrayList<String>())
        }
        if (kind == IntrinsicKind.DUMP_ALL_THREADS_INFO) {
            let snapshotArrayTy = (DeRef(retTy) as RawArrayType).getOrThrow()
            let snapshotInfoDef = (snapshotArrayTy.GetElementType() as StructType).getOrThrow().GetStructDef()
            parameters.add(CreateTypeInfoAsInt8RefCGValue(snapshotArrayTy))
            let stackTraceArrayTy = (DeRef(snapshotInfoDef.GetInstanceVar(2).ty) as RawArrayType).getOrThrow()
            parameters.add(CreateTypeInfoAsInt8RefCGValue(stackTraceArrayTy))
            let charArrayTy = (DeRef(snapshotInfoDef.GetInstanceVar(0).ty) as RawArrayType).getOrThrow()
            parameters.add(CreateTypeInfoAsInt8RefCGValue(charArrayTy))
            return CallIntrinsicFunction(retCGType.GetLLVMType(), "CJ_MCC_GetAllThreadSnapshot", parameters,
                ArrayList<String>())
        }
        throw IllegalStateException("unsupported thread info intrinsic")
    }

    public func CallMathIntrinsics(kind: IntrinsicKind, args: ArrayList<Value>): LLVMValueRef {
        let parameters = RawValuesOfCGValues(MapIntrinsicArguments(args))
        CJC_ASSERT(!parameters.isEmpty())
        if (kind == IntrinsicKind.POWI) {
            CJC_ASSERT(parameters.size == 2)
            let overloadedTypes = ArrayList<LLVMTypeRef>()
            overloadedTypes.add(unsafe { LLVMTypeOf(parameters[0]) })
            overloadedTypes.add(unsafe { LLVMTypeOf(parameters[1]) })
            return CallMappedLLVMIntrinsic(kind, parameters, overloadedTypes)
        }
        let overloadedTypes = ArrayList<LLVMTypeRef>()
        overloadedTypes.add(unsafe { LLVMTypeOf(parameters[0]) })
        if (kind == IntrinsicKind.ABS) {
            parameters.add(GetFalse())
        }
        return CallMappedLLVMIntrinsic(kind, parameters, overloadedTypes)
    }

    public func CallIntrinsicForUninitialized(ty: Type): LLVMValueRef {
        if (ty.IsGeneric()) {
            let blocks = CreateAndInsertBasicBlocks(ArrayList<String>([
                GenNameForBB("handle_ref"), GenNameForBB("handle_non_ref"), GenNameForBB("handle_nothing"),
                GenNameForBB("get_uninitialized_value")]))
            let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
            let ti = CreateBitCast(CreateTypeInfo(ty), i8PtrTy)
            let nothingTi = CreateBitCast(CGType.GetNothingCGType(cgMod).GetOrCreateTypeInfo(), i8PtrTy)
            let isNothing = GenerateCallExpectFunction(
                CreateICmp(LLVMIntPredicate.EQ, ti, nothingTi), GetFalse())
            CreateCondBr(isNothing, blocks[2], blocks[0])

            SetInsertPoint(blocks[2])
            CreateRunTimeInvalidGenericParamException()
            CreateUnreachable()

            SetInsertPoint(blocks[0])
            let isRef = CreateTypeInfoIsReferenceCall(ti)
            let lastBBOfHandleRef = GetInsertBlock()
            CreateCondBr(isRef, blocks[3], blocks[1])

            SetInsertPoint(blocks[1])
            let zeroValue = CreateNullValue(ty)
            let lastBBOfHandleNonRef = GetInsertBlock()
            CreateBr(blocks[3])

            SetInsertPoint(blocks[3])
            let p1i8 = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 1u32) }
            let phi = CreatePHI(p1i8)
            AddIncoming(phi, ArrayList<LLVMValueRef>([unsafe { LLVMConstNull(p1i8) }, zeroValue]),
                ArrayList<LLVMBasicBlockRef>([lastBBOfHandleRef, lastBBOfHandleNonRef]))
            return phi
        }
        return CreateNullValue(ty)
    }

    public func CallIntrinsicFunction(retType: LLVMTypeRef, name: String, parameters: ArrayList<CGValue>,
        attributes: ArrayList<String>): LLVMValueRef {
        CJC_ASSERT(!retType.isNull())
        let parameterTypes = BuildIntrinsicFunctionParamTypes(name, parameters)
        let hasSRet = IntrinsicFunctionNeedsSRet(retType)
        let functionType = BuildIntrinsicFunctionType(retType, parameterTypes, hasSRet)
        let functionValue = GetOrCreateIntrinsicFunction(name, functionType, retType, hasSRet, attributes)
        let callArgs = BuildIntrinsicFunctionCallArgs(name, retType, hasSRet, parameters)
        let callInst = CreateCallOrInvoke(functionValue, callArgs)
        if (hasSRet) {
            return callArgs[0]
        }
        return callInst
    }

    public func CallGCReadWeakRef(args: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(args.size == 2)
        let refTy = CGType.GetRefType(GetLLVMContext())
        let refPlaceTy = unsafe { LLVMPointerType(refTy, 1u32) }
        let fixedArgs = ArrayList<LLVMValueRef>()
        fixedArgs.add(CreatePointerCast(args[0], refTy, name: "gcread.weak.base"))
        fixedArgs.add(CreatePointerCast(args[1], refPlaceTy, name: "gcread.weak.place"))
        return CreateIntrinsicCallNoInvoke(GCREAD_WEAK_REF_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), fixedArgs,
            name: "gcread.weak")
    }

    public func CallVArrayIntrinsicIndexCheck(arrayPtr: CGValue, indices: ArrayList<LLVMValueRef>): Unit {
        var arrayType = arrayPtr.GetCGType().getOrThrow().GetPointerElementType().getOrThrow().GetLLVMType()
        for (index in indices) {
            CJC_ASSERT(unsafe { LLVMGetTypeKind(arrayType) } == LLVM_ARRAY_TYPE_KIND)
            let len = unsafe {
                LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), UInt64(LLVMGetArrayLength(arrayType)), 0)
            }
            CallIntrinsicIndexCheck(len, index)
            let elementType = unsafe { LLVMGetElementType(arrayType) }
            if (elementType.isNull() || unsafe { LLVMGetTypeKind(elementType) } != LLVM_ARRAY_TYPE_KIND) {
                return
            }
            arrayType = elementType
        }
    }

    public func CreateRefStore(cgValue: CGValue, basePtr: LLVMValueRef, place: LLVMValueRef,
        isBaseObjStruct: Bool): Unit {
        let currentFunction = GetInsertFunction()
        CJC_ASSERT(!currentFunction.isNull())
        let inStructMut = HasAttributeAtIndex(currentFunction, UInt32.Max, STRUCT_MUT_FUNC_ATTR)
        let valueCGType = cgValue.GetCGType().getOrThrow()
        let value = cgValue.GetRawValue()
        var base = basePtr
        let isDstAddrspace1 = unsafe { LLVMGetPointerAddressSpace(LLVMTypeOf(base)) } == 1u32
        if (isBaseObjStruct) {
            if (IsGlobalVariableBasePtr(place) && valueCGType.IsPointerType() &&
                IsLLVMTypeContainsRef(valueCGType.GetPointerElementType().getOrThrow().GetLLVMType())) {
                CreateWriteBarrierForGlobalVariable(cgValue, CGValue(place, valueCGType))
                return
            }
            if (!inStructMut || unsafe { LLVMIsAArgument(base) }.isNull()) {
                if (valueCGType.IsPointerType()) {
                    CreateStore(cgValue, CGValue(place, valueCGType))
                } else {
                    CreateStore(value, place)
                }
                return
            } else {
                let baseName = LLVMCStringToString(unsafe { LLVMGetValueName(base) }) ?? ""
                if (baseName == "this") {
                    base = unsafe { LLVMGetPreviousParam(base) }
                }
            }
        }
        if (valueCGType.IsStructPtrType()) {
            let structType = valueCGType.GetPointerElementType().getOrThrow().GetLLVMType()
            if (isDstAddrspace1 && IsLLVMTypeContainsRef(structType)) {
                let size = unsafe {
                    LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), cgMod.GetTypeSize(structType), 0)
                }
                CallGCWriteAgg(structType, ArrayList<LLVMValueRef>([base, place, value, size]))
            } else {
                let size = unsafe {
                    LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), cgMod.GetTypeSize(structType), 0)
                }
                let align = cgMod.GetABITypeAlignment(structType)
                CreateMemCpy(place, align, value, align, size)
            }
        } else if (isDstAddrspace1 && valueCGType.IsVArrayPtrType()) {
            let valueType = valueCGType.GetPointerElementType().getOrThrow()
            let size = GetInt64(Int64(cgMod.GetTypeSize(valueType.GetLLVMType())))
            CallGCWriteAgg(valueType.GetLayoutType(), ArrayList<LLVMValueRef>([base, place, value, size]))
        } else if (isDstAddrspace1 && valueCGType.IsRefType()) {
            CallGCWrite(value, base, place)
        } else {
            CreateStore(value, place)
        }
    }

    public func CreateVArrayStore(cgValue: CGValue, place: LLVMValueRef): Unit {
        var basePtr = unsafe { LLVMConstNull(CGType.GetRefType(GetLLVMContext())) }
        var isBaseObjStruct = true
        if (!unsafe { LLVMIsAGetElementPtrInst(place) }.isNull()) {
            var operand = unsafe { LLVMGetOperand(place, 0u32) }
            while (!unsafe { LLVMIsAGetElementPtrInst(operand) }.isNull()) {
                operand = unsafe { LLVMGetOperand(operand, 0u32) }
                if (!unsafe { LLVMIsABitCastInst(operand) }.isNull()) {
                    basePtr = unsafe { LLVMGetOperand(operand, 0u32) }
                    isBaseObjStruct = false
                    break
                }
            }
        }
        CreateRefStore(cgValue, basePtr, place, isBaseObjStruct)
    }

    public func GetUUIDFromTypeInfo(typeInfo: LLVMValueRef): LLVMValueRef {
        let typeInfoType = CGType.GetOrCreateTypeInfoType(GetLLVMContext())
        let typeInfoPtrType = unsafe { LLVMPointerType(typeInfoType, 0u32) }
        let ptr = CreateStructGEP(typeInfoType, CreateBitCast(typeInfo, typeInfoPtrType),
            6u32, name: "ti.uuid")
        let uuid = CreateLoad(unsafe { LLVMInt32TypeInContext(GetLLVMContext().raw) }, ptr, name: "ti.uuid")
        LLVMSetInstructionMetadata(GetLLVMContext(), uuid, "invariant.load",
            LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>()))
        return uuid
    }

    public func GetTypeKindFromTypeInfo(typeInfo: LLVMValueRef): LLVMValueRef {
        let typeInfoType = CGType.GetOrCreateTypeInfoType(GetLLVMContext())
        let typeInfoPtrType = unsafe { LLVMPointerType(typeInfoType, 0u32) }
        let ptr = CreateStructGEP(typeInfoType, CreateBitCast(typeInfo, typeInfoPtrType),
            1u32, name: "ti.kind")
        let kind = CreateLoad(unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }, ptr, name: "ti.kind")
        LLVMSetInstructionMetadata(GetLLVMContext(), kind, "invariant.load",
            LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>()))
        return kind
    }

    public func CallIntrinsicFuncRefEq(parameters: ArrayList<CGValue>): LLVMValueRef {
        CJC_ASSERT(parameters.size == 2)
        let realUUID0 = GetRealUUIDForAutoEnvClass(parameters[0].GetRawValue())
        let realUUID1 = GetRealUUIDForAutoEnvClass(parameters[1].GetRawValue())
        return CreateICmp(LLVMIntPredicate.EQ, realUUID0, realUUID1, name: "refeq")
    }

    private func CallMappedIntrinsic(kind: IntrinsicKind, args: ArrayList<Value>,
        resultType: Option<Type>): LLVMValueRef {
        return CallMappedIntrinsicWithCGValues(kind, MapIntrinsicArguments(args), resultType)
    }

    private func CallMappedIntrinsicWithCGValues(kind: IntrinsicKind, parameters: ArrayList<CGValue>,
        resultType: Option<Type>): LLVMValueRef {
        if (let Some(funcName) <- IntrinsicRuntimeFunctionName(kind)) {
            return CallIntrinsicFunction(ResultLLVMType(resultType), funcName, parameters,
                IntrinsicFunctionAttributes(kind))
        }
        return CallMappedLLVMIntrinsic(kind, RawValuesOfCGValues(parameters), ArrayList<LLVMTypeRef>())
    }

    private func CallMappedLLVMIntrinsic(kind: IntrinsicKind, args: ArrayList<LLVMValueRef>,
        overloadedTypes: ArrayList<LLVMTypeRef>): LLVMValueRef {
        if (let Some(intrinsicName) <- IntrinsicLLVMName(kind)) {
            let finalOverloadedTypes = ArrayList<LLVMTypeRef>()
            if (IsPlatformDependent(kind)) {
                finalOverloadedTypes.add(GetSizetLLVMType())
            } else {
                for (overloadedType in overloadedTypes) {
                    finalOverloadedTypes.add(overloadedType)
                }
            }
            if (kind == IntrinsicKind.BLACK_BOX) {
                CJC_ASSERT(args.size == 1)
                let argType = unsafe { LLVMTypeOf(args[0]) }
                if (argType.isNull() || unsafe { LLVMGetTypeKind(argType) } != LLVM_POINTER_TYPE_KIND) {
                    return args[0]
                }
                let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
                if (unsafe { LLVMGetPointerAddressSpace(argType) } == 0u32) {
                    let arg = CreateBitCast(args[0], i8PtrTy)
                    return CreateBitCast(CreateIntrinsicCallNoInvoke(intrinsicName, finalOverloadedTypes,
                        ArrayList<LLVMValueRef>([arg])), argType)
                }
                let arg = CreateAddrSpaceCast(args[0], i8PtrTy)
                return CreateAddrSpaceCast(CreateIntrinsicCallNoInvoke(intrinsicName, finalOverloadedTypes,
                    ArrayList<LLVMValueRef>([arg])), argType)
            }
            return CreateIntrinsicCallNoInvoke(intrinsicName, finalOverloadedTypes, args)
        }
        throw IllegalStateException("unsupported LLVM intrinsic")
    }

    private func MapIntrinsicArguments(args: ArrayList<Value>): ArrayList<CGValue> {
        let parameters = ArrayList<CGValue>()
        for (arg in args) {
            parameters.add(cgMod.GetMappedCGValue(arg))
        }
        return parameters
    }

    private func RawValuesOfCGValues(parameters: ArrayList<CGValue>): ArrayList<LLVMValueRef> {
        let rawValues = ArrayList<LLVMValueRef>()
        for (parameter in parameters) {
            rawValues.add(parameter.GetRawValue())
        }
        return rawValues
    }

    private func ResultLLVMType(resultType: Option<Type>): LLVMTypeRef {
        if (let Some(retTy) <- resultType) {
            return CGType.GetOrCreate(cgMod, retTy).GetLLVMType()
        }
        return CGType.GetUnitType(GetLLVMContext())
    }

    private func CreateTypeInfoAsInt8RefCGValue(chirTy: Type): CGValue {
        let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        return CGValue(CreateBitCast(CreateTypeInfo(chirTy), i8PtrTy),
            CGType.GetOrCreate(cgMod, CGType.GetRefTypeOfCHIRInt8(GetCGContext().GetCHIRBuilder())))
    }

    private func IntrinsicFunctionNeedsSRet(retType: LLVMTypeRef): Bool {
        return retType.toUIntNative() != CGType.GetUnitType(GetLLVMContext()).toUIntNative() &&
            unsafe { LLVMGetTypeKind(retType) } == LLVM_STRUCT_TYPE_KIND
    }

    private func BuildIntrinsicFunctionParamTypes(name: String,
        parameters: ArrayList<CGValue>): ArrayList<LLVMTypeRef> {
        let parameterTypes = ArrayList<LLVMTypeRef>()
        for (parameter in parameters) {
            let valueCGType = parameter.GetCGType().getOrThrow()
            var paramType = unsafe { LLVMTypeOf(parameter.GetRawValue()) }
            if (IsStructPtrType(paramType) && !valueCGType.IsCGTI()) {
                if (!IsReflectIntrinsicFunctionName(name)) {
                    parameterTypes.add(CGType.GetRefType(GetLLVMContext()))
                }
                if (unsafe { LLVMGetPointerAddressSpace(paramType) } != 1u32) {
                    let elementCGType = valueCGType.GetPointerElementType().getOrThrow()
                    paramType = unsafe { LLVMPointerType(elementCGType.GetLLVMType(), 1u32) }
                }
            }
            parameterTypes.add(paramType)
        }
        return parameterTypes
    }

    private func BuildIntrinsicFunctionType(retType: LLVMTypeRef, parameterTypes: ArrayList<LLVMTypeRef>,
        hasSRet: Bool): LLVMTypeRef {
        if (!hasSRet) {
            return MakeFunctionType(retType, parameterTypes)
        }
        let fixedParameterTypes = ArrayList<LLVMTypeRef>()
        fixedParameterTypes.add(unsafe { LLVMPointerType(retType, 0u32) })
        for (parameterType in parameterTypes) {
            fixedParameterTypes.add(parameterType)
        }
        return MakeFunctionType(unsafe { LLVMVoidTypeInContext(GetLLVMContext().raw) }, fixedParameterTypes)
    }

    private func GetOrCreateIntrinsicFunction(name: String, functionType: LLVMTypeRef, retType: LLVMTypeRef,
        hasSRet: Bool, attributes: ArrayList<String>): LLVMValueRef {
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            var functionValue = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
                functionValue = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
                if (functionValue.isNull()) {
                    functionValue = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
                    if (hasSRet) {
                        AddNoAliasAttribute(functionValue)
                        AddSRetAttribute(functionValue, retType)
                    }
                    AddLinkageTypeMetadata(functionValue, LLVMLinkage.External,
                        GetCGContext().IsCGParallelEnabled())
                    for (attribute in attributes) {
                        AddFnAttr(functionValue, attribute)
                    }
                }
            }
            return functionValue
        }
        throw IllegalStateException("cannot create intrinsic function without an LLVM module")
    }

    private func BuildIntrinsicFunctionCallArgs(name: String, retType: LLVMTypeRef, hasSRet: Bool,
        parameters: ArrayList<CGValue>): ArrayList<LLVMValueRef> {
        let callArgs = ArrayList<LLVMValueRef>()
        if (hasSRet) {
            callArgs.add(CreateEntryAlloca(retType))
        }
        for (parameter in parameters) {
            let valueCGType = parameter.GetCGType().getOrThrow()
            var llvmVal = parameter.GetRawValue()
            let llvmValType = unsafe { LLVMTypeOf(llvmVal) }
            if (IsStructPtrType(llvmValType) && !valueCGType.IsCGTI()) {
                if (!IsReflectIntrinsicFunctionName(name)) {
                    callArgs.add(GetTrackedBasePtr(llvmVal) ??
                        unsafe { LLVMConstNull(CGType.GetRefType(GetLLVMContext())) })
                }
                if (unsafe { LLVMGetPointerAddressSpace(llvmValType) } != 1u32) {
                    let elementCGType = valueCGType.GetPointerElementType().getOrThrow()
                    llvmVal = CreateAddrSpaceCast(llvmVal,
                        unsafe { LLVMPointerType(elementCGType.GetLLVMType(), 1u32) })
                }
            }
            callArgs.add(llvmVal)
        }
        return callArgs
    }

    private func IsAtomicIntrinsicKind(kind: IntrinsicKind): Bool {
        return kind == IntrinsicKind.ATOMIC_LOAD ||
            kind == IntrinsicKind.ATOMIC_STORE ||
            kind == IntrinsicKind.ATOMIC_SWAP ||
            kind == IntrinsicKind.ATOMIC_COMPARE_AND_SWAP ||
            kind == IntrinsicKind.ATOMIC_FETCH_ADD ||
            kind == IntrinsicKind.ATOMIC_FETCH_SUB ||
            kind == IntrinsicKind.ATOMIC_FETCH_AND ||
            kind == IntrinsicKind.ATOMIC_FETCH_OR ||
            kind == IntrinsicKind.ATOMIC_FETCH_XOR
    }

    private func AtomicRMWOp(kind: IntrinsicKind): Option<UInt32> {
        return match (kind) {
            case IntrinsicKind.ATOMIC_SWAP => Some(0u32)
            case IntrinsicKind.ATOMIC_FETCH_ADD => Some(1u32)
            case IntrinsicKind.ATOMIC_FETCH_SUB => Some(2u32)
            case IntrinsicKind.ATOMIC_FETCH_AND => Some(3u32)
            case IntrinsicKind.ATOMIC_FETCH_OR => Some(5u32)
            case IntrinsicKind.ATOMIC_FETCH_XOR => Some(6u32)
            case _ => None
        }
    }

    private func CallAtomicIntrinsics(kind: IntrinsicKind, args: ArrayList<CGValue>, typeArgs: ArrayList<Type>,
        resultType: Option<Type>): LLVMValueRef {
        CJC_ASSERT(!args.isEmpty())
        let fieldPtr = CreateGEP(args[0], ArrayList<UInt64>([0u64]), name: "atomic.field").GetRawValue()
        CJC_ASSERT(typeArgs.size == 2)
        if (typeArgs[1].IsPrimitive()) {
            return CallAtomicPrimitiveIntrinsics(kind, args, fieldPtr)
        }
        let parameters = ArrayList<LLVMValueRef>()
        let isCompareAndSwap = kind == IntrinsicKind.ATOMIC_COMPARE_AND_SWAP
        var valueArgLimit = args.size - 1
        if (isCompareAndSwap) {
            valueArgLimit = args.size - 2
        }
        var argIdx: Int64 = 1
        while (argIdx < valueArgLimit) {
            parameters.add(args[argIdx].GetRawValue())
            argIdx++
        }
        parameters.add(args[0].GetRawValue())
        let fieldPtrType = unsafe { LLVMTypeOf(fieldPtr) }
        let fieldPtrAddrSpace = if (!fieldPtrType.isNull() &&
            unsafe { LLVMGetTypeKind(fieldPtrType) } == LLVM_POINTER_TYPE_KIND) {
            unsafe { LLVMGetPointerAddressSpace(fieldPtrType) }
        } else {
            0u32
        }
        let fixedFieldPtrType = unsafe { LLVMPointerType(CGType.GetRefType(GetLLVMContext()), fieldPtrAddrSpace) }
        parameters.add(CreateBitCast(fieldPtr, fixedFieldPtrType))
        if (isCompareAndSwap) {
            parameters.add(GetInt32(SEQ_CST_AS_INT32))
            parameters.add(GetInt32(SEQ_CST_AS_INT32))
        } else {
            parameters.add(GetInt32(SEQ_CST_AS_INT32))
        }
        if (kind == IntrinsicKind.ATOMIC_STORE || kind == IntrinsicKind.ATOMIC_SWAP) {
            let valueType = args[1].GetCGType().getOrThrow().GetOriginal()
            let valueCGType = CGType.GetOrCreate(cgMod, valueType)
            if (valueCGType.GetSize().isNone() && !valueType.IsGeneric()) {
                let payloadPtr = GetPayloadFromObject(args[1].GetRawValue())
                parameters[0] = CallGCRead(ArrayList<LLVMValueRef>([args[1].GetRawValue(), payloadPtr]))
            }
        }
        let result = CallMappedLLVMIntrinsic(kind, parameters, ArrayList<LLVMTypeRef>())
        if (let Some(retTy) <- resultType) {
            if (!retTy.IsGeneric()) {
                let retCGType = CGType.GetOrCreate(cgMod, retTy)
                if (retCGType.GetSize().isNone()) {
                    CJC_ASSERT(kind == IntrinsicKind.ATOMIC_LOAD || kind == IntrinsicKind.ATOMIC_SWAP)
                    let boxVal = CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>([CreateTypeInfo(retTy), GetInt32(8)]))
                    let payloadPtr = GetPayloadFromObject(boxVal)
                    CallGCWrite(result, boxVal, payloadPtr)
                    return boxVal
                }
            }
        }
        return result
    }

    private func CallAtomicPrimitiveIntrinsics(kind: IntrinsicKind, args: ArrayList<CGValue>,
        fieldPtr: LLVMValueRef): LLVMValueRef {
        var fieldType = unsafe { LLVMSelfhostGetGEPResultElementType(fieldPtr) }
        if (fieldType.isNull()) {
            fieldType = GetPointerElementType(unsafe { LLVMTypeOf(fieldPtr) })
        }
        if (kind == IntrinsicKind.ATOMIC_COMPARE_AND_SWAP) {
            let cas = unsafe {
                LLVMSelfhostCreateAtomicCmpXchg(builder.raw, fieldPtr, args[1].GetRawValue(), args[2].GetRawValue())
            }
            return CreateExtractValue(cas, 1u32)
        }
        if (let Some(op) <- AtomicRMWOp(kind)) {
            return unsafe { LLVMSelfhostCreateAtomicRMW(builder.raw, op, fieldPtr, args[1].GetRawValue()) }
        }
        let align = UInt32(unsafe { LLVMSelfhostGetPrimitiveSizeInBits(fieldType) })
        if (kind == IntrinsicKind.ATOMIC_STORE) {
            let _ = unsafe { LLVMSelfhostCreateAtomicStore(builder.raw, args[1].GetRawValue(), fieldPtr, align) }
            return LLVMNullValue()
        }
        if (kind == IntrinsicKind.ATOMIC_LOAD) {
            try (nameCString = unsafe { LibC.mallocCString("") }.asResource()) {
                return unsafe {
                    LLVMSelfhostCreateAtomicLoad(builder.raw, fieldType, fieldPtr, align, nameCString.value)
                }
            }
        }
        return LLVMNullValue()
    }

    private func GetRealUUIDForAutoEnvClass(obj: LLVMValueRef): LLVMValueRef {
        let i8PtrTy0 = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let i8PtrTy1 = CGType.GetRefType(GetLLVMContext())
        let blocks = CreateAndInsertBasicBlocks(ArrayList<String>(["judge", "wrapperClass", "end"]))
        CJC_ASSERT(blocks.size == 3)
        let judgeBB = blocks[0]
        let wrapperClassBB = blocks[1]
        let endBB = blocks[2]
        let newObjPtr = CreateEntryAlloca(i8PtrTy1, name: "obj")
        CreateStore(obj, newObjPtr)
        CreateBr(judgeBB)

        SetInsertPoint(judgeBB)
        let newObj0 = CreateLoad(i8PtrTy1, newObjPtr)
        let typeInfoValue = CreateBitCast(GetTypeInfoFromObject(newObj0), i8PtrTy0)
        let cgTi = CGValue(typeInfoValue,
            CGType.GetOrCreate(cgMod, CGType.GetRefTypeOfCHIRInt8(GetCGContext().GetCHIRBuilder())))
        let wrapperArgs = ArrayList<CGValue>()
        wrapperArgs.add(cgTi)
        let isWrapperClass = CallIntrinsicFunction(unsafe { LLVMInt1TypeInContext(GetLLVMContext().raw) },
            "CJ_MCC_IsWrapperClassForAutoEnv", wrapperArgs, ArrayList<String>())
        CreateCondBr(isWrapperClass, wrapperClassBB, endBB)

        SetInsertPoint(wrapperClassBB)
        let newObj1 = CreateLoad(i8PtrTy1, newObjPtr)
        let payload = GetPayloadFromObject(newObj1)
        let realAutoEnvClassPtrType = unsafe { LLVMPointerType(i8PtrTy1, 1u32) }
        let realAutoEnvClass = CreateGEP(i8PtrTy1, CreateBitCast(payload, realAutoEnvClassPtrType),
            ArrayList<LLVMValueRef>([GetInt32(2)]), name: "realAutoEnvClass")
        let loadInst = CallGCRead(ArrayList<LLVMValueRef>([newObj1, realAutoEnvClass]))
        CreateStore(loadInst, newObjPtr)
        CreateBr(judgeBB)

        SetInsertPoint(endBB)
        let newObj2 = CreateLoad(i8PtrTy1, newObjPtr)
        return GetUUIDFromTypeInfo(GetTypeInfoFromObject(newObj2))
    }

    public func GenerateCallExpectFunction(val: LLVMValueRef, expectVal: LLVMValueRef): LLVMValueRef {
        let valueType = unsafe { LLVMTypeOf(val) }
        let paramTypes = ArrayList<LLVMTypeRef>()
        paramTypes.add(valueType)
        paramTypes.add(valueType)
        let functionType = MakeFunctionType(valueType, paramTypes)
        let bitWidth = unsafe { LLVMGetIntTypeWidth(valueType) }
        let expectFunction = cgMod.GetOrInsertFunction("llvm.expect.i" + bitWidth.toString(), functionType)
        let args = ArrayList<LLVMValueRef>()
        args.add(val)
        args.add(expectVal)
        return CreateCall(expectFunction, functionType, args)
    }

    public func CallAssignGeneric(dest: LLVMValueRef, source: LLVMValueRef, typeInfo: LLVMValueRef): LLVMValueRef {
        return CallIntrinsicAssignGeneric(ArrayList<LLVMValueRef>([dest, source, typeInfo]))
    }

    public func CallIntrinsicAssignGeneric(parameters: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(parameters.size == 3)
        let args = ArrayList<LLVMValueRef>()
        args.add(parameters[0])
        args.add(parameters[1])
        args.add(CreateBitCast(parameters[2],
            unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) },
            name: "assign.generic.ti"))
        return CreateIntrinsicCallNoInvoke(ASSIGN_GENERIC_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args)
    }

    public func CallGCWrite(value: LLVMValueRef, baseObj: LLVMValueRef, fieldPtr: LLVMValueRef): LLVMValueRef {
        let gcRefType = CGType.GetRefType(GetLLVMContext())
        let gcRefPtrType = unsafe { LLVMPointerType(gcRefType, 1u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreatePointerCast(value, gcRefType, name: "gcwrite.val"))
        args.add(CreatePointerCast(baseObj, gcRefType, name: "gcwrite.base"))
        args.add(CreatePointerCast(fieldPtr, gcRefPtrType, name: "gcwrite.field"))
        CheckNoWriteBarrierRec()
        return CreateIntrinsicCallNoInvoke(GCWRITE_REF_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args)
    }

    public func CallGCWriteRef(value: LLVMValueRef, baseObject: LLVMValueRef, place: LLVMValueRef): LLVMValueRef {
        let refTy = CGType.GetRefType(GetLLVMContext())
        let refPlaceTy = unsafe { LLVMPointerType(refTy, 1u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreatePointerCast(value, refTy, name: "gcwrite.ref.value"))
        args.add(CreatePointerCast(baseObject, refTy, name: "gcwrite.ref.base"))
        args.add(CreatePointerCast(place, refPlaceTy, name: "gcwrite.ref.place"))
        CheckNoWriteBarrierRec()
        return CreateIntrinsicCallNoInvoke("llvm.cj.gcwrite.ref", ArrayList<LLVMTypeRef>(), args)
    }

    public func CallGCWriteStaticRef(value: LLVMValueRef, place: LLVMValueRef): LLVMValueRef {
        let args = ArrayList<LLVMValueRef>()
        args.add(value)
        args.add(place)
        CheckNoWriteBarrierRec()
        return CreateIntrinsicCallNoInvoke(GCWRITE_STATIC_REF_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args)
    }

    public func CallGCWriteStaticAgg(structType: LLVMTypeRef,
        args: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(args.size == 3)
        var call = LLVMNullValue()
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            call = unsafe {
                LLVMSelfhostCreateGCWriteStaticAgg(builder.raw, moduleHandle.raw, structType, args[0], args[1],
                    args[2], GetSizetLLVMType())
            }
        }
        if (call.isNull()) {
            return call
        }
        let aggTypeName = if (!structType.isNull() &&
            unsafe { LLVMGetTypeKind(structType) } == LLVM_STRUCT_TYPE_KIND) {
            LLVMCStringToString(unsafe { LLVMGetStructName(structType) }) ?? ""
        } else {
            ""
        }
        let metadata = LLVMCreateMDTupleFromString(GetLLVMContext(), aggTypeName)
        LLVMSetInstructionMetadata(GetLLVMContext(), call, "AggType", metadata)
        return call
    }

    public func CreateWriteBarrierForGlobalVariable(value: CGValue, globalVar: CGValue): LLVMValueRef {
        let valueType = value.GetCGType().getOrThrow()
        var inst = LLVMNullValue()
        if (valueType.IsStructPtrType()) {
            let structType = valueType.GetPointerElementType().getOrThrow().GetLLVMType()
            let size = unsafe {
                LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), cgMod.GetTypeSize(structType), 0)
            }
            inst = CallGCWriteStaticAgg(structType,
                ArrayList<LLVMValueRef>([globalVar.GetRawValue(), value.GetRawValue(), size]))
        } else {
            inst = CallGCWriteStaticRef(value.GetRawValue(), globalVar.GetRawValue())
        }
        if (!unsafe { LLVMIsAConstantPointerNull(value.GetRawValue()) }.isNull() && !inst.isNull()) {
            LLVMEraseInstructionMetadata(GetLLVMContext(), inst, "dbg")
        }
        return inst
    }

    public func CallGCWriteGeneric(baseObject: LLVMValueRef, dest: LLVMValueRef, source: LLVMValueRef,
        size: LLVMValueRef): LLVMValueRef {
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let basePtrTy = CGType.GetRefType(GetLLVMContext())
        let destPtrTy = unsafe { LLVMPointerType(i8Type, 1u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreatePointerCast(baseObject, basePtrTy, name: "gcwrite.generic.base"))
        args.add(CreatePointerCast(dest, destPtrTy, name: "gcwrite.generic.dest"))
        args.add(source)
        args.add(size)
        CheckNoWriteBarrierRec()
        return CreateIntrinsicCallNoInvoke(GCWRITE_GENERIC_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args)
    }

    public func CallGCWriteGenericPayload(dest: LLVMValueRef, source: LLVMValueRef,
        size: LLVMValueRef): LLVMValueRef {
        let args = ArrayList<LLVMValueRef>()
        args.add(dest)
        args.add(source)
        args.add(size)
        CheckNoWriteBarrierRec()
        return CreateIntrinsicCallNoInvoke(GCWRITE_GENERIC_PAYLOAD_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args)
    }

    public func CallGCReadRef(baseObject: LLVMValueRef, place: LLVMValueRef): LLVMValueRef {
        let refTy = CGType.GetRefType(GetLLVMContext())
        let refPlaceTy = unsafe { LLVMPointerType(refTy, 1u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreatePointerCast(baseObject, refTy, name: "gcread.ref.base"))
        args.add(CreatePointerCast(place, refPlaceTy, name: "gcread.ref.place"))
        return CreateIntrinsicCallNoInvoke("llvm.cj.gcread.ref", ArrayList<LLVMTypeRef>(), args, name: "gcread.ref")
    }

    public func CallGCRead(args: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(args.size == 2)
        return CallGCReadRef(args[0], args[1])
    }

    public func CallGCReadStaticRef(place: LLVMValueRef): LLVMValueRef {
        let args = ArrayList<LLVMValueRef>()
        args.add(place)
        return CreateIntrinsicCallNoInvoke(GCREAD_STATIC_REF_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args)
    }

    public func CallGCReadStaticAgg(structType: LLVMTypeRef, args: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(args.size == 3)
        var call = LLVMNullValue()
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            call = unsafe {
                LLVMSelfhostCreateGCReadStaticAgg(builder.raw, moduleHandle.raw, structType, args[0], args[1], args[2],
                    GetSizetLLVMType())
            }
        }
        let aggTypeName = if (!structType.isNull() && unsafe { LLVMGetTypeKind(structType) } == LLVM_STRUCT_TYPE_KIND) {
            LLVMCStringToString(unsafe { LLVMGetStructName(structType) }) ?? ""
        } else {
            ""
        }
        let metadata = LLVMCreateMDTupleFromString(GetLLVMContext(), aggTypeName)
        LLVMSetInstructionMetadata(GetLLVMContext(), call, "AggType", metadata)
        return call
    }

    public func CallGCReadGeneric(dest: LLVMValueRef, baseObject: LLVMValueRef, source: LLVMValueRef,
        size: LLVMValueRef): LLVMValueRef {
        let args = ArrayList<LLVMValueRef>()
        args.add(dest)
        args.add(CreatePointerCast(baseObject, CGType.GetRefType(GetLLVMContext()), name: "gcread.generic.base"))
        args.add(CreatePointerCast(source,
            unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 1u32) },
            name: "gcread.generic.source"))
        args.add(size)
        return CreateIntrinsicCallNoInvoke(GCREAD_GENERIC_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args)
    }

    public func CallGetFieldOffset(typeInfo: LLVMValueRef, index: UInt64, preOffset: UInt64): LLVMValueRef {
        let args = ArrayList<LLVMValueRef>()
        args.add(typeInfo)
        args.add(unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), index, 0) })
        args.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), preOffset, 0) })
        return CallIntrinsicGetFieldOffset(args)
    }

    public func CallIntrinsicGetFieldOffset(parameters: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(parameters.size == 2 || parameters.size == 3)
        CJC_ASSERT(unsafe { LLVMGetTypeKind(LLVMTypeOf(parameters[1])) } == LLVM_INTEGER_TYPE_KIND &&
            unsafe { LLVMGetIntTypeWidth(LLVMTypeOf(parameters[1])) } == 64u32)
        let fixedArgs = ArrayList<LLVMValueRef>()
        fixedArgs.add(CreatePointerCast(parameters[0],
            unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) },
            name: "field.offset.ti"))
        fixedArgs.add(parameters[1])
        if (parameters.size == 2) {
            fixedArgs.add(GetInt32(0))
        } else {
            fixedArgs.add(parameters[2])
        }
        return CreateIntrinsicCallNoInvoke(GET_FIELD_OFFSET_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), fixedArgs)
    }

    public func CallGCWriteStruct(baseObject: LLVMValueRef, dest: LLVMValueRef, source: LLVMValueRef,
        size: LLVMValueRef, aggTypeName: String): LLVMValueRef {
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let destPtrTy = unsafe { LLVMPointerType(i8Type, 1u32) }
        let sourceRawTy = unsafe { LLVMTypeOf(source) }
        let sourceAddrSpace = if (!sourceRawTy.isNull() && unsafe { LLVMGetTypeKind(sourceRawTy) } == 12) {
            unsafe { LLVMGetPointerAddressSpace(sourceRawTy) }
        } else {
            0u32
        }
        let sourcePtrTy = unsafe { LLVMPointerType(i8Type, sourceAddrSpace) }
        let i64Type = unsafe { LLVMInt64TypeInContext(GetLLVMContext().raw) }
        let overloadedTypes = ArrayList<LLVMTypeRef>()
        overloadedTypes.add(sourcePtrTy)
        overloadedTypes.add(i64Type)
        let args = ArrayList<LLVMValueRef>()
        args.add(CreatePointerCast(baseObject, CGType.GetRefType(GetLLVMContext()), name: "gcwrite.struct.base"))
        args.add(CreatePointerCast(dest, destPtrTy, name: "gcwrite.struct.dest"))
        args.add(CreatePointerCast(source, sourcePtrTy, name: "gcwrite.struct.source"))
        args.add(size)
        CheckNoWriteBarrierRec()
        let call = CreateIntrinsicCallNoInvoke("llvm.cj.gcwrite.struct", overloadedTypes, args)
        let metadata = LLVMCreateMDTupleFromString(GetLLVMContext(), aggTypeName)
        LLVMSetInstructionMetadata(GetLLVMContext(), call, "AggType", metadata)
        return call
    }

    public func CallGCWriteAgg(structType: LLVMTypeRef, args: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(args.size == 4)
        let sizeValue = args[3]
        let sizeType = unsafe { LLVMTypeOf(sizeValue) }
        if (!sizeType.isNull() && unsafe { LLVMGetTypeKind(sizeType) } == 8 &&
            unsafe { LLVMIsAInstruction(sizeValue) }.isNull() && unsafe { LLVMIsAArgument(sizeValue) }.isNull() &&
            unsafe { LLVMConstIntGetZExtValue(sizeValue) } == 0u64) {
            return LLVMNullValue()
        }
        CheckNoWriteBarrierRec()
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let destPtrTy = unsafe { LLVMPointerType(i8Type, 1u32) }
        let sourceRawTy = unsafe { LLVMTypeOf(args[2]) }
        let sourceAddrSpace = if (!sourceRawTy.isNull() && unsafe { LLVMGetTypeKind(sourceRawTy) } == 12) {
            unsafe { LLVMGetPointerAddressSpace(sourceRawTy) }
        } else {
            0u32
        }
        let sourcePtrTy = unsafe { LLVMPointerType(i8Type, sourceAddrSpace) }
        let i64Type = unsafe { LLVMInt64TypeInContext(GetLLVMContext().raw) }
        let overloadedTypes = ArrayList<LLVMTypeRef>()
        overloadedTypes.add(sourcePtrTy)
        overloadedTypes.add(i64Type)
        let fixedArgs = ArrayList<LLVMValueRef>()
        fixedArgs.add(CreatePointerCast(args[0], CGType.GetRefType(GetLLVMContext()), name: "gcwrite.agg.base"))
        fixedArgs.add(CreatePointerCast(args[1], destPtrTy, name: "gcwrite.agg.dest"))
        fixedArgs.add(CreatePointerCast(args[2], sourcePtrTy, name: "gcwrite.agg.source"))
        fixedArgs.add(CreateZExtOrTrunc(sizeValue, i64Type, name: "gcwrite.agg.size"))
        let call = CreateIntrinsicCallNoInvoke("llvm.cj.gcwrite.struct", overloadedTypes, fixedArgs)
        let aggTypeName = if (!structType.isNull() && unsafe { LLVMGetTypeKind(structType) } == LLVM_STRUCT_TYPE_KIND) {
            LLVMCStringToString(unsafe { LLVMGetStructName(structType) }) ?? ""
        } else {
            ""
        }
        let metadata = LLVMCreateMDTupleFromString(GetLLVMContext(), aggTypeName)
        LLVMSetInstructionMetadata(GetLLVMContext(), call, "AggType", metadata)
        return call
    }

    public func CallGCReadStruct(dest: LLVMValueRef, baseObject: LLVMValueRef, source: LLVMValueRef,
        size: LLVMValueRef, aggTypeName: String): LLVMValueRef {
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let destRawTy = unsafe { LLVMTypeOf(dest) }
        let destAddrSpace = if (!destRawTy.isNull() && unsafe { LLVMGetTypeKind(destRawTy) } == 12) {
            unsafe { LLVMGetPointerAddressSpace(destRawTy) }
        } else {
            0u32
        }
        let destPtrTy = unsafe { LLVMPointerType(i8Type, destAddrSpace) }
        let sourcePtrTy = unsafe { LLVMPointerType(i8Type, 1u32) }
        let i64Type = unsafe { LLVMInt64TypeInContext(GetLLVMContext().raw) }
        let overloadedTypes = ArrayList<LLVMTypeRef>()
        overloadedTypes.add(i64Type)
        let args = ArrayList<LLVMValueRef>()
        args.add(CreatePointerCast(dest, destPtrTy, name: "gcread.struct.dest"))
        args.add(CreatePointerCast(baseObject, CGType.GetRefType(GetLLVMContext()), name: "gcread.struct.base"))
        args.add(CreatePointerCast(source, sourcePtrTy, name: "gcread.struct.source"))
        args.add(size)
        let call = CreateIntrinsicCallNoInvoke("llvm.cj.gcread.struct", overloadedTypes, args)
        let metadata = LLVMCreateMDTupleFromString(GetLLVMContext(), aggTypeName)
        LLVMSetInstructionMetadata(GetLLVMContext(), call, "AggType", metadata)
        return call
    }

    public func CallGCReadAgg(structType: LLVMTypeRef, args: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(args.size == 4)
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let destRawTy = unsafe { LLVMTypeOf(args[0]) }
        let destAddrSpace = if (!destRawTy.isNull() && unsafe { LLVMGetTypeKind(destRawTy) } == LLVM_POINTER_TYPE_KIND) {
            unsafe { LLVMGetPointerAddressSpace(destRawTy) }
        } else {
            0u32
        }
        let destPtrTy = unsafe { LLVMPointerType(i8Type, destAddrSpace) }
        let sourceRawTy = unsafe { LLVMTypeOf(args[2]) }
        let sourceAddrSpace = if (!sourceRawTy.isNull() &&
            unsafe { LLVMGetTypeKind(sourceRawTy) } == LLVM_POINTER_TYPE_KIND) {
            unsafe { LLVMGetPointerAddressSpace(sourceRawTy) }
        } else {
            0u32
        }
        let sourcePtrTy = unsafe { LLVMPointerType(i8Type, sourceAddrSpace) }
        let i64Type = unsafe { LLVMInt64TypeInContext(GetLLVMContext().raw) }
        let overloadedTypes = ArrayList<LLVMTypeRef>()
        overloadedTypes.add(i64Type)
        let fixedArgs = ArrayList<LLVMValueRef>()
        fixedArgs.add(CreatePointerCast(args[0], destPtrTy, name: "gcread.agg.dest"))
        fixedArgs.add(CreatePointerCast(args[1], CGType.GetRefType(GetLLVMContext()), name: "gcread.agg.base"))
        fixedArgs.add(CreatePointerCast(args[2], sourcePtrTy, name: "gcread.agg.source"))
        fixedArgs.add(CreateZExtOrTrunc(args[3], i64Type, name: "gcread.agg.size"))
        let call = CreateIntrinsicCallNoInvoke("llvm.cj.gcread.struct", overloadedTypes, fixedArgs)
        let aggTypeName = if (!structType.isNull() && unsafe { LLVMGetTypeKind(structType) } == LLVM_STRUCT_TYPE_KIND) {
            LLVMCStringToString(unsafe { LLVMGetStructName(structType) }) ?? ""
        } else {
            ""
        }
        let metadata = LLVMCreateMDTupleFromString(GetLLVMContext(), aggTypeName)
        LLVMSetInstructionMetadata(GetLLVMContext(), call, "AggType", metadata)
        return call
    }

    public func CreateGEP(elementType: LLVMTypeRef, pointer: LLVMValueRef, indices: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (indices.isEmpty()) {
                return pointer
            }
            try (idxPtr = LibC.malloc<LLVMValueRef>(count: indices.size).asResource()) {
                var idx: Int64 = 0
                while (idx < indices.size) {
                    unsafe { (idxPtr.value + idx).write(indices[idx]) }
                    idx++
                }
                result = unsafe { LLVMBuildGEP2(builder.raw, elementType, pointer, idxPtr.value, UInt32(indices.size), nameCString.value) }
            }
        }
        PropagateBasePtr(pointer, result)
        return result
    }

    public func CreateInBoundsGEP(elementType: LLVMTypeRef, pointer: LLVMValueRef, indices: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (indices.isEmpty()) {
                return pointer
            }
            try (idxPtr = LibC.malloc<LLVMValueRef>(count: indices.size).asResource()) {
                var idx: Int64 = 0
                while (idx < indices.size) {
                    unsafe { (idxPtr.value + idx).write(indices[idx]) }
                    idx++
                }
                result = unsafe {
                    LLVMBuildInBoundsGEP2(builder.raw, elementType, pointer, idxPtr.value, UInt32(indices.size),
                        nameCString.value)
                }
            }
        }
        PropagateBasePtr(pointer, result)
        return result
    }

    public func CreateStructGEP(elementType: LLVMTypeRef, pointer: LLVMValueRef, index: UInt32,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildStructGEP2(builder.raw, elementType, pointer, index, nameCString.value) }
        }
        PropagateBasePtr(pointer, result)
        return result
    }

    public func CreateGEP(cgVal: CGValue, idxList: ArrayList<UInt64>, name!: String = ""): CGValue {
        var ret = cgVal.GetRawValue()
        let pointerCGType = cgVal.GetCGType() ?? throw IllegalArgumentException("expected CGValue with CGType")
        var eleType = pointerCGType.GetPointerElementType() ?? throw IllegalArgumentException("expected pointer CGType")
        var basePtr = GetTrackedBasePtr(ret)
        var hasSkippedTypeInfo = basePtr.isSome() && !eleType.IsReference()
        let retType = unsafe { LLVMTypeOf(ret) }
        if (basePtr.isNone() && eleType.GetSize().isNone() && !retType.isNull() &&
            unsafe { LLVMGetTypeKind(retType) } == LLVM_POINTER_TYPE_KIND &&
            unsafe { LLVMGetPointerAddressSpace(retType) } == 1u32) {
            basePtr = Some(ret)
        }
        for (idx in idxList) {
            if (eleType.IsReference() || eleType.IsOptionLikeRef()) {
                basePtr = Some(ret)
            }
            let offsetForAutoEnv = if (IsAutoEnvType(eleType.GetOriginal())) { 2u64 } else { 0u64 }
            if (chirExpr.isSome() && eleType.GetSize().isNone()) {
                let typeInfo = CreateTypeInfo(eleType.GetOriginal())
                let preOffset = if (eleType.GetOriginal().IsRawArray()) { 8u64 } else { 0u64 }
                var offset = CallGetFieldOffset(typeInfo, idx + offsetForAutoEnv, preOffset)
                var skipPayloadOffset = false
                if (let Some(currentFunction) <- cgFunction) {
                    let rawFunction = currentFunction.GetRawFunction()
                    if (HasAttributeAtIndex(rawFunction, UInt32.Max, HAS_WITH_TI_WRAPPER_ATTR) ||
                        HasAttributeAtIndex(rawFunction, UInt32.Max, THIS_PARAM_HAS_BP)) {
                        if (let Some(currentExpr) <- chirExpr) {
                            if (let Some(topLevelFunc) <- currentExpr.GetTopLevelFunc()) {
                                if (topLevelFunc.GetNumOfParams() > 0) {
                                    if (let Some(thisParam) <- cgMod.GetMappedValue(topLevelFunc.GetParam(0))) {
                                        let rawThisParam = thisParam.GetRawValue()
                                        skipPayloadOffset = !rawThisParam.isNull() &&
                                            rawThisParam.toUIntNative() == ret.toUIntNative()
                                    }
                                }
                            }
                        }
                    }
                }
                if (!skipPayloadOffset && !hasSkippedTypeInfo) {
                    let payloadOffset = unsafe {
                        LLVMConstInt(LLVMTypeOf(offset), GetPayloadOffset(), 0)
                    }
                    offset = CreateBinary(ExprKind.ADD, offset, payloadOffset)
                    hasSkippedTypeInfo = true
                }
                let indices = ArrayList<LLVMValueRef>()
                indices.add(offset)
                ret = CreateInBoundsGEP(unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }, ret, indices,
                    name: name)
            } else if (let Some(classCGType) <- (eleType as CGClassType)) {
                ret = GetPayloadFromObject(ret)
                let layoutType = classCGType.GetLayoutType()
                ret = CreateBitCast(ret, unsafe { LLVMPointerType(layoutType, 1u32) }, name: name + ".payload")
                ret = CreateStructGEP(layoutType, ret, UInt32(idx + offsetForAutoEnv), name: name)
            } else if (let Some(arrayCGType) <- (eleType as CGArrayType)) {
                let rawArrayTy = (arrayCGType.GetOriginal() as RawArrayType) ??
                    throw IllegalArgumentException("expected raw array type")
                ret = GetArrayElementAddr(rawArrayTy, ret, GetInt64(Int64(idx)), false)
            } else {
                let retRawType = unsafe { LLVMTypeOf(ret) }
                let retAddrspace = if (!retRawType.isNull() &&
                    unsafe { LLVMGetTypeKind(retRawType) } == LLVM_POINTER_TYPE_KIND) {
                    unsafe { LLVMGetPointerAddressSpace(retRawType) }
                } else {
                    0u32
                }
                ret = CreateBitCast(ret, unsafe { LLVMPointerType(eleType.GetLLVMType(), retAddrspace) },
                    name: name + ".base")
                ret = CreateStructGEP(eleType.GetLLVMType(), ret, UInt32(idx), name: name)
            }
            if (let Some(arrayCGTypeForUpdate) <- (eleType as CGArrayType)) {
                eleType = arrayCGTypeForUpdate.GetElementCGType() ??
                    throw IllegalArgumentException("expected array element CGType")
            } else {
                eleType = eleType.GetContainedTypeAt(idx + offsetForAutoEnv)
                if (!eleType.GetOriginal().IsGeneric()) {
                    let retRawType = unsafe { LLVMTypeOf(ret) }
                    let retAddrspace = if (!retRawType.isNull() &&
                        unsafe { LLVMGetTypeKind(retRawType) } == LLVM_POINTER_TYPE_KIND) {
                        unsafe { LLVMGetPointerAddressSpace(retRawType) }
                    } else {
                        0u32
                    }
                    ret = CreateBitCast(ret, unsafe { LLVMPointerType(eleType.GetLLVMType(), retAddrspace) },
                        name: name + ".cast")
                }
            }
            if (let Some(trackedBase) <- basePtr) {
                TrackBasePtr(ret, trackedBase)
            }
        }
        let refTy = GetCGContext().GetCHIRBuilder().context.GetRefTy(eleType.GetOriginal())
        return CGValue(ret, CGType.GetOrCreate(cgMod, refTy))
    }

    public func GetPayloadFromObject(objectValue: LLVMValueRef): LLVMValueRef {
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let objectSlotType = unsafe { LLVMPointerType(i8PtrType, 1u32) }
        let objectSlot = CreateBitCast(objectValue, objectSlotType, name: "obj.payload.slot")
        let indices = ArrayList<LLVMValueRef>()
        indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), 1u64, 0) })
        let payload = CreateGEP(i8PtrType, objectSlot, indices, name: "obj.payload")
        TrackBasePtr(payload, objectValue)
        return payload
    }

    public func CallIntrinsicNull(): LLVMValueRef {
        return unsafe { LLVMConstNull(CGType.GetRefType(GetLLVMContext())) }
    }

    public func CallIntrinsicIsNull(value: LLVMValueRef): LLVMValueRef {
        return CreateICmp(LLVMIntPredicate.EQ, value, CallIntrinsicNull())
    }

    public func CallIntrinsicIsNonNull(value: LLVMValueRef): LLVMValueRef {
        return CreateICmp(LLVMIntPredicate.NE, value, CallIntrinsicNull())
    }

    public func CreateConstGEP1_32(elementType: LLVMTypeRef, pointer: LLVMValueRef, index: UInt32,
        name!: String = ""): LLVMValueRef {
        return CreateGEP(elementType, pointer,
            ArrayList<LLVMValueRef>([unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw),
                UInt64(index), 0) }]), name: name)
    }

    public func CreateEnumGEP(field: Field): LLVMValueRef {
        CJC_ASSERT(field.GetPath().size == 1)
        if (field.GetPath()[0] == 0u64) {
            return GetEnumTag(field)
        }
        let resultValue = GetEnumAssociatedValue(field)
        if (let Some(enumCGType) <- (CGType.GetOrCreate(cgMod,
            field.GetResult().getOrThrow().GetType().getOrThrow()) as CGEnumType)) {
            if (enumCGType.IsOptionLikeRef()) {
                LLVMSetInstructionMetadata(GetLLVMContext(), resultValue, "untrusted_ref",
                    LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>()))
            }
        }
        return resultValue
    }

    public func GetEnumTag(field: Field): LLVMValueRef {
        let cgEnum = cgMod.GetMappedValue(field.GetBase()).getOrThrow()
        CJC_ASSERT(field.GetBase().GetType().getOrThrow().IsEnum())
        let enumValue = cgEnum.GetRawValue()
        let chirType = (field.GetBase().GetType().getOrThrow() as EnumType).getOrThrow()
        let cgEnumType = (CGType.GetOrCreate(cgMod, chirType) as CGEnumType).getOrThrow()
        let enumKind = cgEnumType.GetCGEnumTypeKind()
        if (enumKind == CGEnumTypeKind.NON_EXHAUSTIVE_UNASSOCIATED ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_UNASSOCIATED) {
            return enumValue
        }
        if (enumKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_OTHER) {
            let payload = GetPayloadFromObject(enumValue)
            let tagType = CGType.GetOrCreate(cgMod, field.GetResult().getOrThrow().GetType().getOrThrow()).GetLLVMType()
            return CreateLoad(tagType, CreateBitCast(payload, unsafe { LLVMPointerType(tagType, 1u32) }))
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF) {
            let tagType = CGType.GetOrCreate(cgMod, field.GetResult().getOrThrow().GetType().getOrThrow()).GetLLVMType()
            return CreateLoad(tagType, CreateBitCast(enumValue, unsafe { LLVMPointerType(tagType, 0u32) }))
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            let i1Type = unsafe { LLVMInt1TypeInContext(GetLLVMContext().raw) }
            let payload = GetPayloadFromObject(enumValue)
            let blocks = CreateAndInsertBasicBlocks(ArrayList<String>(["ref", "nonRef", "end"]))
            if (blocks.size != 3) {
                return LLVMNullValue()
            }
            CreateCondBr(CreateTypeInfoIsReferenceCall(chirType.GetTypeArgs()[0]), blocks[0], blocks[1])
            SetInsertPoint(blocks[0])
            let refPayload = CallGCRead(ArrayList<LLVMValueRef>([enumValue, payload]))
            let refResult = if (cgEnumType.IsAntiOptionLike()) {
                CallIntrinsicIsNonNull(refPayload)
            } else {
                CallIntrinsicIsNull(refPayload)
            }
            CreateBr(blocks[2])
            SetInsertPoint(blocks[1])
            let nonRefResult = CreateLoad(i1Type, CreateBitCast(payload, unsafe { LLVMPointerType(i1Type, 1u32) }))
            CreateBr(blocks[2])
            SetInsertPoint(blocks[2])
            let phi = CreatePHI(i1Type)
            AddIncoming(phi, ArrayList<LLVMValueRef>([refResult, nonRefResult]),
                ArrayList<LLVMBasicBlockRef>([blocks[0], blocks[1]]))
            return phi
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            return if (cgEnumType.IsAntiOptionLike()) {
                CallIntrinsicIsNonNull(cgEnum.GetRawValue())
            } else {
                CallIntrinsicIsNull(cgEnum.GetRawValue())
            }
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            let i1Type = unsafe { LLVMInt1TypeInContext(GetLLVMContext().raw) }
            if (cgEnumType.GetSize().isSome()) {
                let enumType = cgEnumType.GetLLVMType()
                let addrSpace = GetPointerAddressSpace(enumValue) ?? 0u32
                let casted = CreateBitCast(enumValue, unsafe { LLVMPointerType(enumType, addrSpace) })
                return CreateLoad(i1Type, CreateStructGEP(enumType, casted, 0u32))
            }
            let casted = CreateBitCast(GetPayloadFromObject(enumValue), unsafe { LLVMPointerType(i1Type, 1u32) })
            return CreateLoad(i1Type, casted)
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE) {
            return GetInt32(0)
        }
        CJC_ASSERT(false)
        return LLVMNullValue()
    }

    private func GetOptionLikeNonRefAssociatedValue(enumType: Type, associatedValueType: Type,
        enumValueWithTI: LLVMValueRef): LLVMValueRef {
        let associatedValueTypeTI = CreateTypeInfo(associatedValueType)
        let sizeOfAssociatedValueType = GetLayoutSize_32(associatedValueType)
        let nonRefResult = CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>(
            [associatedValueTypeTI, sizeOfAssociatedValueType]))
        let typeInfo = CreateTypeInfo(enumType)
        let associatedValOffset = CallIntrinsicGetFieldOffset(ArrayList<LLVMValueRef>(
            [typeInfo, GetInt64(1), GetInt32(8)]))
        let associatedValPtr = CreateInBoundsGEP(unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) },
            enumValueWithTI, ArrayList<LLVMValueRef>([associatedValOffset]))
        CallGCReadGeneric(nonRefResult, enumValueWithTI, associatedValPtr, sizeOfAssociatedValueType)
        return nonRefResult
    }

    private func GetCommonEnumAssociatedValue(field: Field, cgEnum: CGValue): LLVMValueRef {
        let elemTypes = ArrayList<LLVMTypeRef>()
        var isSized = true
        let args = field.GetBase().GetType().getOrThrow().GetTypeArgs()
        var argIdx: Int64 = 0
        while (argIdx < args.size) {
            let cgType = CGType.GetOrCreate(cgMod, args[argIdx])
            if (cgType.GetSize().isSome()) {
                elemTypes.add(cgType.GetLLVMType())
            } else {
                isSized = false
                break
            }
            argIdx++
        }
        let enumVal = cgEnum.GetRawValue()
        let associatedValIdx = UInt32(field.GetPath()[0])
        if (isSized) {
            let layoutType = CreateAnonymousStructType(elemTypes)
            let castedEnumValPtr = CreateBitCast(GetPayloadFromObject(enumVal),
                unsafe { LLVMPointerType(layoutType, 1u32) })
            let fieldPtr = CreateStructGEP(layoutType, castedEnumValPtr, associatedValIdx)
            TrackBasePtr(fieldPtr, enumVal)
            return CreateLoad(elemTypes[Int64(associatedValIdx)], fieldPtr)
        }
        let typeCastExpr = ((field.GetBase() as LocalVar).getOrThrow().GetExpr().getOrThrow() as TypeCast).getOrThrow()
        let chirEnumType = (typeCastExpr.GetSourceTy().getOrThrow() as EnumType).getOrThrow()
        CJC_ASSERT(typeCastExpr.GetResult().getOrThrow().GetEnumCaseIndex().isSome())
        let typeArgs = ArrayList<Type>()
        for (typeArg in GetGenericArgsFromCHIRType(chirEnumType.GetEnumDef().GetType().getOrThrow())) {
            typeArgs.add(GetTypeInnerType(typeCastExpr.GetSourceValue().GetType().getOrThrow(), typeArg))
        }
        let fieldType = field.GetResult().getOrThrow().GetType().getOrThrow()
        let fieldAddrType = CGType.GetOrCreate(cgMod, GetCGContext().GetCHIRBuilder().context.GetRefTy(fieldType))
        let enumCaseTT = cgMod.GetOrCreateEnumCtorTIOrTT(chirEnumType,
            typeCastExpr.GetResult().getOrThrow().GetEnumCaseIndex().getOrThrow())
        let enumCaseTI = CallGetTypeInfoIntrinsic(ArrayList<LLVMValueRef>(
            [enumCaseTT, GetInt32(typeArgs.size), CreateTypeInfoArray(typeArgs)]))
        var fieldOffset = CallIntrinsicGetFieldOffset(ArrayList<LLVMValueRef>(
            [enumCaseTI, GetInt64(Int64(associatedValIdx))]))
        fieldOffset = CreateBinary(ExprKind.ADD, fieldOffset,
            unsafe { LLVMConstInt(LLVMTypeOf(fieldOffset), GetPayloadOffset(), 0) })
        var fieldAddr = CreateInBoundsGEP(unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) },
            enumVal, ArrayList<LLVMValueRef>([fieldOffset]))
        if (!fieldType.IsGeneric()) {
            let fieldCGType = CGType.GetOrCreate(cgMod, fieldType)
            let addrSpace = GetPointerAddressSpace(fieldAddr) ?? 0u32
            fieldAddr = CreateBitCast(fieldAddr, unsafe { LLVMPointerType(fieldCGType.GetLLVMType(), addrSpace) })
        }
        TrackBasePtr(fieldAddr, enumVal)
        return CreateLoad(CGValue(fieldAddr, fieldAddrType))
    }

    private func GetZeroSizeEnumAssociatedValue(field: Field, cgEnum: CGValue): LLVMValueRef {
        let fieldType = field.GetResult().getOrThrow().GetType().getOrThrow()
        let fieldAddrType = CGType.GetOrCreate(cgMod, GetCGContext().GetCHIRBuilder().context.GetRefTy(fieldType))
        return CreateLoad(CGValue(cgEnum.GetRawValue(), fieldAddrType))
    }

    private func GetAssociatedNonRefEnumAssociatedValue(field: Field, cgEnum: CGValue): LLVMValueRef {
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let associatedValIdx = UInt32(field.GetPath()[0])
        let args = field.GetBase().GetType().getOrThrow().GetTypeArgs()
        CJC_ASSERT(Int64(associatedValIdx) < args.size)
        let fieldTypes = ArrayList<Type>()
        for (arg in args) {
            fieldTypes.add(arg)
        }
        let fieldPtr = if (CGEnumType.NeedAndroidArm32AlignedEnumLayout(GetCGContext().GetCompileOptions().target)) {
            let layoutType = CGEnumType.GetAndroidArm32AssociatedNonRefLayoutType(cgMod, fieldTypes)
            let casted = CreateBitCast(cgEnum.GetRawValue(), unsafe { LLVMPointerType(layoutType, 0u32) })
            CreateStructGEP(layoutType, casted, associatedValIdx, name: "enum.field.ptr")
        } else {
            let layout = CGEnumType.ComputeAssociatedNonRefLayout(cgMod, fieldTypes)
            let casted = CreateBitCast(cgEnum.GetRawValue(), unsafe { LLVMPointerType(i8Type, 0u32) })
            CreateConstGEP1_32(i8Type, casted, layout.offsets[Int64(associatedValIdx)], name: "enum.field.ptr")
        }
        let retLLVMType = CGType.GetOrCreate(cgMod, field.GetResult().getOrThrow().GetType().getOrThrow()).GetLLVMType()
        return CreateLoad(retLLVMType, CreateBitCast(fieldPtr, unsafe { LLVMPointerType(retLLVMType, 0u32) }))
    }

    public func GetEnumAssociatedValue(field: Field): LLVMValueRef {
        CJC_ASSERT(field.GetBase().IsLocalVar())
        let typeCast = ((field.GetBase() as LocalVar).getOrThrow().GetExpr().getOrThrow() as TypeCast).getOrThrow()
        let cgEnumType = (CGType.GetOrCreate(cgMod,
            typeCast.GetSourceValue().GetType().getOrThrow()) as CGEnumType).getOrThrow()
        let cgEnum = cgMod.GetMappedValue(field.GetBase()).getOrThrow()
        CJC_ASSERT(field.GetPath().size == 1)
        let index = field.GetPath()[0]
        let enumKind = cgEnumType.GetCGEnumTypeKind()
        if (enumKind == CGEnumTypeKind.NON_EXHAUSTIVE_ASSOCIATED ||
            enumKind == CGEnumTypeKind.EXHAUSTIVE_OTHER) {
            return GetCommonEnumAssociatedValue(field, cgEnum)
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ZERO_SIZE) {
            return GetZeroSizeEnumAssociatedValue(field, cgEnum)
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_NONREF) {
            return GetAssociatedNonRefEnumAssociatedValue(field, cgEnum)
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_T) {
            CJC_ASSERT(index == 1u64)
            let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 1u32) }
            let blocks = CreateAndInsertBasicBlocks(ArrayList<String>(["ref", "nonRef", "end"]))
            if (blocks.size != 3) {
                return LLVMNullValue()
            }
            CreateCondBr(CreateTypeInfoIsReferenceCall(cgEnumType.GetOriginal().GetTypeArgs()[0]),
                blocks[0], blocks[1])
            SetInsertPoint(blocks[0])
            let enumValue = cgEnum.GetRawValue()
            let payload = CreateBitCast(GetPayloadFromObject(enumValue), i8PtrType)
            let refResult = CallGCRead(ArrayList<LLVMValueRef>([enumValue, payload]))
            CreateBr(blocks[2])
            SetInsertPoint(blocks[1])
            let associatedValueType = field.GetResult().getOrThrow().GetType().getOrThrow()
            let nonRefResult = GetOptionLikeNonRefAssociatedValue(cgEnum.GetCGType().getOrThrow().GetOriginal(),
                associatedValueType, enumValue)
            CreateBr(blocks[2])
            SetInsertPoint(blocks[2])
            let phi = CreatePHI(i8PtrType)
            AddIncoming(phi, ArrayList<LLVMValueRef>([refResult, nonRefResult]),
                ArrayList<LLVMBasicBlockRef>([blocks[0], blocks[1]]))
            return phi
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_REF) {
            CJC_ASSERT(index == 1u64)
            let value = cgEnum.GetRawValue()
            cgMod.GetCGContext().AddNullableReference(value)
            return value
        }
        if (enumKind == CGEnumTypeKind.EXHAUSTIVE_ASSOCIATED_OPTION_LIKE_NONREF) {
            CJC_ASSERT(index == 1u64)
            if (cgEnumType.GetSize().isSome()) {
                let enumVal = cgEnum.GetRawValue()
                let enumType = cgEnumType.GetLLVMType()
                let addrSpace = GetPointerAddressSpace(enumVal) ?? 0u32
                let casted = CreateBitCast(enumVal, unsafe { LLVMPointerType(enumType, addrSpace) })
                let associatedLLVMType = CGType.GetOrCreate(cgMod,
                    field.GetResult().getOrThrow().GetType().getOrThrow()).GetLLVMType()
                return CreateLoad(associatedLLVMType, CreateStructGEP(enumType, casted, 1u32))
            }
            let associatedValueType = field.GetResult().getOrThrow().GetType().getOrThrow()
            return GetOptionLikeNonRefAssociatedValue(cgEnum.GetCGType().getOrThrow().GetOriginal(),
                associatedValueType, cgEnum.GetRawValue())
        }
        CJC_ASSERT(false)
        return LLVMNullValue()
    }

    public func CallArrayIntrinsicGetSize(array: LLVMValueRef): LLVMValueRef {
        let i64Type = unsafe { LLVMInt64TypeInContext(GetLLVMContext().raw) }
        let arrayBaseType = CGType.GetArrayBaseType(GetCGContext())
        let payloadPtr = CreateBitCast(GetPayloadFromObject(array),
            unsafe { LLVMPointerType(arrayBaseType, 1u32) }, name: "array.base")
        let ptrToArrayLen = CreateBitCast(payloadPtr, unsafe { LLVMPointerType(i64Type, 1u32) },
            name: "array.len.ptr")
        return CreateLoad(i64Type, ptrToArrayLen, name: "array.len")
    }

    public func CallArrayIntrinsicIndexCheck(array: LLVMValueRef, index: LLVMValueRef): Unit {
        CallIntrinsicIndexCheck(CallArrayIntrinsicGetSize(array), index)
    }

    public func CallIntrinsicIndexCheck(len: LLVMValueRef, index: LLVMValueRef): Unit {
        let indexI64 = CastIntegerToInt64(index)
        let lenI64 = CastIntegerToInt64(len)
        let zero = GetInt64(0)
        let cmpZero = CreateICmp(LLVMIntPredicate.SLT, indexI64, zero, name: "arr.idx.lt.zero")
        let cmpLen = CreateICmp(LLVMIntPredicate.SGE, indexI64, lenI64, name: "arr.idx.ge.len")
        let isThrow = CreateBinary(ExprKind.OR, cmpZero, cmpLen, name: "arr.idx.throw")
        let blocks = CreateAndInsertBasicBlocks(ArrayList<String>(["arr.if.then", "arr.if.else"]))
        if (blocks.size < 2) {
            return
        }
        CreateCondBr(isThrow, blocks[0], blocks[1])
        SetInsertPoint(blocks[0])
        CreateOutOfBoundException()
        let _ = CreateUnreachable()
        SetInsertPoint(blocks[1])
    }

    public func GetArrayElementAddr(rawArrayTy: RawArrayType, array: LLVMValueRef, index: LLVMValueRef,
        isChecked: Bool): LLVMValueRef {
        if (isChecked) {
            CallArrayIntrinsicIndexCheck(array, index)
        }
        let arrayLayoutType = CGArrayType.GenerateArrayLayoutType(cgMod, rawArrayTy)
        let payload = GetPayloadFromObject(array)
        let typedPayload = CreateBitCast(payload, unsafe { LLVMPointerType(arrayLayoutType, 1u32) },
            name: "arr.payload")
        let indices = ArrayList<LLVMValueRef>()
        indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), 0u64, 0) })
        indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), 1u64, 0) })
        indices.add(CastIntegerToInt64(index))
        return CreateInBoundsGEP(arrayLayoutType, typedPayload, indices, name: "arr.idx.get.gep")
    }

    public func CallArrayIntrinsicGet(rawArrayTy: RawArrayType, array: LLVMValueRef, index: LLVMValueRef,
        isChecked: Bool): LLVMValueRef {
        let elementCHIRType = rawArrayTy.GetElementType()
        let elementCGType = CGType.GetOrCreate(cgMod, elementCHIRType)
        let elementType = elementCGType.GetLLVMType()
        let rawArrayCGType = CGType.GetOrCreate(cgMod, rawArrayTy)
        var elementPtr = LLVMNullValue()
        if (rawArrayCGType.GetSize().isNone()) {
            var offset = CreateBinary(ExprKind.MUL, GetSize_64(elementCHIRType), index)
            offset = CreateBinary(ExprKind.ADD, offset, GetInt64(Int64(GetPayloadOffset() + 8u64)))
            elementPtr = CreateInBoundsGEP(unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }, array,
                ArrayList<LLVMValueRef>([offset]))
            let arrayAddressSpace = unsafe { LLVMGetPointerAddressSpace(LLVMTypeOf(array)) }
            elementPtr = CreateBitCast(elementPtr, unsafe { LLVMPointerType(elementType, arrayAddressSpace) })
            GetCGContext().SetBasePtr(elementPtr, array)
        } else {
            elementPtr = GetArrayElementAddr(rawArrayTy, array, index, isChecked)
        }
        let loaded = CreateLoad(elementType, elementPtr, name: "arr.idx.get")
        if (elementCHIRType.IsEnum()) {
            LLVMSetInstructionMetadata(GetLLVMContext(), loaded, "untrusted_ref",
                LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>()))
        }
        return loaded
    }

    public func CallArrayIntrinsicSet(rawArrayTy: RawArrayType, array: LLVMValueRef, index: LLVMValueRef,
        elementValue: CGValue, isChecked: Bool): LLVMValueRef {
        let elementCHIRType = rawArrayTy.GetElementType()
        let elementCGType = CGType.GetOrCreate(cgMod, elementCHIRType)
        let elementType = elementCGType.GetLLVMType()
        let rawArrayCGType = CGType.GetOrCreate(cgMod, rawArrayTy)
        if (rawArrayCGType.GetSize().isNone()) {
            var offset = CreateBinary(ExprKind.MUL, GetSize_64(elementCHIRType), index)
            offset = CreateBinary(ExprKind.ADD, offset, GetInt64(Int64(GetPayloadOffset() + 8u64)))
            var fieldAddr = CreateInBoundsGEP(unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }, array,
                ArrayList<LLVMValueRef>([offset]))
            let arrayAddressSpace = unsafe { LLVMGetPointerAddressSpace(LLVMTypeOf(array)) }
            fieldAddr = CreateBitCast(fieldAddr, unsafe { LLVMPointerType(elementType, arrayAddressSpace) })
            GetCGContext().SetBasePtr(fieldAddr, array)
            let fieldAddrCGType = CGType.GetOrCreate(cgMod,
                GetCGContext().GetCHIRBuilder().context.GetRefTy(elementCHIRType))
            return CreateStore(elementValue, CGValue(fieldAddr, fieldAddrCGType))
        }
        let rawValue = elementValue.GetRawValue()
        let elementPtr = GetArrayElementAddr(rawArrayTy, array, index, isChecked)
        if (unsafe { LLVMGetTypeKind(elementType) } == LLVM_STRUCT_TYPE_KIND) {
            let size = unsafe {
                LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw),
                    cgMod.GetTypeSize(elementType), 0)
            }
            if (IsLLVMTypeContainsRef(elementType)) {
                return CallGCWriteAgg(elementType,
                    ArrayList<LLVMValueRef>([array, elementPtr, rawValue, size]))
            } else {
                let align = cgMod.GetABITypeAlignment(elementType)
                return CreateMemCpy(elementPtr, align, rawValue, align, size)
            }
        } else if (unsafe { LLVMGetTypeKind(elementType) } == LLVM_ARRAY_TYPE_KIND) {
            let size = unsafe {
                LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), cgMod.GetTypeSize(elementType), 0)
            }
            return CallGCWriteAgg(elementCGType.GetLayoutType(),
                ArrayList<LLVMValueRef>([array, elementPtr, rawValue, size]))
        } else if (elementType.toUIntNative() == CGType.GetRefType(GetLLVMContext()).toUIntNative()) {
            return CallGCWrite(rawValue, array, elementPtr)
        } else {
            return CreateStore(rawValue, elementPtr)
        }
    }

    public func CallArrayIntrinsicCopy(rawArrayTy: RawArrayType, srcArray: LLVMValueRef): LLVMValueRef {
        let srcLen = CallArrayIntrinsicGetSize(srcArray)
        let dstArray = AllocateArray(rawArrayTy, srcLen)
        if (dstArray.isNull()) {
            return LLVMNullValue()
        }
        CallArrayIntrinsicCopyTo(rawArrayTy, srcArray, dstArray, GetInt64(0), GetInt64(0), srcLen)
        return dstArray
    }

    public func CallArrayIntrinsicCopyTo(rawArrayTy: RawArrayType, srcArray: LLVMValueRef, dstArray: LLVMValueRef,
        srcStart: LLVMValueRef, dstStart: LLVMValueRef, copyLen: LLVMValueRef): LLVMValueRef {
        let elementSizeValue = GetRawArrayElementSizeValue(rawArrayTy)
        let copyLenI64 = CastIntegerToInt64(copyLen)
        let dataSize = CreateBinary(ExprKind.MUL, copyLenI64, elementSizeValue, name: "arr.data.len")
        let srcIndex = CreateBinary(ExprKind.MUL, CastIntegerToInt64(srcStart), elementSizeValue, name: "src.index")
        let dstIndex = CreateBinary(ExprKind.MUL, CastIntegerToInt64(dstStart), elementSizeValue, name: "dst.index")
        let arrayLayoutType = CGArrayType.GenerateArrayLayoutType(cgMod, rawArrayTy)
        let srcArrPtr = CreateStructGEP(arrayLayoutType, CreateBitCast(GetPayloadFromObject(srcArray),
            unsafe { LLVMPointerType(arrayLayoutType, 1u32) }, name: "src.arr.ptr"), 1u32, name: "src.arr.data")
        let dstArrPtr = CreateStructGEP(arrayLayoutType, CreateBitCast(GetPayloadFromObject(dstArray),
            unsafe { LLVMPointerType(arrayLayoutType, 1u32) }, name: "dst.arr.ptr"), 1u32, name: "dst.arr.data")
        return CreateArrayCopyTo(rawArrayTy, srcArray, dstArray, srcArrPtr, dstArrPtr, dataSize, srcIndex, dstIndex)
    }

    public func AcquireRawData(args: ArrayList<Value>): LLVMValueRef {
        let llvmArgs = ArrayList<LLVMValueRef>()
        for (arg in args) {
            llvmArgs.add(cgMod.GetMappedCGValue(arg).GetRawValue())
        }
        CJC_ASSERT(llvmArgs.size == 1)
        let int1Ty = unsafe { LLVMInt1TypeInContext(GetLLVMContext().raw) }
        let tmp = CreateEntryAlloca(int1Ty)
        let _ = CreateStore(GetFalse(), tmp)
        let isCopyPtr = CreateBitCast(tmp, unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) })
        let callArgs = ArrayList<LLVMValueRef>()
        callArgs.add(llvmArgs[0])
        callArgs.add(isCopyPtr)
        return CreateIntrinsicCall("llvm.cj.acquire.rawdata", ArrayList<LLVMTypeRef>(), callArgs)
    }

    public func ReleaseRawData(args: ArrayList<Value>): LLVMValueRef {
        let llvmArgs = ArrayList<LLVMValueRef>()
        for (arg in args) {
            llvmArgs.add(cgMod.GetMappedCGValue(arg).GetRawValue())
        }
        CJC_ASSERT(llvmArgs.size == 2)
        let mode = unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), 0u64, 0) }
        let callArgs = ArrayList<LLVMValueRef>()
        callArgs.add(llvmArgs[0])
        callArgs.add(llvmArgs[1])
        callArgs.add(mode)
        return CreateIntrinsicCall("llvm.cj.release.rawdata", ArrayList<LLVMTypeRef>(), callArgs)
    }

    public func CallArrayInit(arrPtr: LLVMValueRef, arrayLen: LLVMValueRef, elemValue: LLVMValueRef,
        arrTy: RawArrayType): Unit {
        if (unsafe { LLVMSelfhostIsNullConstant(elemValue) } != 0) {
            return
        }
        let arrayType = CGArrayType.GenerateArrayLayoutType(cgMod, arrTy)
        let elemCGType = CGType.GetOrCreate(cgMod, arrTy.GetElementType())
        if (elemCGType.GetSize().isNone()) {
            InitArrayDataUG(this, arrPtr, arrayLen, elemValue, arrayType, arrTy)
            return
        }
        let elemType = unsafe { LLVMTypeOf(elemValue) }
        let blocks = CreateAndInsertBasicBlocks(ArrayList<String>([
            GenNameForBB("arr.init.non-opt"), GenNameForBB("arr.init.opt")]))
        CJC_ASSERT(blocks.size >= 2)
        let nonOptBB = blocks[0]
        let optBB = blocks[1]
        var isValNull = LLVMNullValue()
        if (IsFPType(elemType)) {
            try (name = unsafe { LibC.mallocCString("val.is-zero") }.asResource()) {
                isValNull = unsafe { LLVMBuildFCmp(builder.raw, LLVMRealPredicateValue(LLVMRealPredicate.OEQ),
                    elemValue, LLVMConstReal(elemType, 0.0), name.value) }
            }
        } else {
            isValNull = CreateICmp(LLVMIntPredicate.EQ, elemValue, unsafe { LLVMConstNull(elemType) },
                name: "val.is-null")
        }
        let isZeroSize = CreateICmp(LLVMIntPredicate.EQ, arrayLen, GetInt64(0), name: "size.is-zero")
        CreateCondBr(CreateBinary(ExprKind.OR, isZeroSize, isValNull), optBB, nonOptBB)
        SetInsertPoint(nonOptBB)
        let typeSize = GetCGModule().GetTypeSize(elemType)
        CJC_ASSERT(typeSize > 0u64)
        if (typeSize == 1u64) {
            InitByteArrayData(this, arrPtr, arrayLen, elemValue, arrayType)
            CreateBr(optBB)
            SetInsertPoint(optBB)
            return
        }
        InitArrayData(this, arrPtr, arrayLen, elemValue, arrayType)
        CreateBr(optBB)
        SetInsertPoint(optBB)
    }

    public func CreateVArrayGEP(varrayPtr: CGValue, indices: ArrayList<LLVMValueRef>,
        name!: String = ""): LLVMValueRef {
        indices.add(GetInt64(0), at: 0)
        let elementType = varrayPtr.GetCGType().getOrThrow().GetPointerElementType().getOrThrow().GetLLVMType()
        let varrayType = if (!elementType.isNull() &&
            unsafe { LLVMGetTypeKind(elementType) } == LLVM_ARRAY_TYPE_KIND) {
            elementType
        } else {
            LLVMNullType()
        }
        return CreateGEP(varrayType, varrayPtr.GetRawValue(), indices, name: name)
    }

    public func VArrayInitedByLambda(varrayLen: LLVMValueRef, autoEnv: CGValue,
        vArrayType: VArrayType): LLVMValueRef {
        let autoEnvCGType = autoEnv.GetCGType().getOrThrow()
        let autoEnvClassTy = (autoEnvCGType.GetOriginal().StripAllRefs() as ClassType).getOrThrow()
        let autoEnvClsDef = autoEnvClassTy.GetClassDef()
        let methods = autoEnvClsDef.GetMethods()
        CJC_ASSERT(methods.size == 1)
        let abstractMethod = methods[methods.size - 1]
        let abstractMethodIdx = GetMethodIdxInAutoEnvObject(abstractMethod.GetSrcCodeIdentifier())
        let initFuncCGType = (CGType.GetOrCreate(cgMod, abstractMethod.GetType().getOrThrow(),
            extraInfo: TypeExtraInfo(0u32, true, false, true, ArrayList<Type>())) as CGFunctionType).getOrThrow()
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let autoEnvPayload = GetPayloadFromObject(autoEnv.GetRawValue())
        let autoEnvPayloadPtr = CreateBitCast(autoEnvPayload, unsafe { LLVMPointerType(i8PtrType, 1u32) })
        let funcPtrIndices = ArrayList<LLVMValueRef>()
        funcPtrIndices.add(unsafe {
            LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), abstractMethodIdx, 0)
        })
        var initFuncPtr = CreateGEP(i8PtrType, autoEnvPayloadPtr, funcPtrIndices, name: "virtualFPtr")
        initFuncPtr = CreateLoad(i8PtrType, initFuncPtr)
        initFuncPtr = CreateBitCast(initFuncPtr, unsafe { LLVMPointerType(initFuncCGType.GetLLVMFunctionType(), 0u32) })

        let arrayCGType = CGType.GetOrCreate(cgMod, vArrayType)
        let varrPtr = CreateEntryAlloca(arrayCGType, name: "varray.initialized.by.lambda")
        let blockNames = ArrayList<String>()
        blockNames.add(GenNameForBB("varr.init.start"))
        blockNames.add(GenNameForBB("varr.init.body"))
        blockNames.add(GenNameForBB("varr.init.end"))
        let blocks = CreateAndInsertBasicBlocks(blockNames)
        let startBB = blocks[0]
        let bodyBB = blocks[1]
        let endBB = blocks[2]
        CreateBr(startBB)

        SetInsertPoint(startBB)
        let indexCGType = CGType.GetOrCreate(cgMod, GetCGContext().GetCHIRBuilder().context.GetInt64Ty())
        let iterator = CreateEntryAlloca(indexCGType, name: "iterator")
        CreateStore(GetInt64(0), iterator)
        CreateBr(bodyBB)

        SetInsertPoint(bodyBB)
        let index = CreateLoad(indexCGType.GetLLVMType(), iterator)
        let cgValueOfIdx = CGValue(index, indexCGType)
        let args = ArrayList<CGValue>()
        args.add(autoEnv)
        args.add(cgValueOfIdx)
        let value = CreateCallOrInvoke(initFuncCGType, initFuncPtr, args)
        let elemType = vArrayType.GetElementType()
        let elemCGType = CGType.GetOrCreate(cgMod, elemType)
        let elemRefType = GetCGContext().GetCHIRBuilder().context.GetRefTy(elemType)
        let elemPtrCGType = CGType.GetOrCreate(cgMod, elemRefType)
        let elemIndices = ArrayList<LLVMValueRef>()
        elemIndices.add(GetInt64(0))
        elemIndices.add(index)
        let elemPtr = CreateGEP(arrayCGType.GetLLVMType(), varrPtr, elemIndices, name: "varr.idx")
        if (elemCGType.IsVArrayType() || elemCGType.IsStructType()) {
            CreateStore(CGValue(value, elemPtrCGType), CGValue(elemPtr, elemPtrCGType))
        } else {
            CreateStore(CGValue(value, elemCGType), CGValue(elemPtr, elemPtrCGType))
        }

        let incremented = CreateBinary(ExprKind.ADD, index, GetInt64(1), name: "iterator.next")
        CreateStore(incremented, iterator)
        let cmpResult = CreateICmp(LLVMIntPredicate.SLT, incremented, varrayLen, name: "iterator.size.cmp")
        CreateCondBr(cmpResult, bodyBB, endBB)

        SetInsertPoint(endBB)
        return varrPtr
    }

    public func VArrayInitedByItem(varrayLen: LLVMValueRef, cgVal: CGValue, vArrayType: Type): LLVMValueRef {
        let arrayCGType = CGType.GetOrCreate(cgMod, vArrayType)
        let arrayType = arrayCGType.GetLLVMType()
        let varrPtr = CreateEntryAlloca(arrayCGType, name: "varray.initialized.by.item")
        let blockNames = ArrayList<String>()
        blockNames.add(GenNameForBB("varr.init.start"))
        blockNames.add(GenNameForBB("varr.init.body"))
        blockNames.add(GenNameForBB("varr.init.end"))
        let blocks = CreateAndInsertBasicBlocks(blockNames)
        let startBB = blocks[0]
        let bodyBB = blocks[1]
        let endBB = blocks[2]
        CreateBr(startBB)

        SetInsertPoint(startBB)
        let indexCGType = CGType.GetOrCreate(cgMod, GetCGContext().GetCHIRBuilder().context.GetInt64Ty())
        let iterator = CreateEntryAlloca(indexCGType, name: "iterator")
        CreateStore(GetInt64(0), iterator)
        CreateBr(bodyBB)

        SetInsertPoint(bodyBB)
        let index = CreateLoad(indexCGType.GetLLVMType(), iterator)
        let elemIndices = ArrayList<LLVMValueRef>()
        elemIndices.add(GetInt64(0))
        elemIndices.add(index)
        let elemPtr = CreateGEP(arrayType, varrPtr, elemIndices, name: "varr.idx")
        let vArrayTypeValue = (vArrayType as VArrayType).getOrThrow()
        let elementRefTy = GetCGContext().GetCHIRBuilder().context.GetRefTy(vArrayTypeValue.GetElementType())
        let elementPtrCGType = CGType.GetOrCreate(cgMod, elementRefTy)
        CreateStore(cgVal, CGValue(elemPtr, elementPtrCGType))
        let incremented = CreateBinary(ExprKind.ADD, index, GetInt64(1), name: "iterator.next")
        CreateStore(incremented, iterator)
        let cmpResult = CreateICmp(LLVMIntPredicate.SLT, incremented, varrayLen, name: "iterator.size.cmp")
        CreateCondBr(cmpResult, bodyBB, endBB)

        SetInsertPoint(endBB)
        return varrPtr
    }

    public func CreatePHI(valueType: LLVMTypeRef, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildPhi(builder.raw, valueType, nameCString.value) }
        }
        return ApplyFastMathIfNeeded(result)
    }

    public func AddIncoming(phi: LLVMValueRef, values: ArrayList<LLVMValueRef>,
        blocks: ArrayList<LLVMBasicBlockRef>): Unit {
        if (values.size != blocks.size) {
            throw IllegalArgumentException("PHI incoming values and blocks must have the same length")
        }
        if (values.isEmpty()) {
            return
        }
        try (valuePtr = LibC.malloc<LLVMValueRef>(count: values.size).asResource()) {
            try (blockPtr = LibC.malloc<LLVMBasicBlockRef>(count: blocks.size).asResource()) {
                var idx: Int64 = 0
                while (idx < values.size) {
                    unsafe { (valuePtr.value + idx).write(values[idx]) }
                    unsafe { (blockPtr.value + idx).write(blocks[idx]) }
                    idx++
                }
                unsafe { LLVMAddIncoming(phi, valuePtr.value, blockPtr.value, UInt32(values.size)) }
            }
        }
    }

    public func CreateSelect(cond: LLVMValueRef, trueValue: LLVMValueRef, falseValue: LLVMValueRef,
        name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildSelect(builder.raw, cond, trueValue, falseValue, nameCString.value) }
        }
        return ApplyFastMathIfNeeded(result)
    }

    public func CreateBitCast(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "bitcast"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildBitCast(builder.raw, value, destType, nameCString.value) }
        }
        PropagateBasePtr(value, result)
        return result
    }

    public func CreateTrunc(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "trunc"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildTrunc(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateZExt(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "zext"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildZExt(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateZExtOrTrunc(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "zextortrunc"): LLVMValueRef {
        let valueType = unsafe { LLVMTypeOf(value) }
        let valueWidth = unsafe { LLVMGetIntTypeWidth(valueType) }
        let destWidth = unsafe { LLVMGetIntTypeWidth(destType) }
        if (valueWidth == destWidth) {
            return value
        }
        if (valueWidth < destWidth) {
            return CreateZExt(value, destType, name: name)
        }
        return CreateTrunc(value, destType, name: name)
    }

    public func CreateSExt(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "sext"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildSExt(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateSExtOrTrunc(value: LLVMValueRef, destType: LLVMTypeRef,
        name!: String = "sextortrunc"): LLVMValueRef {
        let valueWidth = unsafe { LLVMGetIntTypeWidth(LLVMTypeOf(value)) }
        let destWidth = unsafe { LLVMGetIntTypeWidth(destType) }
        if (valueWidth == destWidth) {
            return value
        }
        if (valueWidth < destWidth) {
            return CreateSExt(value, destType, name: name)
        }
        return CreateTrunc(value, destType, name: name)
    }

    public func CreateFPTrunc(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "fptrunc"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildFPTrunc(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateFPExt(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "fpext"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildFPExt(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateFPToUI(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "fptoui"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildFPToUI(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateFPToSI(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "fptosi"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildFPToSI(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateUIToFP(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "uitofp"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildUIToFP(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateSIToFP(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "sitofp"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildSIToFP(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreatePtrToInt(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "ptrtoint"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildPtrToInt(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateIntToPtr(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "inttoptr"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildIntToPtr(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreatePointerCast(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "ptrcast"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMSelfhostCreatePointerCast(builder.raw, value, destType, nameCString.value) }
        }
        PropagateBasePtr(value, result)
        return result
    }

    public func CreateBitOrPointerCast(value: LLVMValueRef, destType: LLVMTypeRef,
        name!: String = ""): LLVMValueRef {
        let sourceType = unsafe { LLVMTypeOf(value) }
        if (unsafe { LLVMGetTypeKind(sourceType) } == LLVM_POINTER_TYPE_KIND &&
            unsafe { LLVMGetTypeKind(destType) } == LLVM_POINTER_TYPE_KIND) {
            return CreatePointerCast(value, destType, name: name)
        }
        return CreateBitCast(value, destType, name: name)
    }

    public func CreateAddrSpaceCast(value: LLVMValueRef, destType: LLVMTypeRef, name!: String = "addrspacecast"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildAddrSpaceCast(builder.raw, value, destType, nameCString.value) }
        }
        return result
    }

    public func CreateUnreachable(): LLVMValueRef {
        let currentBlock = GetInsertBlock()
        if (currentBlock.isNull()) {
            return LLVMNullValue()
        }
        if (!unsafe { LLVMGetBasicBlockTerminator(currentBlock) }.isNull()) {
            return LLVMNullValue()
        }
        return unsafe { LLVMBuildUnreachable(builder.raw) }
    }

    public func GetLandingPadType(): LLVMTypeRef {
        return unsafe { LLVMTokenTypeInContext(GetLLVMContext().raw) }
    }

    public func CreateLandingPad(landingPadType: LLVMTypeRef, numClauses: UInt32,
        name!: String = "landingpad"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMBuildLandingPad(builder.raw, landingPadType, LLVMNullValue(), numClauses, nameCString.value)
            }
        }
        return result
    }

    public func CreateLandingPad(numClauses: UInt32, name!: String = "landingpad"): LLVMValueRef {
        return CreateLandingPad(GetLandingPadType(), numClauses, name: name)
    }

    public func AddLandingPadClause(landingPad: LLVMValueRef, clause: LLVMValueRef): Unit {
        if (!landingPad.isNull() && !clause.isNull()) {
            unsafe { LLVMAddClause(landingPad, clause) }
        }
    }

    public func AddLandingPadCatchAllClause(landingPad: LLVMValueRef): Unit {
        let catchAll = unsafe {
            LLVMConstNull(LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32))
        }
        AddLandingPadClause(landingPad, catchAll)
    }

    public func GetLandingPadClauseCount(landingPad: LLVMValueRef): UInt32 {
        if (landingPad.isNull()) {
            return 0u32
        }
        return unsafe { LLVMGetNumClauses(landingPad) }
    }

    public func GetLandingPadClause(landingPad: LLVMValueRef, index: UInt32): LLVMValueRef {
        if (landingPad.isNull() || index >= GetLandingPadClauseCount(landingPad)) {
            return LLVMNullValue()
        }
        return unsafe { LLVMGetClause(landingPad, index) }
    }

    public func SetLandingPadCleanup(landingPad: LLVMValueRef, cleanup: Bool): Unit {
        if (!landingPad.isNull()) {
            unsafe { LLVMSetCleanup(landingPad, if (cleanup) { 1 } else { 0 }) }
        }
    }

    public func IsLandingPadCleanup(landingPad: LLVMValueRef): Bool {
        return !landingPad.isNull() && unsafe { LLVMIsCleanup(landingPad) } != 0
    }

    public func CreateResume(exceptionValue: LLVMValueRef): LLVMValueRef {
        return unsafe { LLVMBuildResume(builder.raw, exceptionValue) }
    }

    public func CreateCleanupRet(catchPad: LLVMValueRef, block: LLVMBasicBlockRef): LLVMValueRef {
        return unsafe { LLVMBuildCleanupRet(builder.raw, catchPad, block) }
    }

    public func CreateCatchRet(catchPad: LLVMValueRef, block: LLVMBasicBlockRef): LLVMValueRef {
        return unsafe { LLVMBuildCatchRet(builder.raw, catchPad, block) }
    }

    public func CreateCatchPad(parentPad: LLVMValueRef, args: ArrayList<LLVMValueRef>,
        name!: String = "catchpad"): LLVMValueRef {
        return CreateFuncletPad(parentPad, args, true, name: name)
    }

    public func CreateCleanupPad(parentPad: LLVMValueRef, args: ArrayList<LLVMValueRef>,
        name!: String = "cleanuppad"): LLVMValueRef {
        return CreateFuncletPad(parentPad, args, false, name: name)
    }

    private func CreateFuncletPad(parentPad: LLVMValueRef, args: ArrayList<LLVMValueRef>, isCatch: Bool,
        name!: String): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            if (args.isEmpty()) {
                result = if (isCatch) {
                    unsafe { LLVMBuildCatchPad(builder.raw, parentPad, CPointer<LLVMValueRef>(), 0u32, nameCString.value) }
                } else {
                    unsafe { LLVMBuildCleanupPad(builder.raw, parentPad, CPointer<LLVMValueRef>(), 0u32, nameCString.value) }
                }
            } else {
                try (argPtr = LibC.malloc<LLVMValueRef>(count: args.size).asResource()) {
                    var idx: Int64 = 0
                    while (idx < args.size) {
                        unsafe { (argPtr.value + idx).write(args[idx]) }
                        idx++
                    }
                    result = if (isCatch) {
                        unsafe { LLVMBuildCatchPad(builder.raw, parentPad, argPtr.value, UInt32(args.size), nameCString.value) }
                    } else {
                        unsafe { LLVMBuildCleanupPad(builder.raw, parentPad, argPtr.value, UInt32(args.size), nameCString.value) }
                    }
                }
            }
        }
        return result
    }

    public func CreateCatchSwitch(parentPad: LLVMValueRef, unwindBlock: LLVMBasicBlockRef, handlerCountHint: UInt32,
        name!: String = "catchswitch"): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildCatchSwitch(builder.raw, parentPad, unwindBlock, handlerCountHint, nameCString.value) }
        }
        return result
    }

    public func AddCatchSwitchHandler(catchSwitch: LLVMValueRef, dest: LLVMBasicBlockRef): Unit {
        if (!catchSwitch.isNull() && !dest.isNull()) {
            unsafe { LLVMAddHandler(catchSwitch, dest) }
        }
    }

    public func CreateAggregateValue(aggregateType: LLVMTypeRef, elements: ArrayList<LLVMValueRef>,
        name!: String = "agg"): LLVMValueRef {
        var aggregate = unsafe { LLVMGetUndef(aggregateType) }
        var idx: Int64 = 0
        while (idx < elements.size) {
            try (nameCString = unsafe { LibC.mallocCString(name + ".${idx}") }.asResource()) {
                aggregate = unsafe { LLVMBuildInsertValue(builder.raw, aggregate, elements[idx], UInt32(idx), nameCString.value) }
            }
            idx++
        }
        return aggregate
    }

    public func CreateExtractValue(aggregate: LLVMValueRef, index: UInt32, name!: String = ""): LLVMValueRef {
        var result = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { LLVMBuildExtractValue(builder.raw, aggregate, index, nameCString.value) }
        }
        return result
    }

    public func CreateOverflowOrArithmeticException(ident: String, isOverflow!: Bool = true): Unit {
        let helperName = if (isOverflow) { CREATE_OVERFLOW_EXCEPTION_FUNC_NAME } else {
            CREATE_ARITHMETIC_EXCEPTION_FUNC_NAME
        }
        // The const-string global is already a sized `%String*` in address space 0 and the helper
        // param is now address space 0 too, so pass it directly — mirror C++ DoSimpleCast
        // (CJNativeIRBuilder.cpp:27) which emits no cast when the address spaces already match.
        let literal = CreateStringLiteral(ident)
        let (helperFunction, _) = GetOrInsertRuntimeExceptionHelper(helperName)
        let helperArgs = ArrayList<LLVMValueRef>()
        helperArgs.add(literal)
        let exceptionValue = CreateCallOrInvoke(helperFunction, helperArgs, name: "exception")
        CallExceptionIntrinsicThrow(exceptionValue)
    }

    public func CreateStringLiteral(value: String): LLVMValueRef {
        let cjStringName = GetCjStringLiteralName(value)
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            var result = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(cjStringName) }.asResource()) {
                result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
                if (result.isNull()) {
                    let _ = CGArrayType.GenerateArrayLayoutTypeInfo(GetCGContext(), ARRAY_LAYOUT_PREFIX + "UInt8",
                        unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) })
                    result = unsafe { LLVMAddGlobal(moduleHandle.raw, GetCGContext().GetCjStringType(), nameCString.value) }
                    unsafe {
                        LLVMSetGlobalConstant(result, 1)
                        addAttribute(result, CJSTRING_LITERAL_ATTR)
                        LLVMSetLinkage(result, LLVMLinkageValue(LLVMLinkage.Private))
                    }
                    GetCGContext().AddCJString(cjStringName, value)
                }
            }
            return result
        }
        throw IllegalStateException("cannot create string literal without an LLVM module")
    }

    public func CallExceptionIntrinsicThrow(exceptionValue: LLVMValueRef): Unit {
        let throwArgs = ArrayList<LLVMValueRef>()
        throwArgs.add(exceptionValue)
        let intrinsicCall = CreateIntrinsicCall(THROW_EXCEPTION_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), throwArgs)
        if (intrinsicCall.isNull()) {
            let throwType = GetThrowExceptionFunctionType()
            let throwFunction = GetOrInsertRuntimeFunction(THROW_EXCEPTION_FUNC_NAME, throwType)
            let _ = CreateCallOrInvoke(throwFunction, throwArgs)
        }
        let _ = CreateUnreachable()
    }

    public func CallExceptionIntrinsicGetExceptionValue(): LLVMValueRef {
        let args = ArrayList<LLVMValueRef>()
        let exceptionValue = CreateIntrinsicCall(GET_EXCEPTION_WRAPPER_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args,
            name: "exception.wrapper")
        if (!exceptionValue.isNull()) {
            return exceptionValue
        }
        let fallbackType = MakeFunctionType(unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) },
            ArrayList<LLVMTypeRef>())
        return CreateCallOrInvoke(GetOrInsertRuntimeFunction("CJ_MCC_GetExceptionWrapper", fallbackType), args,
            name: "exception.wrapper")
    }

    public func CallPostThrowExceptionIntrinsic(exceptionValue: LLVMValueRef): LLVMValueRef {
        let args = ArrayList<LLVMValueRef>()
        args.add(exceptionValue)
        let postThrowValue = CreateIntrinsicCall(POST_THROW_EXCEPTION_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args,
            name: "post.throw")
        if (!postThrowValue.isNull()) {
            return postThrowValue
        }
        let paramTypes = ArrayList<LLVMTypeRef>()
        paramTypes.add(unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) })
        let fallbackType = MakeFunctionType(CGType.GetRefType(GetLLVMContext()), paramTypes)
        return CreateCallOrInvoke(GetOrInsertRuntimeFunction("CJ_MCC_PostThrowException", fallbackType), args,
            name: "post.throw")
    }

    public func CallSpawnIntrinsic(obj: CGValue, cgFunc: CGFunction, threadCtx: Option<CGValue>,
        spawnWithFuture: Bool): LLVMValueRef {
        return CallSpawnIntrinsic(obj, cgFunc, threadCtx, spawnWithFuture, None)
    }

    public func CallSpawnIntrinsic(obj: CGValue, cgFunc: CGFunction, threadCtx: Option<CGValue>,
        spawnWithFuture: Bool, futureTI: Option<LLVMValueRef>): LLVMValueRef {
        let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(cgFunc.GetRawFunction())
        args.add(obj.GetRawValue())
        if (let Some(ctxValue) <- threadCtx) {
            args.add(ctxValue.GetRawValue())
        } else {
            args.add(unsafe { LLVMConstNull(i8PtrTy) })
        }
        if (!spawnWithFuture) {
            let futureTIValue = if (let Some(value) <- futureTI) {
                value
            } else {
                return LLVMNullValue()
            }
            args.add(CreateBitCast(futureTIValue, i8PtrTy, name: "future.ti"))
        }
        let runtimeName = if (spawnWithFuture) { NEW_CJ_THREAD_FUNC_NAME } else { NEW_CJ_THREAD_NO_RETURN_FUNC_NAME }
        let runtimeType = MakeFunctionTypeFromArgs(i8PtrTy, args)
        return CreateCallOrInvoke(GetOrInsertRuntimeFunction(runtimeName, runtimeType), args, name: "spawn.thread")
    }

    public func CreateSpawnException(): Unit {
        CreateImplicitExceptionAndThrow("_CNat14SpawnException6<init>Hv")
    }

    public func CreateSetRuntimeCJThreadHandleCall(args: ArrayList<LLVMValueRef>): LLVMValueRef {
        let helperName = "_CNat6Thread24setRuntimeCJThreadHandleHPu"
        if (let Some(helperNode) <- GetCGContext().GetImplicitUsedFunc(helperName)) {
            let helperFunc = cgMod.GetOrInsertCGFunction(helperNode)
            return CreateCallOrInvoke(helperFunc.GetRawFunction(), args)
        }
        let helperType = MakeFunctionTypeFromArgs(unsafe { LLVMVoidTypeInContext(GetLLVMContext().raw) }, args)
        return CreateCallOrInvoke(GetOrInsertRuntimeFunction(helperName, helperType), args)
    }

    public func CreateExecAtExitCallbacksCall(): LLVMValueRef {
        let helperName = "_CNat27CJ_CORE_ExecAtexitCallbacksHv"
        let args = ArrayList<LLVMValueRef>()
        args.add(CreateEntryAlloca(CGType.GetUnitType(GetLLVMContext())))
        if (let Some(helperNode) <- GetCGContext().GetImplicitUsedFunc(helperName)) {
            let helperFunc = cgMod.GetOrInsertCGFunction(helperNode)
            return CreateCallOrInvoke(helperFunc.GetRawFunction(), args)
        }
        return CreateImplicitUsedFunctionCall(helperName, args)
    }

    public func CreateGetCommandLineArgsCall(args: ArrayList<LLVMValueRef>): LLVMValueRef {
        return CreateImplicitUsedFunctionCall("_CNat18getCommandLineArgsHv", args)
    }

    public func CreateHandleExceptionCall(exceptionValue: LLVMValueRef): LLVMValueRef {
        let helperName = "_CNat15handleExceptionHCNat9ExceptionE"
        if (let Some(helperNode) <- GetCGContext().GetImplicitUsedFunc(helperName)) {
            let helperFunc = cgMod.GetOrInsertCGFunction(helperNode)
            if (let Some(helperFuncType) <- helperFunc.GetCGFunctionType()) {
                if (let Some(funcTy) <- helperNode.GetFuncType()) {
                    let args = ArrayList<LLVMValueRef>()
                    args.add(CreateEntryAlloca(CGType.GetUnitType(GetLLVMContext())))
                    args.add(FixFuncArg(CGValue(exceptionValue, CGType.GetOrCreate(cgMod, funcTy.GetParamType(0))),
                        helperFuncType.GetParamType(0)))
                    return CreateCallOrInvoke(helperFunc.GetRawFunction(), args)
                }
            }
        }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreateEntryAlloca(CGType.GetUnitType(GetLLVMContext())))
        args.add(exceptionValue)
        return CreateImplicitUsedFunctionCall(helperName, args)
    }

    public func CreateEPrintlnCall(message: String): LLVMValueRef {
        let helperName = "_CNat8eprintlnHRNat6StringE"
        if (let Some(helperNode) <- GetCGContext().GetImplicitUsedFunc(helperName)) {
            let helperFunc = cgMod.GetOrInsertCGFunction(helperNode)
            if (let Some(helperFuncType) <- helperFunc.GetCGFunctionType()) {
                if (let Some(funcTy) <- helperNode.GetFuncType()) {
                    let paramRefTy = GetCGContext().GetCHIRBuilder().context.GetRefTy(funcTy.GetParamType(0))
                    let args = ArrayList<LLVMValueRef>()
                    args.add(CreateEntryAlloca(CGType.GetUnitType(GetLLVMContext())))
                    args.add(FixFuncArg(CGValue(CreateStringLiteral(message), CGType.GetOrCreate(cgMod, paramRefTy)),
                        helperFuncType.GetParamType(0)))
                    return CreateCallOrInvoke(helperFunc.GetRawFunction(), args)
                }
            }
        }
        return LLVMNullValue()
    }

    public func CallClassIntrinsicInstanceOf(instance: LLVMValueRef, targetTy: Type): LLVMValueRef {
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i8PtrPtrType = unsafe { LLVMPointerType(i8PtrType, 1u32) }
        let instanceInt8Ptr = CreateBitCast(instance, i8PtrPtrType, name: "inst.i8ptr")
        let instanceTypeInfo = CreateLoad(i8PtrType, instanceInt8Ptr, name: "inst.ti")
        let targetTypeInfo = CreateBitCast(CreateTypeInfo(targetTy), i8PtrType, name: "target.ti")
        let args = ArrayList<LLVMValueRef>()
        args.add(instanceTypeInfo)
        args.add(targetTypeInfo)
        return CreateIntrinsicCallNoInvoke("llvm.cj.is.subtype", ArrayList<LLVMTypeRef>(), args, name: "is.subtype")
    }

    public func CallIntrinsicIsSubtype(parameters: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(parameters.size == 2)
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreateBitCast(parameters[0], i8PtrType))
        args.add(CreateBitCast(parameters[1], i8PtrType))
        return CreateIntrinsicCallNoInvoke("llvm.cj.is.subtype", ArrayList<LLVMTypeRef>(), args)
    }

    public func CallIntrinsicIsTupleTypeOf(parameters: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(parameters.size == 3)
        let boolType = unsafe { LLVMInt1TypeInContext(GetLLVMContext().raw) }
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i8PtrType1 = unsafe { LLVMPointerType(i8Type, 1u32) }
        let objectLLVMType = unsafe { LLVMTypeOf(parameters[0]) }
        let isRefType = unsafe { LLVMGetTypeKind(objectLLVMType) } == LLVM_POINTER_TYPE_KIND &&
            unsafe { LLVMGetPointerAddressSpace(objectLLVMType) } == 1u32
        let objectParamType = if (isRefType) { i8PtrType1 } else { i8PtrType }
        let functionName = if (isRefType) {
            "llvm.cj.is.tupletype.of.p1i8"
        } else {
            "llvm.cj.is.tupletype.of.p0i8"
        }
        let functionType = MakeFunctionType(boolType,
            ArrayList<LLVMTypeRef>([objectParamType, i8PtrType, i8PtrType]))
        let function = cgMod.GetOrInsertFunction(functionName, functionType)
        let args = ArrayList<LLVMValueRef>([
            CreateBitCast(parameters[0], objectParamType),
            CreateBitCast(parameters[1], i8PtrType),
            CreateBitCast(parameters[2], i8PtrType)
        ])
        return CreateCall(function, functionType, args)
    }

    public func CallIntrinsicIsTypeEqualTo(parameters: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(parameters.size == 2)
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreateBitCast(parameters[0], i8PtrType))
        args.add(CreateBitCast(parameters[1], i8PtrType))
        return CreateIntrinsicCallNoInvoke("llvm.cj.is.typeinfo.equal", ArrayList<LLVMTypeRef>(), args)
    }

    public func CallIntrinsicGetVTableFunc(ti: LLVMValueRef, introTypeIdx: LLVMValueRef,
        funcOffset: LLVMValueRef, introTI: LLVMValueRef): LLVMValueRef {
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreateBitCast(ti, i8PtrType))
        args.add(introTypeIdx)
        args.add(funcOffset)
        args.add(CreateBitCast(introTI, i8PtrType))
        return CreateIntrinsicCallNoInvoke("llvm.cj.get.vtable.func", ArrayList<LLVMTypeRef>(), args)
    }

    public func CallIntrinsicMTable(parameters: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(parameters.size == 3)
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreateBitCast(parameters[0], i8PtrType))
        args.add(CreateBitCast(parameters[1], i8PtrType))
        args.add(parameters[2])
        return CreateIntrinsicCallNoInvoke("llvm.cj.get.mtable.func", ArrayList<LLVMTypeRef>(), args)
    }

    public func CallIntrinsicMethodOuterType(parameters: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(parameters.size == 3)
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreateBitCast(parameters[0], i8PtrType))
        args.add(CreateBitCast(parameters[1], i8PtrType))
        args.add(parameters[2])
        return CreateIntrinsicCallNoInvoke("llvm.cj.get.method.outertype", ArrayList<LLVMTypeRef>(), args)
    }

    public func CreateNegativeArraySizeException(): Unit {
        let helperType = MakeFunctionType(unsafe { LLVMVoidTypeInContext(GetLLVMContext().raw) }, ArrayList<LLVMTypeRef>())
        let helper = if (let Some(helperNode) <- GetCGContext().GetImplicitUsedFunc(THROW_NEGATIVE_ARRAY_SIZE_EXCEPTION_FUNC_NAME)) {
            cgMod.GetOrInsertCGFunction(helperNode).GetRawFunction()
        } else {
            GetOrInsertRuntimeFunction(THROW_NEGATIVE_ARRAY_SIZE_EXCEPTION_FUNC_NAME, helperType)
        }
        let _ = CreateCallOrInvoke(helper, ArrayList<LLVMValueRef>())
    }

    public func CreateOutOfBoundException(): Unit {
        CreateImplicitExceptionAndThrow("_CNat25IndexOutOfBoundsException6<init>Hv")
    }

    public func CreateRunTimeInvalidGenericParamException(): Unit {
        CreateImplicitExceptionAndThrow("_CNat9Exception6<init>Hv")
    }

    public func AllocateArray(rawArrayTy: RawArrayType, length: LLVMValueRef): LLVMValueRef {
        let rawArrayCGType = CGType.GetOrCreate(cgMod, rawArrayTy)
        let rawTypeInfo = rawArrayCGType.GetOrCreateTypeInfo()
        let rawTypeInfoArg = CreateBitCast(rawTypeInfo,
            unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }, name: "rawarray.ti")
        let lengthArg = CastIntegerToInt64(length)
        let args = ArrayList<LLVMValueRef>()
        args.add(rawTypeInfoArg)
        args.add(lengthArg)
        let intrinsicName = if (rawArrayCGType.IsDynamicGI()) {
            MALLOC_ARRAY_GENERIC_INTRINSIC_NAME
        } else {
            let elementSize = GetRawArrayElementSize(rawArrayTy)
            args.add(unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), UInt64(elementSize), 0) })
            MALLOC_ARRAY_INTRINSIC_NAME
        }
        CheckNoHeapAlloc(intrinsicName)
        let arrayValue = CreateIntrinsicCall(intrinsicName, ArrayList<LLVMTypeRef>(), args, name: "rawarray")
        if (arrayValue.isNull()) {
            return LLVMNullValue()
        }
        AddRetAttr(arrayValue, "noalias")
        return arrayValue
    }

    private func GetOrInsertRuntimeExceptionHelper(funcName: String): (LLVMValueRef, LLVMTypeRef) {
        if (let Some(helperNode) <- GetCGContext().GetImplicitUsedFunc(funcName)) {
            let cgFunctionValue = cgMod.GetOrInsertCGFunction(helperNode)
            if (let Some(functionType) <- cgFunctionValue.GetCGFunctionType()) {
                return (cgFunctionValue.GetRawFunction(), functionType.GetLLVMFunctionType())
            }
        }
        let fallbackType = GetRuntimeExceptionHelperType()
        return (GetOrInsertRuntimeFunction(funcName, fallbackType), fallbackType)
    }

    private func CreateImplicitExceptionAndThrow(initFuncName: String): Unit {
        if (let Some(initFuncNode) <- GetCGContext().GetImplicitUsedFunc(initFuncName)) {
            if (let Some(exceptionTy) <- TryGetFirstParamClassType(initFuncNode)) {
                let exceptionValue = CallClassIntrinsicAlloc(exceptionTy)
                let initArgs = ArrayList<LLVMValueRef>()
                initArgs.add(exceptionValue)
                initArgs.add(CGType.GetOrCreate(cgMod, exceptionTy).GetOrCreateTypeInfo())
                let initFunc = cgMod.GetOrInsertCGFunction(initFuncNode)
                let _ = CreateCallOrInvoke(initFunc.GetRawFunction(), initArgs)
                CallExceptionIntrinsicThrow(exceptionValue)
                return
            }
        }
        CreateUnreachable()
    }

    private func CreateImplicitUsedFunctionCall(helperName: String, args: ArrayList<LLVMValueRef>): LLVMValueRef {
        if (let Some(helperNode) <- GetCGContext().GetImplicitUsedFunc(helperName)) {
            let helperFunc = cgMod.GetOrInsertCGFunction(helperNode)
            if (let Some(helperFuncType) <- helperFunc.GetCGFunctionType()) {
                return CreateCallOrInvoke(helperFunc.GetRawFunction(), args)
            }
        }
        let helperType = MakeFunctionTypeFromArgs(unsafe { LLVMVoidTypeInContext(GetLLVMContext().raw) }, args)
        return CreateCallOrInvoke(GetOrInsertRuntimeFunction(helperName, helperType), args)
    }

    private func TryGetFirstParamClassType(fn: Function): Option<Type> {
        if (let Some(funcTy) <- fn.GetFuncType()) {
            let params = funcTy.GetParamTypes()
            if (!params.isEmpty()) {
                let strippedTy = params[0].StripAllRefs()
                if (strippedTy.IsClass()) {
                    return strippedTy
                }
            }
        }
        return None
    }

    public func CallClassIntrinsicAlloc(classTy: Type): LLVMValueRef {
        let objectValue = CallClassIntrinsicAlloc(ArrayList<LLVMValueRef>([CreateTypeInfo(classTy),
            GetLayoutSize_32(classTy)]))
        if (!objectValue.isNull()) {
            if (classTy.IsClass()) {
                AddClassMallocMetadata(objectValue, classTy)
            }
            if (IsSizeTrustedInCompileUnit(cgMod, classTy)) {
                LLVMSetInstructionMetadata(GetLLVMContext(), objectValue, "TrustedSize",
                    LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>()))
            }
        }
        return objectValue
    }

    public func CallClassIntrinsicAlloc(parameters: ArrayList<LLVMValueRef>): LLVMValueRef {
        CJC_ASSERT(parameters.size == 2)
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreateBitCast(parameters[0], i8PtrType, name: "class.ti"))
        args.add(parameters[1])
        CheckNoHeapAlloc(MALLOC_OBJECT_INTRINSIC_NAME)
        let objectValue = CreateIntrinsicCall(MALLOC_OBJECT_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args,
            name: "class.alloc")
        if (!objectValue.isNull()) {
            AddRetAttr(objectValue, "noalias")
        }
        return objectValue
    }

    private func AddClassMallocMetadata(objectValue: LLVMValueRef, classTy: Type): Unit {
        let classType = (classTy as ClassType).getOrThrow()
        CJC_ASSERT(!classTy.IsAutoEnvBase())
        let classDef = classType.GetClassDef()
        let mallocType = ArrayList<LLVMMetadataRef>()
        if (classDef.GetFinalizer().isSome()) {
            mallocType.add(LLVMCreateMDString(GetLLVMContext(), GC_FINALIZER_ATTR))
        }
        if (IsCoreFutureClass(classDef) || IsSyncRelatedClass(classDef) || IsWeakRefClass(classDef)) {
            mallocType.add(LLVMCreateMDString(GetLLVMContext(), classDef.GetSrcCodeIdentifier()))
        }
        if (!mallocType.isEmpty()) {
            LLVMSetInstructionMetadata(GetLLVMContext(), objectValue, "MallocType",
                LLVMCreateMDTuple(GetLLVMContext(), mallocType))
        }
    }

    public func CallValueIntrinsicAlloc(sourceTy: Type): LLVMValueRef {
        let valueTy = sourceTy.StripAllRefs()
        let valueCGType = CGType.GetOrCreate(cgMod, valueTy)
        let typeInfo = if (valueCGType.IsDynamicGI()) {
            CreateTypeInfo(valueTy)
        } else {
            valueCGType.GetOrCreateTypeInfo()
        }
        let typeInfoArg = CreateBitCast(typeInfo, unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw),
            0u32) }, name: "generic.ti")
        let args = ArrayList<LLVMValueRef>()
        args.add(typeInfoArg)
        args.add(GetLayoutSize32(valueTy, valueCGType))
        CheckNoHeapAlloc(MALLOC_OBJECT_INTRINSIC_NAME)
        let objectValue = CreateIntrinsicCall(MALLOC_OBJECT_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args,
            name: "generic.alloc")
        if (!objectValue.isNull()) {
            AddRetAttr(objectValue, "noalias")
        }
        return objectValue
    }

    public func StoreValueToObjectPayload(objectValue: LLVMValueRef, sourceValue: LLVMValueRef, sourceTy: Type): Unit {
        let valueTy = sourceTy.StripAllRefs()
        if (valueTy.IsUnit()) {
            return
        }
        let valueCGType = CGType.GetOrCreate(cgMod, valueTy)
        let payload = GetPayloadFromObject(objectValue)
        let payloadType = unsafe { LLVMPointerType(valueCGType.GetLLVMType(), 1u32) }
        let typedPayload = CreateBitCast(payload, payloadType, name: "generic.payload")
        let storedValue = if (ShouldLoadGenericAggregateBoxSource(sourceValue, valueTy, valueCGType)) {
            CreateLoad(valueCGType.GetLLVMType(), sourceValue, name: "generic.payload.value")
        } else {
            sourceValue
        }
        if (valueCGType.IsReference() || IsOptionLikeRefValue(valueCGType)) {
            CallGCWrite(storedValue, objectValue, typedPayload)
            return
        }
        if ((valueTy.IsStruct() || valueTy.IsTuple()) && IsLLVMTypeContainsRef(valueCGType.GetLLVMType())) {
            let storedValueType = unsafe { LLVMTypeOf(storedValue) }
            let sourcePtr = if (!storedValueType.isNull() && unsafe { LLVMGetTypeKind(storedValueType) } == 12) {
                storedValue
            } else {
                let tmp = CreateEntryAlloca(valueCGType, name: "generic.tuple")
                StoreAggregateArgToSlot(storedValue, tmp)
                tmp
            }
            let size = unsafe {
                LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw),
                    cgMod.GetTypeSize(valueCGType.GetLLVMType()), 0)
            }
            CallGCWriteStruct(objectValue, typedPayload, sourcePtr, size, valueCGType.GetOriginal().ToString())
            return
        }
        let addrType = CGType.GetOrCreate(cgMod, GetCGContext().GetCHIRBuilder().context.GetRefTy(valueTy),
            extraInfo: TypeExtraInfo(1u32))
        CreateStore(CGValue(storedValue, valueCGType), CGValue(typedPayload, addrType))
    }

    private func ShouldLoadGenericAggregateBoxSource(sourceValue: LLVMValueRef, valueTy: Type, valueCGType: CGType): Bool {
        if (!(valueTy.IsStruct() || valueTy.IsTuple() || valueTy.IsEnum() || valueTy.IsVArray() || valueTy.IsUnit())) {
            return false
        }
        if (let Some(enumCGType) <- (valueCGType as CGEnumType)) {
            if (enumCGType.IsOptionLikeRef()) {
                return false
            }
        }
        if (valueCGType.GetSize().isNone()) {
            return false
        }
        let rawTy = unsafe { LLVMTypeOf(sourceValue) }
        return !rawTy.isNull() && unsafe { LLVMGetTypeKind(rawTy) } == 12
    }

    public func GetLayoutSize32(chirTy: Type, cgType: CGType): LLVMValueRef {
        let sizeValue = if (chirTy.StripAllRefs().IsClass()) {
            cgMod.GetTypeSize(cgType.GetLayoutType())
        } else if (let Some(staticSize) <- cgType.GetSize()) {
            UInt64(staticSize)
        } else {
            return GetLayoutSize32ForAllocaGeneric(cgType, CreateTypeInfo(chirTy))
        }
        return unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), sizeValue, 0) }
    }

    public func GetLayoutSize_32(chirTy: Type): LLVMValueRef {
        let baseType = DeRef(chirTy)
        let cgType = CGType.GetOrCreate(cgMod, baseType)
        if (let Some(staticSize) <- cgType.GetSize()) {
            return unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), UInt64(staticSize), 0) }
        }
        return GetSizeFromTypeInfo(CreateTypeInfo(baseType))
    }

    public func GetLayoutSize_64(chirTy: Type): LLVMValueRef {
        let baseType = DeRef(chirTy)
        let cgType = CGType.GetOrCreate(cgMod, baseType)
        if (let Some(staticSize) <- cgType.GetSize()) {
            return unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), UInt64(staticSize), 0) }
        }
        let typeInfo = CreateTypeInfo(baseType)
        return CreateSExt(GetSizeFromTypeInfo(typeInfo), unsafe { LLVMInt64TypeInContext(GetLLVMContext().raw) })
    }

    public func GetSize_32(chirTy: Type): LLVMValueRef {
        let baseType = DeRef(chirTy)
        if (baseType.IsGeneric()) {
            let blocks = CreateAndInsertBasicBlocks(ArrayList<String>([GenNameForBB("get_ref_size"),
                GenNameForBB("get_non_ref_size"), GenNameForBB("get_size_exit")]))
            CreateCondBr(CreateTypeInfoIsReferenceCall(chirTy), blocks[0], blocks[1])
            SetInsertPoint(blocks[0])
            CreateBr(blocks[2])
            SetInsertPoint(blocks[1])
            let nonRefSize = GetLayoutSize_32(chirTy)
            CreateBr(blocks[2])
            SetInsertPoint(blocks[2])
            let sizePhi = CreatePHI(unsafe { LLVMInt32TypeInContext(GetLLVMContext().raw) })
            AddIncoming(sizePhi, ArrayList<LLVMValueRef>([
                unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), GetPtrSize(), 0) }, nonRefSize]),
                ArrayList<LLVMBasicBlockRef>([blocks[0], blocks[1]]))
            return sizePhi
        } else if (CGType.GetOrCreate(cgMod, chirTy).IsReference()) {
            return unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), GetPtrSize(), 0) }
        } else {
            return GetLayoutSize_32(chirTy)
        }
    }

    public func GetSize_64(chirTy: Type): LLVMValueRef {
        return CreateSExt(GetSize_32(chirTy), unsafe { LLVMInt64TypeInContext(GetLLVMContext().raw) })
    }

    // Mirrors CodeGen/CJNative/CJNativeIRBuilder.cpp:1876-1879 IRBuilder2::GetSize_Native.
    public func GetSize_Native(chirTy: Type): LLVMValueRef {
        return if (GetCGContext().GetCompileOptions().target.arch == ArchType.ARM32) {
            GetSize_32(chirTy)
        } else {
            GetSize_64(chirTy)
        }
    }

    public func GetSizeFromTypeInfo(typeInfo: LLVMValueRef): LLVMValueRef {
        let currentBlock = GetInsertBlock()
        let blockKey = currentBlock.toUIntNative()
        let typeInfoKey = typeInfo.toUIntNative()
        let cacheMap = GetCGContext().genericParamsSizeBlockLevelCacheMap
        if (cacheMap.contains(blockKey)) {
            let blockCacheMap = cacheMap[blockKey]
            if (blockCacheMap.contains(typeInfoKey)) {
                return blockCacheMap[typeInfoKey]
            }
        }
        let typeInfoType = CGType.GetOrCreateTypeInfoType(GetLLVMContext())
        let typeInfoPtrType = unsafe { LLVMPointerType(typeInfoType, 0u32) }
        let ptr = CreateStructGEP(typeInfoType, CreateBitCast(typeInfo, typeInfoPtrType), 4u32,
            name: "ti.size")
        var sizeValue = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString("") }.asResource()) {
            sizeValue = unsafe {
                LLVMBuildLoad2(builder.raw, LLVMInt32TypeInContext(GetLLVMContext().raw), ptr, nameCString.value)
            }
        }
        LLVMSetInstructionMetadata(GetLLVMContext(), sizeValue, "invariant.load",
            LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>()))
        if (!cacheMap.contains(blockKey)) {
            cacheMap[blockKey] = HashMap<UIntNative, LLVMValueRef>()
        }
        cacheMap[blockKey][typeInfoKey] = sizeValue
        return sizeValue
    }

    public func GetSize32(chirTy: Type, cgType: CGType): LLVMValueRef {
        let baseTy = chirTy.StripAllRefs()
        if (baseTy.IsGeneric()) {
            let blockNames = ArrayList<String>()
            blockNames.add("get_ref_size")
            blockNames.add("get_non_ref_size")
            blockNames.add("get_size_exit")
            let blocks = CreateAndInsertBasicBlocks(blockNames)
            if (blocks.size < 3) {
                return GetLayoutSize32(baseTy, cgType)
            }
            CreateCondBr(CreateTypeInfoIsReferenceCall(baseTy), blocks[0], blocks[1])
            SetInsertPoint(blocks[0])
            CreateBr(blocks[2])
            SetInsertPoint(blocks[1])
            let nonRefSize = GetLayoutSize32(baseTy, cgType)
            CreateBr(blocks[2])
            SetInsertPoint(blocks[2])
            let sizePhi = CreatePHI(unsafe { LLVMInt32TypeInContext(GetLLVMContext().raw) }, name: "generic.size")
            let values = ArrayList<LLVMValueRef>()
            values.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), 8u64, 0) })
            values.add(nonRefSize)
            let incomingBlocks = ArrayList<LLVMBasicBlockRef>()
            incomingBlocks.add(blocks[0])
            incomingBlocks.add(blocks[1])
            AddIncoming(sizePhi, values, incomingBlocks)
            return sizePhi
        }
        if (cgType.IsReference()) {
            return unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), 8u64, 0) }
        }
        return GetLayoutSize32(baseTy, cgType)
    }

    public func CreateTypeInfo(chirTy: Type): LLVMValueRef {
        // GAP_TODO(create-typeinfo-delegate-parity): C++ single-arg CreateTypeInfo
        // delegates to the map overload (CJNativeIntrinsicsCall.cpp:1465-1470).
        // Keep the pre-port selfhost lookup as a miss fallback until the upstream
        // CHIR generic canonicalization gap is fixed: meta_transformation
        // currently passes class generic DeclT as objectId 622 while the
        // CGFunction maps function generic DeclT as objectId 4030. After that
        // root is fixed, delegate here.
        let typeInfoProviders = if (let Some(currentFunction) <- cgFunction) {
            currentFunction.genericParamsMap
        } else {
            HashMap<Int64, (IRBuilder2) -> LLVMValueRef>()
        }
        let baseTy = chirTy.StripAllRefs()
        if (baseTy.IsGeneric() && !typeInfoProviders.contains(baseTy.objectId)) {
            if (let Some(currentFunction) <- cgFunction) {
                if (let Some(typeInfoProvider) <- FindGenericTypeInfoProvider(currentFunction, baseTy)) {
                    return typeInfoProvider(this)
                }
            }
            throw IllegalStateException("missing runtime TypeInfo mapping for generic type: " + baseTy.ToString())
        }
        return CreateTypeInfo(chirTy, typeInfoProviders)
    }

    private func FindGenericTypeInfoProvider(currentFunction: CGFunction,
        baseTy: Type): Option<(IRBuilder2) -> LLVMValueRef> {
        if (let Some(typeInfoProvider) <- currentFunction.genericParamsNameMap.get(baseTy.ToString())) {
            return Some(typeInfoProvider)
        }
        if (let Some(genericTy) <- (baseTy as GenericType)) {
            if (let Some(typeInfoProvider) <- currentFunction.genericParamsNameMap.get(genericTy.GetIdentifier())) {
                return Some(typeInfoProvider)
            }
            if (let Some(typeInfoProvider) <- currentFunction.genericParamsNameMap.get(genericTy.GetSrcCodeIdentifier())) {
                return Some(typeInfoProvider)
            }
        }
        return None
    }

    public func CreateTypeInfo(chirTy: Type, typeInfoProviders: HashMap<Int64, (IRBuilder2) -> LLVMValueRef>,
        canChangeBB!: Bool = true): LLVMValueRef {
        let baseTy = chirTy.StripAllRefs()
        if (baseTy.IsThis()) {
            let currentFunction = cgFunction ?? throw IllegalStateException("ThisType requires current CGFunction")
            let cgFuncType = currentFunction.GetCGFunctionType() ??
                throw IllegalStateException("ThisType requires CGFunctionType")
            if (cgFuncType.IsStaticMethodType()) {
                let thisTypeInfoIndex = cgFuncType.GetStaticMethodTypeInfoIndex() ??
                    throw IllegalStateException("static method ThisType has no TypeInfo parameter")
                return unsafe { LLVMGetParam(currentFunction.GetRawFunction(), UInt32(thisTypeInfoIndex)) }
            }
            if (!cgFuncType.IsMethodType()) {
                throw IllegalStateException("ThisType is used outside a method")
            }
            let thisArgIndex: UInt32 = if (currentFunction.IsSRet()) { 1u32 } else { 0u32 }
            return GetTypeInfoFromObject(unsafe { LLVMGetParam(currentFunction.GetRawFunction(), thisArgIndex) })
        }

        let insertFunction = GetInsertFunction()
        let functionKey = insertFunction.toUIntNative()
        let cacheMaps = GetCGContext().genericParamsCacheMap
        if (!cacheMaps.contains(functionKey)) {
            cacheMaps[functionKey] = HashMap<Int64, LLVMValueRef>()
        }
        let cacheMap = cacheMaps[functionKey]
        if (let Some(cached) <- cacheMap.get(baseTy.objectId)) {
            return cached
        }

        var result = LLVMNullValue()
        try (debugLocGuard = TemporarilySetDebugLocInThisScope(this, LLVMNullMetadata())) {
            if (let Some(typeInfoProvider) <- typeInfoProviders.get(baseTy.objectId)) {
                let currentBlock = GetInsertBlock()
                let currentInsertPoint = unsafe { LLVMSelfhostGetInsertPointInstruction(builder.raw) }
                if (canChangeBB) {
                    SetInsertPointForPreparingTypeInfo()
                }
                result = typeInfoProvider(this)
                RestoreInsertPoint(currentBlock, currentInsertPoint)
            } else if (baseTy.IsGeneric()) {
                throw IllegalStateException("missing runtime TypeInfo mapping for generic type: " + baseTy.ToString())
            } else {
                let cgTy = CGType.GetOrCreate(cgMod, baseTy)
                if (cgTy.IsConcrete() || cgTy.IsStaticGI()) {
                    result = cgTy.GetOrCreateTypeInfo()
                } else {
                    let (typeTemplate, typeArgs) = IRBuilderRuntimeTypeTemplateAndArgs(baseTy)
                    if (typeArgs.isEmpty()) {
                        throw IllegalStateException("missing runtime TypeInfo arguments for generic-related type: " +
                            baseTy.ToString())
                    }
                    let currentBlock = GetInsertBlock()
                    let currentInsertPoint = unsafe { LLVMSelfhostGetInsertPointInstruction(builder.raw) }
                    if (canChangeBB) {
                        SetInsertPointForPreparingTypeInfo()
                    }
                    let typeInfoArray = CreateTypeInfoArray(typeArgs, typeInfoProviders)
                    let args = ArrayList<LLVMValueRef>()
                    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
                    args.add(CreateBitCast(typeTemplate, i8PtrType, name: "ti.template"))
                    args.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), UInt64(typeArgs.size), 0) })
                    args.add(typeInfoArray)
                    result = CallGetTypeInfoIntrinsic(args)
                    RestoreInsertPoint(currentBlock, currentInsertPoint)
                }
            }
        }

        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())
        let typeInfoPtrPtrType = unsafe { LLVMPointerType(typeInfoPtrType, 0u32) }
        if (!result.isNull() && !unsafe { LLVMIsAGlobalVariable(result) }.isNull() &&
            unsafe { LLVMTypeOf(result) }.toUIntNative() == typeInfoPtrPtrType.toUIntNative()) {
            result = CreateLoad(typeInfoPtrType, result)
        }
        cacheMap[baseTy.objectId] = result
        return result
    }

    public func GetTypeArgsFromTypeInfo(typeInfo: LLVMValueRef): LLVMValueRef {
        let typeInfoType = CGType.GetOrCreateTypeInfoType(GetLLVMContext())
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        var typedTypeInfo = LLVMNullValue()
        try (typedTypeInfoName = unsafe { LibC.mallocCString("") }.asResource()) {
            typedTypeInfo = unsafe { LLVMBuildBitCast(builder.raw, typeInfo, typeInfoPtrType, typedTypeInfoName.value) }
        }
        let typeArgsPtr = CreateStructGEP(typeInfoType, typedTypeInfo, 12u32, name: "ti.typeArgs")
        var typeArgsRaw = LLVMNullValue()
        try (typeArgsName = unsafe { LibC.mallocCString("") }.asResource()) {
            typeArgsRaw = unsafe { LLVMBuildLoad2(builder.raw, i8PtrType, typeArgsPtr, typeArgsName.value) }
        }
        let metadata = LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>())
        LLVMSetInstructionMetadata(GetLLVMContext(), typeArgsRaw, "invariant.load", metadata)
        var typedTypeArgs = LLVMNullValue()
        try (typedTypeArgsName = unsafe { LibC.mallocCString("") }.asResource()) {
            typedTypeArgs = unsafe {
                LLVMBuildBitCast(builder.raw, typeArgsRaw, unsafe { LLVMPointerType(typeInfoPtrType, 0u32) },
                    typedTypeArgsName.value)
            }
        }
        return typedTypeArgs
    }

    // Mirrors CodeGen/CJNative/CJNativeIRBuilder.cpp:1929-1939 IRBuilder2::GetTypeForTypeParameter.
    public func GetTypeForTypeParameter(typeInfo: LLVMValueRef): LLVMValueRef {
        let typeInfoType = CGType.GetOrCreateTypeInfoType(GetLLVMContext())
        let typeInfoPtrType = unsafe { LLVMPointerType(typeInfoType, 0u32) }
        let typedTypeInfo = CreateBitCast(typeInfo, typeInfoPtrType)
        let namePtr = CreateStructGEP(typeInfoType, typedTypeInfo, 0u32)
        let nameType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let typeInfoName = CreateLoad(nameType, namePtr, name: "ti.typeInfoName")
        LLVMSetInstructionMetadata(GetLLVMContext(), typeInfoName, "invariant.load",
            LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>()))
        return typeInfoName
    }

    public func GetTypeInfoFromTiArray(tiArray: LLVMValueRef, index: Int64, name!: String = ""): LLVMValueRef {
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())
        let indices = ArrayList<LLVMValueRef>()
        indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), UInt64(index), 0) })
        let typeInfoSlot = CreateInBoundsGEP(typeInfoPtrType, tiArray, indices)
        var typeInfo = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            typeInfo = unsafe { LLVMBuildLoad2(builder.raw, typeInfoPtrType, typeInfoSlot, nameCString.value) }
        }
        let metadata = LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>())
        LLVMSetInstructionMetadata(GetLLVMContext(), typeInfo, "invariant.load", metadata)
        return typeInfo
    }

    public func GetTypeInfoFromTiArrayPlain(tiArray: LLVMValueRef, index: Int64, name!: String = ""): LLVMValueRef {
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())
        let indices = ArrayList<LLVMValueRef>()
        indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), UInt64(index), 0) })
        let typeInfoSlot = CreateGEP(typeInfoPtrType, tiArray, indices)
        return CreateLoad(typeInfoPtrType, typeInfoSlot, name: name)
    }

    public func GetTypeInfoFromTypeInfoArgs(typeInfo: LLVMValueRef, index: Int64): LLVMValueRef {
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())
        let typeArgs = GetTypeArgsFromTypeInfo(typeInfo)
        let indices = ArrayList<LLVMValueRef>()
        indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(GetLLVMContext().raw), UInt64(index), 0) })
        let typeInfoSlot = CreateInBoundsGEP(typeInfoPtrType, typeArgs, indices, name: "ti.arg")
        var argTypeInfo = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString("ti.arg") }.asResource()) {
            argTypeInfo = unsafe { LLVMBuildLoad2(builder.raw, typeInfoPtrType, typeInfoSlot, nameCString.value) }
        }
        let metadata = LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>())
        LLVMSetInstructionMetadata(GetLLVMContext(), argTypeInfo, "invariant.load", metadata)
        return argTypeInfo
    }

    public func GetTypeInfoFromObject(obj: LLVMValueRef): LLVMValueRef {
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())
        let typeInfoSlotType = unsafe { LLVMPointerType(typeInfoPtrType, 1u32) }
        let typeInfoSlot = CreateBitCast(obj, typeInfoSlotType, name: "obj.ti.slot")
        var typeInfo = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString("ti") }.asResource()) {
            typeInfo = unsafe { LLVMBuildLoad2(builder.raw, typeInfoPtrType, typeInfoSlot, nameCString.value) }
        }
        let metadata = LLVMCreateMDTuple(GetLLVMContext(), ArrayList<LLVMMetadataRef>())
        LLVMSetInstructionMetadata(GetLLVMContext(), typeInfo, "invariant.load", metadata)
        return typeInfo
    }

    private func IRBuilderRuntimeTypeTemplateAndArgs(chirTy: Type): (LLVMValueRef, ArrayList<Type>) {
        let typeArgs = ArrayList<Type>()
        if (let Some(funcTy) <- (chirTy as FuncType)) {
            typeArgs.add(funcTy.GetReturnType())
            for (paramTy in funcTy.GetParamTypes()) {
                typeArgs.add(paramTy)
            }
            return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
        }
        if (let Some(tupleTy) <- (chirTy as TupleType)) {
            for (typeArg in tupleTy.GetTypeArgs()) {
                typeArgs.add(typeArg)
            }
            return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
        }
        if (let Some(varrayTy) <- (chirTy as VArrayType)) {
            var idx: UInt64 = 0u64
            while (idx < varrayTy.size) {
                typeArgs.add(varrayTy.GetElementType())
                idx++
            }
            return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
        }
        if (let Some(rawArrayTy) <- (chirTy as RawArrayType)) {
            typeArgs.add(rawArrayTy.GetElementType())
            return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
        }
        if (let Some(cPointerTy) <- (chirTy as CPointerType)) {
            typeArgs.add(cPointerTy.GetElementType())
            return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
        }
        if (let Some(boxTy) <- (chirTy as BoxType)) {
            typeArgs.add(boxTy.GetBaseType())
            return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
        }
        if (let Some(customTy) <- (chirTy as CustomType)) {
            let typeTemplate = EnsureSourceGenericTypeTemplate(cgMod, IRBuilderSourceCustomType(customTy))
            if (IsAutoEnvBaseType(customTy)) {
                let autoEnvTy = if (IsAutoEnvInstBaseType(customTy)) {
                    if (let Some(classTy) <- (customTy as ClassType)) {
                        classTy.GetSuperClassTy() ?? classTy
                    } else {
                        customTy
                    }
                } else {
                    customTy
                }
                let autoEnvArgs = autoEnvTy.GetGenericArgs()
                if (!autoEnvArgs.isEmpty()) {
                    let paramTypes = ArrayList<Type>()
                    var idx: Int64 = 0
                    while (idx + 1 < autoEnvArgs.size) {
                        paramTypes.add(autoEnvArgs[idx])
                        idx++
                    }
                    typeArgs.add(FuncType(paramTypes, autoEnvArgs[autoEnvArgs.size - 1]))
                }
            } else {
                for (typeArg in customTy.GetGenericArgs()) {
                    typeArgs.add(typeArg)
                }
            }
            return (typeTemplate, typeArgs)
        }
        return (CGType.GetOrCreate(cgMod, chirTy).GetOrCreateTypeTemplate(), typeArgs)
    }

    private func IRBuilderSourceCustomType(customTy: CustomType): CustomType {
        if (let Some(defTy) <- customTy.GetCustomTypeDef().GetType()) {
            return StaticCast<CustomType>(defTy)
        }
        return customTy
    }

    public func CallGetTypeInfoIntrinsic(args: ArrayList<LLVMValueRef>): LLVMValueRef {
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i8PtrPtrType = unsafe { LLVMPointerType(i8PtrType, 0u32) }
        let fixedArgs = ArrayList<LLVMValueRef>()
        fixedArgs.add(CreateBitCast(args[0], i8PtrType, name: "ti.template.raw"))
        fixedArgs.add(args[1])
        fixedArgs.add(CreateBitCast(args[2], i8PtrPtrType, name: "ti.args.i8"))
        return CreateIntrinsicCallNoInvoke(GET_TYPE_INFO_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), fixedArgs, name: "ti")
    }

    public func CreateTypeInfoArray(typeArgs: ArrayList<Type>): LLVMValueRef {
        let typeInfoProviders = if (let Some(currentFunction) <- cgFunction) {
            currentFunction.genericParamsMap
        } else {
            HashMap<Int64, (IRBuilder2) -> LLVMValueRef>()
        }
        return CreateTypeInfoArray(typeArgs, typeInfoProviders)
    }

    public func CreateTypeInfoArray(typeArgs: ArrayList<Type>,
        typeInfoProviders: HashMap<Int64, (IRBuilder2) -> LLVMValueRef>): LLVMValueRef {
        let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(GetLLVMContext())
        let arrayType = unsafe { LLVMArrayType(typeInfoPtrType, UInt32(typeArgs.size)) }
        let slot = CreateEntryAlloca(arrayType, name: "ti.args")
        let storeInst = CreateStore(unsafe { LLVMConstNull(arrayType) }, slot)
        let typeInfoElements = ArrayList<LLVMValueRef>()
        var hasStaticTypeInfo = false
        let i32Type = unsafe { LLVMInt32TypeInContext(GetLLVMContext().raw) }
        var idx: Int64 = 0
        while (idx < typeArgs.size) {
            let argTy = typeArgs[idx].StripAllRefs()
            let argCGType = CGType.GetOrCreate(cgMod, argTy)
            if (argCGType.IsDynamicGI()) {
                typeInfoElements.add(unsafe { LLVMConstNull(typeInfoPtrType) })
                let rawTypeInfo = CreateTypeInfo(argTy, typeInfoProviders)
                let argTypeInfo = CreateBitCast(rawTypeInfo, typeInfoPtrType, name: "ti.arg.cast")
                let indices = ArrayList<LLVMValueRef>()
                indices.add(unsafe { LLVMConstInt(i32Type, 0u64, 0) })
                indices.add(unsafe { LLVMConstInt(i32Type, UInt64(idx), 0) })
                let argSlot = CreateInBoundsGEP(arrayType, slot, indices, name: "ti.arg")
                CreateStore(argTypeInfo, argSlot)
            } else {
                typeInfoElements.add(unsafe {
                    LLVMConstBitCast(argCGType.GetOrCreateTypeInfo(), typeInfoPtrType)
                })
                hasStaticTypeInfo = true
            }
            idx++
        }
        var realConstantArray = LLVMNullValue()
        if (typeInfoElements.isEmpty()) {
            realConstantArray = unsafe { LLVMConstArray(typeInfoPtrType, CPointer<LLVMValueRef>(), 0u32) }
        } else {
            try (valuePtr = LibC.malloc<LLVMValueRef>(count: typeInfoElements.size).asResource()) {
                var elementIdx: Int64 = 0
                while (elementIdx < typeInfoElements.size) {
                    unsafe { (valuePtr.value + elementIdx).write(typeInfoElements[elementIdx]) }
                    elementIdx++
                }
                realConstantArray = unsafe {
                    LLVMConstArray(typeInfoPtrType, valuePtr.value, UInt32(typeInfoElements.size))
                }
            }
        }
        if (!hasStaticTypeInfo) {
            unsafe { LLVMInstructionEraseFromParent(storeInst) }
        } else {
            unsafe { LLVMSetOperand(storeInst, 0u32, realConstantArray) }
        }
        return slot
    }

    public func CreateTypeInfoIsReferenceCall(chirTy: Type): LLVMValueRef {
        let baseTy = chirTy.StripAllRefs()
        if (!baseTy.IsGeneric()) {
            return if (CGType.GetOrCreate(cgMod, baseTy).IsReference()) { GetTrue() } else { GetFalse() }
        }
        let typeInfoValue = CreateTypeInfo(baseTy)
        return CreateTypeInfoIsReferenceCall(typeInfoValue)
    }

    public func CreateTypeInfoIsReferenceCall(typeInfoValue: LLVMValueRef): LLVMValueRef {
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(GetLLVMContext().raw), 0u32) }
        let args = ArrayList<LLVMValueRef>()
        args.add(CreateBitCast(typeInfoValue, i8PtrType, name: "isref.ti"))
        return CreateIntrinsicCallNoInvoke(IS_REFERENCE_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), args, name: "isref")
    }

    private func GetRuntimeExceptionHelperType(): LLVMTypeRef {
        let paramTypes = ArrayList<LLVMTypeRef>()
        paramTypes.add(GetCjStringRefType())
        return MakeFunctionType(CGType.GetRefType(GetLLVMContext()), paramTypes)
    }

    private func GetThrowExceptionFunctionType(): LLVMTypeRef {
        let paramTypes = ArrayList<LLVMTypeRef>()
        paramTypes.add(CGType.GetRefType(GetLLVMContext()))
        return MakeFunctionType(unsafe { LLVMVoidTypeInContext(GetLLVMContext().raw) }, paramTypes)
    }

    private func GetCjStringRefType(): LLVMTypeRef {
        // `String` is a fully-sized struct, so a String* parameter lives in address space 0, not 1
        // (mirror C++ CGFunctionType.cpp:117-125: getPointerTo(cgType->GetSize() ? 0U : 1U)).
        return unsafe { LLVMPointerType(GetCGContext().GetCjStringType(), 0u32) }
    }

    private func GetOrInsertRuntimeFunction(name: String, functionType: LLVMTypeRef): LLVMValueRef {
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            var result = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
                result = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
                if (result.isNull()) {
                    result = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
                }
            }
            return result
        }
        throw IllegalStateException("cannot create runtime function without an LLVM module")
    }

    private func MakeFunctionType(returnType: LLVMTypeRef, paramTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
        if (paramTypes.isEmpty()) {
            return unsafe { LLVMFunctionType(returnType, CPointer<LLVMTypeRef>(), 0u32, 0) }
        }
        var result = LLVMNullType()
        try (paramPtr = LibC.malloc<LLVMTypeRef>(count: paramTypes.size).asResource()) {
            var idx: Int64 = 0
            while (idx < paramTypes.size) {
                unsafe { (paramPtr.value + idx).write(paramTypes[idx]) }
                idx++
            }
            result = unsafe { LLVMFunctionType(returnType, paramPtr.value, UInt32(paramTypes.size), 0) }
        }
        return result
    }

    private func MakeFunctionTypeFromArgs(returnType: LLVMTypeRef, args: ArrayList<LLVMValueRef>): LLVMTypeRef {
        let paramTypes = ArrayList<LLVMTypeRef>()
        for (arg in args) {
            paramTypes.add(unsafe { LLVMTypeOf(arg) })
        }
        return MakeFunctionType(returnType, paramTypes)
    }

    private func CastIntegerToInt64(value: LLVMValueRef): LLVMValueRef {
        let valueType = unsafe { LLVMTypeOf(value) }
        let bitWidth = unsafe { LLVMGetIntTypeWidth(valueType) }
        if (bitWidth == 64u32) {
            return value
        }
        let int64Type = unsafe { LLVMInt64TypeInContext(GetLLVMContext().raw) }
        if (bitWidth < 64u32) {
            return CreateSExt(value, int64Type, name: "array.length.i64")
        }
        return CreateTrunc(value, int64Type, name: "array.length.i64")
    }

    private func GetRawArrayElementSize(rawArrayTy: RawArrayType): Int64 {
        let elementCGType = CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType())
        if (let Some(elementSize) <- elementCGType.GetSize()) {
            return elementSize
        }
        return 0
    }

    private func GetRawArrayElementSizeValue(rawArrayTy: RawArrayType): LLVMValueRef {
        let elementCGType = CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType())
        let elementSize = if (let Some(size) <- elementCGType.GetSize()) {
            size
        } else {
            Int64(cgMod.GetTypeSize(elementCGType.GetLLVMType()))
        }
        return unsafe { LLVMConstInt(LLVMInt64TypeInContext(GetLLVMContext().raw), UInt64(elementSize), 0) }
    }

    public func CreateCopyTo(arrayCopyToInfo: ArrayCopyToInfo): Unit {
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 1u32) }
        let srcArrPtr = CreateBitCast(arrayCopyToInfo.srcArrPtr, i8PtrType, name: "src.arr.ptr.i8")
        let dstArrPtr = CreateBitCast(arrayCopyToInfo.dstArrPtr, i8PtrType, name: "dst.arr.ptr.i8")
        let srcIndices = ArrayList<LLVMValueRef>()
        srcIndices.add(arrayCopyToInfo.srcIndex)
        let dstIndices = ArrayList<LLVMValueRef>()
        dstIndices.add(arrayCopyToInfo.dstIndex)
        let srcArrI8Ptr = CreateInBoundsGEP(i8Type, srcArrPtr, srcIndices, name: "src.arr.i8")
        let dstArrI8Ptr = CreateInBoundsGEP(i8Type, dstArrPtr, dstIndices, name: "dst.arr.i8")
        let elemCGType = arrayCopyToInfo.elemType
        match (elemCGType.GetSize()) {
            case None =>
                let sizeType = GetSizetLLVMType()
                let dataSize = CreateZExtOrTrunc(arrayCopyToInfo.dataSize, sizeType)
                _ = CreateArrayCopyIntrinsic(ARRAY_COPY_GENERIC_INTRINSIC_NAME, arrayCopyToInfo.dstBP, dstArrI8Ptr,
                    arrayCopyToInfo.srcBP, srcArrI8Ptr, dataSize)
            case Some(_) =>
                match (IsLLVMTypeContainsRef(elemCGType.GetLLVMType())) {
                    case true =>
                        let refType = CGType.GetRefType(GetLLVMContext())
                        let intrinsicName = if (elemCGType.GetLLVMType().toUIntNative() == refType.toUIntNative()) {
                            ARRAY_COPY_REF_INTRINSIC_NAME
                        } else {
                            ARRAY_COPY_STRUCT_INTRINSIC_NAME
                        }
                        let sizeType = GetSizetLLVMType()
                        let dataSize = CreateZExtOrTrunc(arrayCopyToInfo.dataSize, sizeType)
                        _ = CreateArrayCopyIntrinsic(intrinsicName, arrayCopyToInfo.dstBP, dstArrI8Ptr,
                            arrayCopyToInfo.srcBP, srcArrI8Ptr, dataSize)
                    case _ =>
                        let align = cgMod.GetPrefTypeAlignment(elemCGType.GetLLVMType())
                        _ = CreateMemMove(dstArrI8Ptr, align, srcArrI8Ptr, align, arrayCopyToInfo.dataSize)
                }
        }
    }

    private func CreateArrayCopyTo(rawArrayTy: RawArrayType, srcArray: LLVMValueRef, dstArray: LLVMValueRef,
        srcArrPtr: LLVMValueRef, dstArrPtr: LLVMValueRef, dataSize: LLVMValueRef, srcIndex: LLVMValueRef,
        dstIndex: LLVMValueRef): LLVMValueRef {
        let i8Type = unsafe { LLVMInt8TypeInContext(GetLLVMContext().raw) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 1u32) }
        let srcI8Ptr = CreatePointerCast(srcArrPtr, i8PtrType, name: "src.arr.i8")
        let dstI8Ptr = CreatePointerCast(dstArrPtr, i8PtrType, name: "dst.arr.i8")
        let srcIndices = ArrayList<LLVMValueRef>()
        srcIndices.add(srcIndex)
        let dstIndices = ArrayList<LLVMValueRef>()
        dstIndices.add(dstIndex)
        let srcDataPtr = CreateGEP(i8Type, srcI8Ptr, srcIndices, name: "src.arr.data.i8")
        let dstDataPtr = CreateGEP(i8Type, dstI8Ptr, dstIndices, name: "dst.arr.data.i8")
        let elementCGType = CGType.GetOrCreate(cgMod, rawArrayTy.GetElementType())
        if (elementCGType.GetSize().isNone()) {
            return CreateArrayCopyIntrinsic(ARRAY_COPY_GENERIC_INTRINSIC_NAME, dstArray, dstDataPtr, srcArray, srcDataPtr,
                dataSize)
        }
        if (IsLLVMTypeContainsRef(elementCGType.GetLLVMType())) {
            let intrinsicName = if (elementCGType.IsReference()) {
                ARRAY_COPY_REF_INTRINSIC_NAME
            } else {
                ARRAY_COPY_STRUCT_INTRINSIC_NAME
            }
            return CreateArrayCopyIntrinsic(intrinsicName, dstArray, dstDataPtr, srcArray, srcDataPtr, dataSize)
        }
        return CreateMemMove(dstDataPtr, 8u32, srcDataPtr, 8u32, dataSize)
    }

    private func CreateArrayCopyIntrinsic(intrinsicName: String, dstBase: LLVMValueRef, dstData: LLVMValueRef,
        srcBase: LLVMValueRef, srcData: LLVMValueRef, dataSize: LLVMValueRef): LLVMValueRef {
        let overloadedTypes = ArrayList<LLVMTypeRef>()
        overloadedTypes.add(unsafe { LLVMTypeOf(dataSize) })
        let args = ArrayList<LLVMValueRef>()
        args.add(CreatePointerCast(dstBase, CGType.GetRefType(GetLLVMContext()), name: "array.copy.dst.base"))
        args.add(CreatePointerCast(dstData, CGType.GetRefType(GetLLVMContext()), name: "array.copy.dst"))
        args.add(CreatePointerCast(srcBase, CGType.GetRefType(GetLLVMContext()), name: "array.copy.src.base"))
        args.add(CreatePointerCast(srcData, CGType.GetRefType(GetLLVMContext()), name: "array.copy.src"))
        args.add(dataSize)
        return CreateIntrinsicCall(intrinsicName, overloadedTypes, args)
    }

    public func IsLLVMTypeContainsRef(llvmTy: LLVMTypeRef): Bool {
        if (llvmTy.isNull()) {
            return false
        }
        let kind = unsafe { LLVMGetTypeKind(llvmTy) }
        if (kind == LLVM_POINTER_TYPE_KIND) {
            return unsafe { LLVMGetPointerAddressSpace(llvmTy) } == 1u32
        }
        if (kind == LLVM_STRUCT_TYPE_KIND) {
            let elementCount = unsafe { LLVMCountStructElementTypes(llvmTy) }
            if (elementCount == 0u32) {
                return false
            }
            var result = false
            try (elementPtr = LibC.malloc<LLVMTypeRef>(count: Int64(elementCount)).asResource()) {
                unsafe { LLVMGetStructElementTypes(llvmTy, elementPtr.value) }
                var idx: Int64 = 0
                while (idx < Int64(elementCount)) {
                    if (IsLLVMTypeContainsRef(unsafe { (elementPtr.value + idx).read() })) {
                        result = true
                        break
                    }
                    idx++
                }
            }
            return result
        }
        if (kind == LLVM_ARRAY_TYPE_KIND || kind == LLVM_VECTOR_TYPE_KIND || kind == LLVM_SCALABLE_VECTOR_TYPE_KIND) {
            return IsLLVMTypeContainsRef(unsafe { LLVMGetElementType(llvmTy) })
        }
        return false
    }

    private func LookupIntrinsicID(intrinsicName: String): UInt32 {
        var intrinsicID = 0u32
        try (nameCString = unsafe { LibC.mallocCString(intrinsicName) }.asResource()) {
            intrinsicID = unsafe { LLVMLookupIntrinsicID(nameCString.value, UIntNative(intrinsicName.size)) }
        }
        return intrinsicID
    }

    private func IsBasicBlockNamed(block: LLVMBasicBlockRef, name: String): Bool {
        if (block.isNull()) {
            return false
        }
        let blockName = unsafe { LLVMGetBasicBlockName(block) }
        if (blockName.isNull()) {
            return false
        }
        var result = false
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe { strcmp(blockName, nameCString.value) } == 0
        }
        return result
    }

    private func FindOrCreatePrepTiAfterAllocas(parentFunction: LLVMValueRef,
        allocasBlock: LLVMBasicBlockRef): LLVMBasicBlockRef {
        let nextBlock = unsafe { LLVMGetNextBasicBlock(allocasBlock) }
        if (!nextBlock.isNull() && IsBasicBlockNamed(nextBlock, "prepTi")) {
            return nextBlock
        }
        let oldEntry = if (nextBlock.isNull()) {
            unsafe { LLVMGetEntryBasicBlock(parentFunction) }
        } else {
            nextBlock
        }
        let created = CreateEntryBasicBlock(parentFunction, "prepTi")
        unsafe { LLVMMoveBasicBlockAfter(created, allocasBlock) }
        let terminator = unsafe { LLVMGetBasicBlockTerminator(allocasBlock) }
        CJC_ASSERT(!terminator.isNull())
        unsafe { LLVMSetSuccessor(terminator, 0u32, created) }
        SetInsertPoint(created)
        if (!oldEntry.isNull()) {
            CreateBr(oldEntry)
        }
        return created
    }

    private func ApplyFastMathIfNeeded(value: LLVMValueRef): LLVMValueRef {
        // LLVM-15 C API has no fast-math-flag accessor; skip (optimization hint only).
        return value
    }

    private func IsFloatOperand(ty: Option<Type>): Bool {
        if (let Some(valueType) <- ty) {
            return valueType.IsFloat()
        }
        return false
    }

    private func IsUnsignedOperand(ty: Option<Type>): Bool {
        if (let Some(valueType) <- ty) {
            return valueType.IsUnsignedInteger()
        }
        return false
    }

    private func SelectLessThanPredicate(ty: Option<Type>): LLVMIntPredicate {
        return if (IsUnsignedOperand(ty)) { LLVMIntPredicate.ULT } else { LLVMIntPredicate.SLT }
    }

    private func SelectLessEqualPredicate(ty: Option<Type>): LLVMIntPredicate {
        return if (IsUnsignedOperand(ty)) { LLVMIntPredicate.ULE } else { LLVMIntPredicate.SLE }
    }

    private func SelectGreaterThanPredicate(ty: Option<Type>): LLVMIntPredicate {
        return if (IsUnsignedOperand(ty)) { LLVMIntPredicate.UGT } else { LLVMIntPredicate.SGT }
    }

    private func SelectGreaterEqualPredicate(ty: Option<Type>): LLVMIntPredicate {
        return if (IsUnsignedOperand(ty)) { LLVMIntPredicate.UGE } else { LLVMIntPredicate.SGE }
    }
}

public class TemporarilySetDebugLocInThisScope <: Resource {
    private let irBuilder: IRBuilder2
    private let oldLocation: LLVMMetadataRef
    private var closed: Bool = false

    public init(irBuilder: IRBuilder2, newLocation: LLVMMetadataRef) {
        this.irBuilder = irBuilder
        oldLocation = unsafe { LLVMGetCurrentDebugLocation2(irBuilder.GetBuilder().raw) }
        unsafe { LLVMSetCurrentDebugLocation2(irBuilder.GetBuilder().raw, newLocation) }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        unsafe { LLVMSetCurrentDebugLocation2(irBuilder.GetBuilder().raw, oldLocation) }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}
