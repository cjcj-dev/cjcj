package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.DynamicDispatch
import cangjie_compiler::chir.DynamicDispatchWithException
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Invoke
import cangjie_compiler::chir.InvokeStatic
import cangjie_compiler::chir.InvokeStaticWithException
import cangjie_compiler::chir.InvokeWithException
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value

private let GET_VTABLE_FUNC_INTRINSIC_NAME: String = "llvm.cj.get.vtable.func"
private let GET_MTABLE_FUNC_INTRINSIC_NAME: String = "llvm.cj.get.mtable.func"
private let GET_METHOD_OUTERTYPE_INTRINSIC_NAME: String = "llvm.cj.get.method.outertype"

public func GenerateInvokeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(invokeExpr) <- (chirExpr as Invoke)) {
        return GenerateResolvedInvoke(irBuilder, invokeExpr.GetObject(), invokeExpr.GetMethodName(),
            invokeExpr.GetArgs())
    }
    if (let Some(invokeWithExceptionExpr) <- (chirExpr as InvokeWithException)) {
        return GenerateResolvedInvoke(irBuilder, invokeWithExceptionExpr.GetObject(),
            invokeWithExceptionExpr.GetMethodName(), invokeWithExceptionExpr.GetArgs())
    }
    if (let Some(invokeStaticExpr) <- (chirExpr as InvokeStatic)) {
        return GenerateResolvedStaticInvoke(irBuilder, invokeStaticExpr, invokeStaticExpr.GetArgs())
    }
    if (let Some(invokeStaticWithExceptionExpr) <- (chirExpr as InvokeStaticWithException)) {
        return GenerateResolvedStaticInvoke(irBuilder, invokeStaticWithExceptionExpr,
            invokeStaticWithExceptionExpr.GetArgs())
    }
    return LLVMNullValue()
}

private func GenerateResolvedInvoke(irBuilder: IRBuilder2, objectValue: Value, methodName: String,
    args: ArrayList<Value>): LLVMValueRef {
    if (let Some(objectTy) <- objectValue.GetType()) {
        if (let Some(callee) <- FindMethodByName(objectTy, methodName)) {
            return GenerateVirtualApply(irBuilder, objectTy, methodName, callee, args)
        }
    }
    return LLVMNullValue()
}

private func GenerateVirtualApply(irBuilder: IRBuilder2, ownerTy: Type, methodName: String, callee: Function,
    args: ArrayList<Value>): LLVMValueRef {
    let cgFunc = irBuilder.GetCGModule().GetOrInsertCGFunction(callee)
    let cgFuncType = cgFunc.GetCGFunctionType() ?? return LLVMNullValue()
    if (args.isEmpty()) {
        return LLVMNullValue()
    }
    let argValues = ArrayList<CGValue>()
    for (arg in args) {
        argValues.add(irBuilder.GetCGModule().MaterializeValue(irBuilder, arg))
    }
    if (IsAutoEnvType(ownerTy)) {
        let calleePtr = BuildAutoEnvCallee(irBuilder, argValues[0], ownerTy, methodName, cgFuncType)
        return irBuilder.CreateCallOrInvoke(cgFuncType, calleePtr, argValues, name: "call")
    }
    let methodIndex = FindMethodIndex(ownerTy, methodName)
    let (calleePtr, methodTypeInfoArg) = BuildVirtualCallee(irBuilder, argValues[0], ownerTy, methodIndex, cgFuncType)
    return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(cgFuncType, calleePtr, argValues,
        Some(methodTypeInfoArg), name: "call")
}

private func BuildAutoEnvCallee(irBuilder: IRBuilder2, objectValue: CGValue, ownerTy: Type, methodName: String,
    cgFuncType: CGFunctionType): LLVMValueRef {
    let llvmContext = irBuilder.GetLLVMContext().raw
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(llvmContext), 0u32) }
    let i8PtrSlotType = unsafe { LLVMPointerType(i8PtrType, 1u32) }
    let payload = irBuilder.GetPayloadFromObject(objectValue.GetRawValue())
    let typedPayload = irBuilder.CreateBitCast(payload, i8PtrSlotType, name: "autoenv.payload")
    let indices = ArrayList<LLVMValueRef>()
    indices.add(unsafe {
        LLVMConstInt(LLVMInt32TypeInContext(llvmContext), FindAutoEnvPayloadMethodIndex(ownerTy, methodName), 0)
    })
    let slot = irBuilder.CreateGEP(i8PtrType, typedPayload, indices, name: "autoenv.fn.addr")
    let rawCallee = irBuilder.CreateLoad(i8PtrType, slot, name: "autoenv.fn")
    return irBuilder.CreateBitCast(rawCallee,
        unsafe { LLVMPointerType(cgFuncType.GetLLVMFunctionType(), 0u32) }, name: "autoenv.fn.cast")
}

private func FindAutoEnvPayloadMethodIndex(ownerTy: Type, methodName: String): UInt64 {
    if (IsAutoEnvInstBaseType(ownerTy)) {
        return 1u64
    }
    if (let Some(customTy) <- (ownerTy.StripAllRefs() as CustomType)) {
        var idx: UInt64 = 0u64
        for (method in customTy.GetCustomTypeDef().GetMethods()) {
            if (MethodNameMatches(method, methodName)) {
                return idx
            }
            idx++
        }
    }
    return 0u64
}

