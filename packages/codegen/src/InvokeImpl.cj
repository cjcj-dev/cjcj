package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.ClassDef
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.CustomType
import cangjie_compiler::chir.CustomTypeDef
import cangjie_compiler::chir.DynamicDispatch
import cangjie_compiler::chir.DynamicDispatchWithException
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.FuncType
import cangjie_compiler::chir.GetMethodIdxInAutoEnvObject
import cangjie_compiler::chir.GetTypeQualifiedName
import cangjie_compiler::chir.Invoke
import cangjie_compiler::chir.InvokeStatic
import cangjie_compiler::chir.InvokeStaticWithException
import cangjie_compiler::chir.InvokeWithException
import cangjie_compiler::chir.Type
import cangjie_compiler::chir.Value
import cangjie_compiler::option.{OptimizationLevel, enumIndex}
import cangjie_compiler::utils.CJC_ASSERT

public func GenerateInvokeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(invokeExpr) <- (chirExpr as Invoke)) {
        return GenerateInvoke(irBuilder, invokeExpr)
    }
    if (let Some(invokeWithExceptionExpr) <- (chirExpr as InvokeWithException)) {
        return GenerateInvoke(irBuilder, invokeWithExceptionExpr)
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

private func GenerateInvoke(irBuilder: IRBuilder2, invokeExpr: Invoke): LLVMValueRef {
    irBuilder.SetCHIRExpr(CHIRExprWrapper(invokeExpr))
    let chirBuilder = irBuilder.GetCGContext().GetCHIRBuilder()
    return GenerateInvoke(irBuilder, invokeExpr.GetObject(), invokeExpr.GetArgs(), invokeExpr.GetMethodName(),
        invokeExpr.GetMethodType(), invokeExpr.GetInstantiatedTypeArgs(), invokeExpr.GetThisType(),
        invokeExpr.GetInstSrcParentCustomTypeOfMethod(chirBuilder), invokeExpr.GetVirtualMethodOffset(chirBuilder),
        invokeExpr.GetVirtualMethodAttr(chirBuilder).Test(Attribute.MUT))
}

private func GenerateInvoke(irBuilder: IRBuilder2, invokeExpr: InvokeWithException): LLVMValueRef {
    irBuilder.SetCHIRExpr(CHIRExprWrapper(invokeExpr))
    let chirBuilder = irBuilder.GetCGContext().GetCHIRBuilder()
    return GenerateInvoke(irBuilder, invokeExpr.GetObject(), invokeExpr.GetArgs(), invokeExpr.GetMethodName(),
        invokeExpr.GetMethodType(), invokeExpr.GetInstantiatedTypeArgs(), invokeExpr.GetThisType(),
        invokeExpr.GetInstSrcParentCustomTypeOfMethod(chirBuilder), invokeExpr.GetVirtualMethodOffset(chirBuilder),
        invokeExpr.GetVirtualMethodAttr(chirBuilder).Test(Attribute.MUT))
}

private func GenerateInvoke(irBuilder: IRBuilder2, objectValue: Value, args: ArrayList<Value>, methodName: String,
    methodType: FuncType, instTypeArgs: ArrayList<Type>, thisType: Option<Type>, introType: ClassType,
    vtableOffset: UInt64, isMutMethod: Bool): LLVMValueRef {
    let cgMod = irBuilder.GetCGModule()
    let argValues = ArrayList<CGValue>()
    for (arg in args) {
        argValues.add(cgMod.GetMappedCGValue(arg))
    }
    let objectRawValue = cgMod.GetMappedCGValue(objectValue).GetRawValue()
    let objectType = objectValue.GetType().getOrThrow().StripAllRefs()
    let objectTypeInfo = irBuilder.GetTypeInfoFromObject(objectRawValue)
    let isAutoEnv = IsAutoEnvType(objectType)
    let methodTypeInfoArg = if (isAutoEnv) {
        objectTypeInfo
    } else {
        CreateOuterTypeInfo(irBuilder, objectValue, objectTypeInfo, introType, vtableOffset)
    }
    let rawFuncPtr = if (isAutoEnv) {
        GenerateFuncPtrForAutoEnv(irBuilder, objectRawValue, methodName)
    } else {
        GenerateFuncPtrForNonAutoEnv(irBuilder, objectTypeInfo, thisType, introType, vtableOffset)
    }
    let typeExtra = TypeExtraInfo(0u32, true, false, true, instTypeArgs)
    let concreteFuncType = (CGType.GetOrCreate(cgMod, methodType, extraInfo: typeExtra) as CGFunctionType).getOrThrow()
    let typedFuncPtr = irBuilder.CreateBitCast(rawFuncPtr,
        unsafe { LLVMPointerType(concreteFuncType.GetLLVMFunctionType(), 0u32) })
    let result = irBuilder.CreateCallOrInvokeWithMethodTypeInfo(concreteFuncType, typedFuncPtr, argValues,
        Some(methodTypeInfoArg), instTypeArgs)
    GenIRToUnboxResult(irBuilder, objectRawValue, isMutMethod)
    return result
}

private func GenerateFuncPtrForNonAutoEnv(irBuilder: IRBuilder2, thisTI: LLVMValueRef, thisType: Option<Type>,
    introType: ClassType, vtableOffset: UInt64): LLVMValueRef {
    if (VirtualCallCanBeHoisted(irBuilder, thisType)) {
        throw IllegalStateException("GAP_TODO CGContext::AddVirtualCallInfo4LICM InvokeImpl.cpp:49-90")
    }
    let introTi = irBuilder.CreateTypeInfo(introType)
    let idxOfVFunc = irBuilder.GetInt64(Int64(vtableOffset))
    let funcPtr = if (introType.GetClassDef().IsInterface()) {
        let mtableArgs = ArrayList<LLVMValueRef>()
        mtableArgs.add(thisTI)
        mtableArgs.add(introTi)
        mtableArgs.add(idxOfVFunc)
        irBuilder.CallIntrinsicMTable(mtableArgs)
    } else {
        let vtableSizeOfIntroType = VTableSizeOf(introType)
        CJC_ASSERT(vtableSizeOfIntroType > 0)
        let rawPtr = irBuilder.CallIntrinsicGetVTableFunc(thisTI, irBuilder.GetInt64(vtableSizeOfIntroType - 1),
            idxOfVFunc, introTi)
        LLVMSetInstructionMetadata(irBuilder.GetLLVMContext(), rawPtr, "IntroType",
            LLVMCreateMDTupleFromString(irBuilder.GetLLVMContext(), GetTypeQualifiedName(introType)))
        rawPtr
    }
    if (introType.GetTypeArgs().size <= 1) {
        LLVMSetInstructionMetadata(irBuilder.GetLLVMContext(), funcPtr, "objType",
            GenObjTyMetaForVirtualCall(irBuilder, introType))
    }
    return funcPtr
}

private func VirtualCallCanBeHoisted(irBuilder: IRBuilder2, thisType: Option<Type>): Bool {
    let options = irBuilder.GetCGContext().GetCompileOptions()
    if (enumIndex(options.optimizationLevel) < enumIndex(OptimizationLevel.O2)) {
        return false
    }
    if (let Some(thisTy) <- thisType) {
        return thisTy.IsGeneric()
    }
    return false
}

private func GenerateFuncPtrForAutoEnv(irBuilder: IRBuilder2, objectRawValue: LLVMValueRef,
    methodName: String): LLVMValueRef {
    let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
    let methodIdx = GetMethodIdxInAutoEnvObject(methodName)
    let payload = irBuilder.GetPayloadFromObject(objectRawValue)
    let typedPayload = irBuilder.CreateBitCast(payload, unsafe { LLVMPointerType(i8PtrTy, 1u32) },
        name: "virtualFPtr")
    let indices = ArrayList<LLVMValueRef>()
    indices.add(unsafe { LLVMConstInt(LLVMInt32TypeInContext(irBuilder.GetLLVMContext().raw), methodIdx, 0) })
    let virtualPtr = irBuilder.CreateGEP(i8PtrTy, typedPayload, indices, name: "virtualFPtr")
    let loadInst = irBuilder.CreateLoad(i8PtrTy, virtualPtr)
    LLVMSetInstructionMetadata(irBuilder.GetLLVMContext(), loadInst, "invariant.load",
        LLVMCreateMDTuple(irBuilder.GetLLVMContext(), ArrayList<LLVMMetadataRef>()))
    return loadInst
}

private func CreateOuterTypeInfo(irBuilder: IRBuilder2, objectValue: Value, thisTypeInfo: LLVMValueRef,
    outerCHIRType: ClassType, vtableOffset: UInt64): LLVMValueRef {
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(irBuilder.GetLLVMContext())
    if (IsAutoEnvType(objectValue.GetType().getOrThrow().StripAllRefs())) {
        return irBuilder.GetTypeInfoFromObject(irBuilder.GetCGModule().GetMappedCGValue(objectValue).GetRawValue())
    }
    if (irBuilder.GetCGContext().GetCGPkgContext().NeedOuterTypeInfo(outerCHIRType)) {
        let methodOuterTypeArgs = ArrayList<LLVMValueRef>()
        methodOuterTypeArgs.add(thisTypeInfo)
        methodOuterTypeArgs.add(irBuilder.CreateTypeInfo(outerCHIRType))
        methodOuterTypeArgs.add(irBuilder.GetInt64(Int64(vtableOffset)))
        let outerType = irBuilder.CallIntrinsicMethodOuterType(methodOuterTypeArgs)
        return irBuilder.CreateBitCast(outerType, typeInfoPtrType)
    }
    return unsafe { LLVMConstNull(typeInfoPtrType) }
}

private func GenObjTyMetaForVirtualCall(irBuilder: IRBuilder2, ty: Type): LLVMMetadataRef {
    CJC_ASSERT(ty.GetTypeArgs().size <= 1)
    if (ty.GetTypeArgs().size == 1) {
        return LLVMCreateMDTuple(irBuilder.GetLLVMContext(), UnwindGenericRelateType(irBuilder.GetLLVMContext(), ty))
    }
    return LLVMCreateMDTupleFromString(irBuilder.GetLLVMContext(), CGType.GetNameOfTypeInfoGV(ty))
}

private func GenIRToUnboxResult(_: IRBuilder2, _: LLVMValueRef, _: Bool): Unit {
    // GAP_TODO CGContext::GetOriginalNonRefValOfBoxedValue/SetBoxedValueMap InvokeImpl.cpp:107-129.
}

private func VTableSizeOf(ownerTy: Type): Int64 {
    if (let Some(classTy) <- (ownerTy.StripAllRefs() as ClassType)) {
        let classDef = classTy.GetClassDef()
        if (classDef.IsInterface()) {
            return 0
        }
        var count: Int64 = 0
        var current: Option<ClassDef> = classDef
        while (let Some(def) <- current) {
            count++
            current = def.GetSuperClassDef()
        }
        return count
    }
    return 1
}

private func GenerateResolvedStaticInvoke(irBuilder: IRBuilder2, dispatch: DynamicDispatch,
    args: ArrayList<Value>): LLVMValueRef {
    if (let Some(thisTy) <- dispatch.GetThisType()) {
        if (let Some(callee) <- FindMethodByName(thisTy, dispatch.GetMethodName())) {
            return GenerateApply(irBuilder, callee, args, callType: Some(dispatch.GetMethodType()),
                isMethodType: true, isStaticMethodType: true, instTypeArgs: dispatch.GetInstantiatedTypeArgs())
        }
    }
    return LLVMNullValue()
}

private func GenerateResolvedStaticInvoke(irBuilder: IRBuilder2, dispatch: DynamicDispatchWithException,
    args: ArrayList<Value>): LLVMValueRef {
    if (let Some(thisTy) <- dispatch.GetThisType()) {
        if (let Some(callee) <- FindMethodByName(thisTy, dispatch.GetMethodName())) {
            return GenerateApply(irBuilder, callee, args, callType: Some(dispatch.GetMethodType()),
                isMethodType: true, isStaticMethodType: true, instTypeArgs: dispatch.GetInstantiatedTypeArgs())
        }
    }
    return LLVMNullValue()
}

private func FindMethodByName(ownerTy: Type, methodName: String): Option<Function> {
    if (let Some(customTy) <- (ownerTy.StripAllRefs() as CustomType)) {
        return FindMethodByName(customTy.GetCustomTypeDef(), methodName)
    }
    return None
}

private func FindMethodByName(def: CustomTypeDef, methodName: String): Option<Function> {
    for (method in def.GetMethods()) {
        if (MethodNameMatches(method, methodName)) {
            return Some(method)
        }
    }
    if (let Some(classDef) <- (def as ClassDef)) {
        if (let Some(superDef) <- classDef.GetSuperClassDef()) {
            return FindMethodByName(superDef, methodName)
        }
    }
    return None
}

private func MethodNameMatches(method: Function, methodName: String): Bool {
    return method.GetIdentifierWithoutPrefix() == methodName || method.GetSrcCodeIdentifier() == methodName ||
        method.GetRawMangledName() == methodName
}
