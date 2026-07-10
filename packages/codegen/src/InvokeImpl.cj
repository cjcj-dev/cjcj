package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.ClassDef
import cangjie_compiler::chir.ClassType
import cangjie_compiler::chir.Expression
import cangjie_compiler::chir.GetMethodIdxInAutoEnvObject
import cangjie_compiler::chir.GetTypeQualifiedName
import cangjie_compiler::chir.Invoke
import cangjie_compiler::chir.InvokeStatic
import cangjie_compiler::chir.InvokeStaticWithException
import cangjie_compiler::chir.InvokeWithException
import cangjie_compiler::chir.Type
import cangjie_compiler::option.{OptimizationLevel, enumIndex}
import cangjie_compiler::utils.CJC_ASSERT

public func GenerateInvokeExpression(irBuilder: IRBuilder2, chirExpr: Expression): LLVMValueRef {
    if (let Some(invokeExpr) <- (chirExpr as Invoke)) {
        return GenerateInvoke(irBuilder, CHIRInvokeWrapper(invokeExpr))
    }
    if (let Some(invokeWithExceptionExpr) <- (chirExpr as InvokeWithException)) {
        return GenerateInvoke(irBuilder, CHIRInvokeWrapper(invokeWithExceptionExpr))
    }
    if (let Some(invokeStaticExpr) <- (chirExpr as InvokeStatic)) {
        return GenerateInvokeStatic(irBuilder, CHIRInvokeStaticWrapper(invokeStaticExpr))
    }
    if (let Some(invokeStaticWithExceptionExpr) <- (chirExpr as InvokeStaticWithException)) {
        return GenerateInvokeStatic(irBuilder, CHIRInvokeStaticWrapper(invokeStaticWithExceptionExpr))
    }
    return LLVMNullValue()
}

private func GenerateInvoke(irBuilder: IRBuilder2, invoke: CHIRInvokeWrapper): LLVMValueRef {
    irBuilder.SetCHIRExpr(invoke)
    let cgMod = irBuilder.GetCGModule()
    let argValues = ArrayList<CGValue>()
    for (arg in invoke.GetArgs()) {
        argValues.add(cgMod.GetMappedCGValue(arg))
    }
    let objectRawValue = cgMod.GetMappedCGValue(invoke.GetObject()).GetRawValue()
    let objectType = DeRef(invoke.GetObject().GetType().getOrThrow())
    let rawFuncPtr = if (IsAutoEnvType(objectType)) {
        GenerateFuncPtrForAutoEnv(irBuilder, invoke)
    } else {
        let objectTypeInfo = irBuilder.GetTypeInfoFromObject(objectRawValue)
        GenerateFuncPtrForNonAutoEnv(irBuilder, objectTypeInfo, invoke)
    }
    let instTypeArgs = invoke.GetInstantiatedTypeArgs()
    let typeExtra = TypeExtraInfo(0u32, true, false, true, instTypeArgs)
    let concreteFuncType =
        (CGType.GetOrCreate(cgMod, invoke.GetMethodType(), extraInfo: typeExtra) as CGFunctionType).getOrThrow()
    let typedFuncPtr = irBuilder.CreateBitCast(rawFuncPtr,
        unsafe { LLVMPointerType(concreteFuncType.GetLLVMFunctionType(), 0u32) })
    let result = irBuilder.CreateCallOrInvokeWithMethodTypeInfo(concreteFuncType, typedFuncPtr, argValues,
        None, instTypeArgs)
    GenIRToUnboxResult(irBuilder, objectRawValue,
        invoke.TestVritualMethodAttr(irBuilder.GetCGContext().GetCHIRBuilder(), Attribute.MUT))
    return result
}