private func BuildVirtualCallee(irBuilder: IRBuilder2, objectValue: CGValue, ownerTy: Type, methodIndex: Int64,
    cgFuncType: CGFunctionType): (LLVMValueRef, LLVMValueRef) {
    let llvmContext = irBuilder.GetLLVMContext().raw
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(llvmContext), 0u32) }
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
    let typeInfoSlotType = unsafe { LLVMPointerType(typeInfoPtrType, 1u32) }
    let objectTypeInfoSlot = irBuilder.CreateBitCast(objectValue.GetRawValue(), typeInfoSlotType, name: "invoke.ti.slot")
    let objectTypeInfo = irBuilder.CreateLoad(typeInfoPtrType, objectTypeInfoSlot, name: "invoke.ti")
    let objectTypeInfoRaw = irBuilder.CreateBitCast(objectTypeInfo, i8PtrType, name: "invoke.ti.raw")
    let ownerTypeInfo = CGType.GetOrCreate(irBuilder.GetCGModule(), ownerTy.StripAllRefs()).GetOrCreateTypeInfo()
    let ownerTypeInfoRaw = irBuilder.CreateBitCast(ownerTypeInfo, i8PtrType, name: "invoke.owner.ti")
    let isInterfaceCall = IsInterfaceOwnerType(ownerTy)
    let rawCallee = if (isInterfaceCall) {
        let intrinsicArgs = ArrayList<LLVMValueRef>()
        intrinsicArgs.add(objectTypeInfoRaw)
        intrinsicArgs.add(ownerTypeInfoRaw)
        intrinsicArgs.add(irBuilder.GetInt64(methodIndex))
        irBuilder.CreateIntrinsicCall(GET_MTABLE_FUNC_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), intrinsicArgs,
            name: "invoke.fn")
    } else {
        let intrinsicArgs = ArrayList<LLVMValueRef>()
        intrinsicArgs.add(objectTypeInfoRaw)
        intrinsicArgs.add(irBuilder.GetInt64(1))
        intrinsicArgs.add(irBuilder.GetInt64(methodIndex))
        intrinsicArgs.add(ownerTypeInfoRaw)
        irBuilder.CreateIntrinsicCall(GET_VTABLE_FUNC_INTRINSIC_NAME, ArrayList<LLVMTypeRef>(), intrinsicArgs,
            name: "invoke.fn")
    }
    if (isInterfaceCall && ownerTy.StripAllRefs().GetTypeArgs().isEmpty()) {
        return (irBuilder.CreateBitCast(rawCallee,
            unsafe { LLVMPointerType(cgFuncType.GetLLVMFunctionType(), 0u32) }, name: "invoke.fn.cast"),
            unsafe { LLVMConstNull(typeInfoPtrType) })
    }
    let outerTypeInfoArgs = ArrayList<LLVMValueRef>()
    outerTypeInfoArgs.add(objectTypeInfoRaw)
    outerTypeInfoArgs.add(ownerTypeInfoRaw)
    outerTypeInfoArgs.add(irBuilder.GetInt64(methodIndex))
    let rawOuterTypeInfo = irBuilder.CreateIntrinsicCall(GET_METHOD_OUTERTYPE_INTRINSIC_NAME,
        ArrayList<LLVMTypeRef>(), outerTypeInfoArgs, name: "invoke.outer.ti.raw")
    let outerTypeInfo = irBuilder.CreateBitCast(rawOuterTypeInfo, typeInfoPtrType, name: "invoke.outer.ti")
    return (irBuilder.CreateBitCast(rawCallee,
        unsafe { LLVMPointerType(cgFuncType.GetLLVMFunctionType(), 0u32) }, name: "invoke.fn.cast"), outerTypeInfo)
}

private func IsInterfaceOwnerType(ownerTy: Type): Bool {
    if (let Some(customTy) <- (ownerTy.StripAllRefs() as CustomType)) {
        return customTy.GetCustomTypeDef().IsInterface()
    }
    return false
}

private func GenerateResolvedStaticInvoke(irBuilder: IRBuilder2, dispatch: DynamicDispatch,
    args: ArrayList<Value>): LLVMValueRef {
    if (let Some(thisTy) <- dispatch.GetThisType()) {
        if (let Some(callee) <- FindMethodByName(thisTy, dispatch.GetMethodName())) {
            return GenerateApply(irBuilder, callee, args, callType: Some(dispatch.GetMethodType()),
                isMethodType: false, isStaticMethodType: true)
        }
    }
    return LLVMNullValue()
}

private func GenerateResolvedStaticInvoke(irBuilder: IRBuilder2, dispatch: DynamicDispatchWithException,
    args: ArrayList<Value>): LLVMValueRef {
    if (let Some(thisTy) <- dispatch.GetThisType()) {
        if (let Some(callee) <- FindMethodByName(thisTy, dispatch.GetMethodName())) {
            return GenerateApply(irBuilder, callee, args, callType: Some(dispatch.GetMethodType()),
                isMethodType: false, isStaticMethodType: true)
        }
    }
    return LLVMNullValue()
}

private func FindMethodByName(ownerTy: Type, methodName: String): Option<Function> {
    if (let Some(customTy) <- (ownerTy.StripAllRefs() as CustomType)) {
        for (method in customTy.GetCustomTypeDef().GetMethods()) {
            if (MethodNameMatches(method, methodName)) {
                return Some(method)
            }
        }
    }
    return None
}

private func FindMethodIndex(ownerTy: Type, methodName: String): Int64 {
    if (let Some(customTy) <- (ownerTy.StripAllRefs() as CustomType)) {
        var idx: Int64 = 0
        for (method in customTy.GetCustomTypeDef().GetMethods()) {
            if (MethodNameMatches(method, methodName)) {
                return idx
            }
            idx++
        }
    }
    return 0
}

private func MethodNameMatches(method: Function, methodName: String): Bool {
    return method.GetIdentifierWithoutPrefix() == methodName || method.GetSrcCodeIdentifier() == methodName ||
        method.GetRawMangledName() == methodName
}