private func GenerateFuncPtrForNonAutoEnv(irBuilder: IRBuilder2, thisTI: LLVMValueRef,
    invokeExpr: CHIRInvokeExpr): LLVMValueRef {
    let cgCtx = irBuilder.GetCGContext()
    if (VirtualCallCanBeHoisted(irBuilder, invokeExpr)) {
        let prepForVirtualCallBB = irBuilder.CreateAndInsertBasicBlocks(
            ArrayList<String>([GenNameForBB("prepForVirtualCall.bb")]))[0]
        invokeExpr.SetPrepForVirtualCallBB(prepForVirtualCallBB)
        irBuilder.CreateBr(prepForVirtualCallBB)
        irBuilder.SetInsertPoint(prepForVirtualCallBB)
    }
    let introType = (invokeExpr.GetOuterType(cgCtx.GetCHIRBuilder()) as ClassType).getOrThrow()
    let introTi = irBuilder.CreateTypeInfo(introType)
    let vtableOffset = invokeExpr.GetVirtualMethodOffset()
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
    let prepForVirtualCallBB = invokeExpr.GetPrepForVirtualCallBB()
    if (!prepForVirtualCallBB.isNull()) {
        cgCtx.AddVirtualCallInfo4LICM(irBuilder.GetInsertCGFunction().getOrThrow(),
            VirtualCallInfo4LICM(prepForVirtualCallBB, funcPtr, invokeExpr.GetThisType(false).getOrThrow(), introType,
                vtableOffset))
        let prepForVirtualCallEndBB = irBuilder.CreateAndInsertBasicBlocks(
            ArrayList<String>([GenNameForBB("prepForVirtualCall.end")]))[0]
        irBuilder.CreateBr(prepForVirtualCallEndBB)
        irBuilder.SetInsertPoint(prepForVirtualCallEndBB)
    }
    return funcPtr
}

private func VirtualCallCanBeHoisted(irBuilder: IRBuilder2, callExprWrapper: CHIRCallExpr): Bool {
    let options = irBuilder.GetCGContext().GetCompileOptions()
    if (enumIndex(options.optimizationLevel) < enumIndex(OptimizationLevel.O2)) {
        return false
    }
    return callExprWrapper.GetThisType(false).getOrThrow().IsGeneric()
}

private func GenerateFuncPtrForAutoEnv(irBuilder: IRBuilder2, invoke: CHIRInvokeWrapper): LLVMValueRef {
    let i8PtrTy = unsafe { LLVMPointerType(LLVMInt8TypeInContext(irBuilder.GetLLVMContext().raw), 0u32) }
    let methodIdx = GetMethodIdxInAutoEnvObject(invoke.GetMethodName())
    let objectRawValue = irBuilder.GetCGModule().GetMappedCGValue(invoke.GetObject()).GetRawValue()
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

private func GenerateInvokeStatic(irBuilder: IRBuilder2, invokeStatic: CHIRInvokeStaticWrapper): LLVMValueRef {
    irBuilder.SetCHIRExpr(invokeStatic)
    let cgMod = irBuilder.GetCGModule()
    let argValues = ArrayList<CGValue>()
    for (arg in invokeStatic.GetArgs()) {
        argValues.add(cgMod.GetMappedCGValue(arg))
    }
    let thisTI = cgMod.GetMappedCGValue(invokeStatic.GetRTTIValue()).GetRawValue()
    let rawFuncPtr = GenerateFuncPtrForNonAutoEnv(irBuilder, thisTI, invokeStatic)
    let instTypeArgs = invokeStatic.GetInstantiatedTypeArgs()
    let typeExtra = TypeExtraInfo(0u32, true, true, false, instTypeArgs)
    let concreteFuncType =
        (CGType.GetOrCreate(cgMod, invokeStatic.GetMethodType(), extraInfo: typeExtra) as CGFunctionType).getOrThrow()
    let typedFuncPtr = irBuilder.CreateBitCast(rawFuncPtr,
        unsafe { LLVMPointerType(concreteFuncType.GetLLVMFunctionType(), 0u32) })
    return irBuilder.CreateCallOrInvokeWithMethodTypeInfo(concreteFuncType, typedFuncPtr, argValues, None,
        instTypeArgs, thisTypeInfoArg: Some(thisTI))
}
