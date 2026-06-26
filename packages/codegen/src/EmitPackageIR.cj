package cangjie_compiler::codegen

import std.collection.*
import std.sort.*
import cangjie_compiler::chir.Attribute
import cangjie_compiler::chir.ExprKind
import cangjie_compiler::chir.FuncKind
import cangjie_compiler::chir.Function
import cangjie_compiler::chir.Type
import cangjie_compiler::mangle.MANGLE_FUNC_PARAM_TYPE_PREFIX
import cangjie_compiler::mangle.MANGLE_VOID_TY_SUFFIX
import cangjie_compiler::mangle.SPECIAL_NAME_FOR_IMPORTS_INIT_FUNCTION
import cangjie_compiler::mangle.SPECIAL_NAME_FOR_INIT_FLAG_RESET_FUNCTION
import cangjie_compiler::mangle.SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION
import cangjie_compiler::mangle.SPECIAL_NAME_FOR_INIT_RESET_FUNCTION
import cangjie_compiler::option.GlobalOptions

private let CANGJIE_SDK_VERSION: String = "1.1.0-alpha.20260331010029"
private let PKG_INIT_FUNC_METADATA: String = "pkg_init_func"
private let HAS_INVOKED_PKG_INIT_LITERAL: String = "has_invoked_pkg_init_literal"

private type LLVMIsACallInstFunc = CFunc<(LLVMValueRef) -> LLVMValueRef>
private type LLVMGetCalledValueFunc = CFunc<(LLVMValueRef) -> LLVMValueRef>
private type LLVMSetValueName2Func = CFunc<(LLVMValueRef, CString, UIntNative) -> Unit>

public func GenPackageModules(chirData: CHIRData, options: GlobalOptions, enableIncrement: Bool,
    cachedMangleMap!: CachedMangleMap = CachedMangleMap()): ArrayList<LLVMModuleHandle> {
    let cgPkgContext = CGPkgContext(chirData, options, enableIncrement, cachedMangleMap)
    let splitter = CHIRSplitter(cgPkgContext)
    for (subPackage in splitter.SplitCHIRPackage()) {
        let cgMod = CGModule(subPackage, cgPkgContext)
        cgPkgContext.AddCGModule(cgMod)
        EmitTypeTemplatesForOwnedGenericCustomDefs(cgMod)
        for (globalVar in subPackage.chirGVs) {
            EmitGlobalVariableIR(cgMod, globalVar)
        }
        for (chirFunc in subPackage.chirFuncs) {
            EmitFunctionIR(cgMod, chirFunc)
        }
        for (chirFunc in subPackage.chirForeigns) {
            EmitImportedCFuncIR(cgMod, chirFunc)
        }
        for (chirFunc in subPackage.chirImportedCFuncs) {
            EmitImportedCFuncIR(cgMod, chirFunc)
        }
        if (subPackage.mainModule && options.CompileExecutable()) {
            EmitCJSDKVersion(cgMod)
            EmitMainFunctionIR(cgMod)
            CreatePackageInitResetFunction(cgMod)
            SpecifyPackageInitFunc(cgMod)
        }
        InitializeCjStringLiteral(cgMod)
        GenerateInterfaceExtensionDefs(cgMod)
        RedefineTypeInfosForCustomDefs(cgMod)
        let keepTypesFunc = KeepSomeTypesManually(cgMod)
        EmitStaticGenericTIsAndLLVMUsed(cgMod, keepTypesFunc)
        cgMod.EraseUselessInstsAndDeclarations()
        cgMod.Opt()
    }
    return cgPkgContext.ReleaseLLVMModules()
}

private func EmitTypeTemplatesForOwnedGenericCustomDefs(cgMod: CGModule): Unit {
    for (def in cgMod.GetCGContext().GetSubCHIRPackage().chirCustomDefs) {
        if (def.IsExtend() || !def.IsGenericDef()) {
            continue
        }
        if (let Some(customTy) <- def.GetType()) {
            EnsureSourceGenericTypeTemplate(cgMod, customTy)
        }
    }
}

private func EmitCJSDKVersion(cgMod: CGModule): Unit {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        try (globalName = unsafe { LibC.mallocCString("cj.sdk.version") }.asResource(),
            versionCString = unsafe { LibC.mallocCString(CANGJIE_SDK_VERSION) }.asResource()) {
            let initializer = unsafe {
                LLVMConstStringInContext(cgMod.GetLLVMContext().raw, versionCString.value,
                    UInt32(CANGJIE_SDK_VERSION.size), 0)
            }
            let globalType = unsafe { LLVMTypeOf(initializer) }
            var versionGlobal = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, globalName.value) }
            if (versionGlobal.isNull()) {
                versionGlobal = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, globalName.value) }
            }
            unsafe {
                LLVMSetInitializer(versionGlobal, initializer)
                LLVMSetLinkage(versionGlobal, LLVMLinkageValue(LLVMLinkage.Private))
                LLVMSetGlobalConstant(versionGlobal, 1)
            }
            cgMod.GetCGContext().AddLLVMUsedVars("cj.sdk.version")
        }
    }
}

private func EmitMainFunctionIR(cgMod: CGModule): Unit {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        var mainFunc = LLVMNullValue()
        try (mainName = unsafe { LibC.mallocCString("main") }.asResource()) {
            mainFunc = unsafe { LLVMGetNamedFunction(moduleHandle.raw, mainName.value) }
            if (!mainFunc.isNull()) {
                return
            }
            let llvmContext = cgMod.GetLLVMContext().raw
            let voidType = unsafe { LLVMVoidTypeInContext(llvmContext) }
            let i32Type = unsafe { LLVMInt32TypeInContext(llvmContext) }
            let i8Type = unsafe { LLVMInt8TypeInContext(llvmContext) }
            let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
            let i8PtrPtrType = unsafe { LLVMPointerType(i8PtrType, 0u32) }
            try (paramTypes = LibC.malloc<LLVMTypeRef>(count: 2).asResource()) {
                unsafe {
                    (paramTypes.value + 0).write(i32Type)
                    (paramTypes.value + 1).write(i8PtrPtrType)
                }
                let mainType = unsafe { LLVMFunctionType(voidType, paramTypes.value, 2u32, 0) }
                mainFunc = unsafe { LLVMAddFunction(moduleHandle.raw, mainName.value, mainType) }
            }
            try (blockName = unsafe { LibC.mallocCString("entry") }.asResource()) {
                let builder = unsafe { LLVMCreateBuilderInContext(llvmContext) }
                let entryBlock = unsafe { LLVMAppendBasicBlockInContext(llvmContext, mainFunc, blockName.value) }
                unsafe {
                    LLVMPositionBuilderAtEnd(builder, entryBlock)
                }
                if (let Some(mainEntry) <- FindMainEntryFunction(cgMod)) {
                    CreateUserMainWrapper(cgMod, moduleHandle, llvmContext, mainEntry)
                }
                let cjEntryFunc = CreateCJEntryFunction(cgMod, moduleHandle, llvmContext, i32Type)
                let voidFnType = unsafe { LLVMFunctionType(voidType, CPointer<LLVMTypeRef>(), 0u32, 0) }
                let i32FnType = unsafe { LLVMFunctionType(i32Type, CPointer<LLVMTypeRef>(), 0u32, 0) }
                let runtimeInit = GetOrInsertLLVMFunction(moduleHandle, PREFIX_OF_RUNTIME_SYMS + "CjRuntimeInit",
                    voidFnType)
                BuildVoidCall(builder, voidFnType, runtimeInit, ArrayList<LLVMValueRef>())

                let setArgsParamTypes = ArrayList<LLVMTypeRef>()
                setArgsParamTypes.add(i32Type)
                setArgsParamTypes.add(i8PtrPtrType)
                let setArgsType = BuildLLVMFunctionType(voidType, setArgsParamTypes)
                let setArgsFunc = GetOrInsertLLVMFunction(moduleHandle, PREFIX_OF_RUNTIME_SYMS + "SetCommandLineArgs",
                    setArgsType)
                let setArgsValues = ArrayList<LLVMValueRef>()
                setArgsValues.add(unsafe { LLVMGetParam(mainFunc, 0u32) })
                setArgsValues.add(unsafe { LLVMGetParam(mainFunc, 1u32) })
                BuildVoidCall(builder, setArgsType, setArgsFunc, setArgsValues)

                let startParamTypes = ArrayList<LLVMTypeRef>()
                startParamTypes.add(unsafe { LLVMPointerType(i32FnType, 0u32) })
                let runtimeStartType = BuildLLVMFunctionType(voidType, startParamTypes)
                let runtimeStart = GetOrInsertLLVMFunction(moduleHandle, PREFIX_OF_RUNTIME_SYMS + "CjRuntimeStart",
                    runtimeStartType)
                let startArgs = ArrayList<LLVMValueRef>()
                startArgs.add(cjEntryFunc)
                BuildVoidCall(builder, runtimeStartType, runtimeStart, startArgs)

                unsafe {
                    LLVMBuildRetVoid(builder)
                    LLVMDisposeBuilder(builder)
                }
            }
        }
    }
}

private func CreateUserMainWrapper(cgMod: CGModule, moduleHandle: LLVMModuleHandle, llvmContext: LLVMContextRef,
    mainEntry: Function): Unit {
    try (wrapperName = unsafe { LibC.mallocCString(USER_MAIN_MANGLED_NAME) }.asResource()) {
        if (!unsafe { LLVMGetNamedFunction(moduleHandle.raw, wrapperName.value) }.isNull()) {
            return
        }
        let i64Type = unsafe { LLVMInt64TypeInContext(llvmContext) }
        let wrapperType = unsafe { LLVMFunctionType(i64Type, CPointer<LLVMTypeRef>(), 0u32, 0) }
        let wrapperFunc = unsafe { LLVMAddFunction(moduleHandle.raw, wrapperName.value, wrapperType) }
        SetCangjieGC(wrapperFunc)
        AddFnAttr(wrapperFunc, "noinline")
        cgMod.SetExceptionIntrinsicPersonality(wrapperFunc)
        try (blockName = unsafe { LibC.mallocCString("entry") }.asResource()) {
            let entryBlock = unsafe { LLVMAppendBasicBlockInContext(llvmContext, wrapperFunc, blockName.value) }
            try (irBuilder = IRBuilder2(cgMod, entryBlock)) {
                let retSlot = irBuilder.CreateEntryAlloca(i64Type)
                let cgMain = cgMod.GetOrInsertCGFunction(mainEntry)
                let mainRet = irBuilder.CreateCallOrInvoke(cgMain)
                let retValue = if (mainRet.isNull()) {
                    irBuilder.GetInt64(0)
                } else if (let Some(retTy) <- mainEntry.GetReturnType()) {
                    if (retTy.IsUnit() || retTy.IsVoid() || retTy.IsNothing()) {
                        irBuilder.GetInt64(0)
                    } else {
                        mainRet
                    }
                } else {
                    irBuilder.GetInt64(0)
                }
                irBuilder.CreateStore(retValue, retSlot)
                let loaded = irBuilder.CreateLoad(i64Type, retSlot)
                let _ = irBuilder.CreateRet(loaded)
            }
        }
    }
}

private func CreateCJEntryFunction(cgMod: CGModule, moduleHandle: LLVMModuleHandle, llvmContext: LLVMContextRef,
    i32Type: LLVMTypeRef): LLVMValueRef {
    let entryType = unsafe { LLVMFunctionType(i32Type, CPointer<LLVMTypeRef>(), 0u32, 0) }
    let entryFunc = GetOrInsertLLVMFunction(moduleHandle, CJ_ENTRY_FUNC_NAME, entryType)
    SetCangjieGC(entryFunc)
    cgMod.SetExceptionIntrinsicPersonality(entryFunc)
    let zero = unsafe { LLVMConstInt(i32Type, 0u64, 0) }
    try (blockName = unsafe { LibC.mallocCString("entry") }.asResource()) {
        let entryBlock = unsafe { LLVMAppendBasicBlockInContext(llvmContext, entryFunc, blockName.value) }
        try (irBuilder = IRBuilder2(cgMod, entryBlock)) {
            let voidType = unsafe { LLVMVoidTypeInContext(llvmContext) }
            let voidFnType = unsafe { LLVMFunctionType(voidType, CPointer<LLVMTypeRef>(), 0u32, 0) }
            let checkThreadLocal = GetOrInsertLLVMFunction(moduleHandle,
                PREFIX_OF_BACKEND_SYMS + "CheckThreadLocalDataOffset", voidFnType)
            let _ = irBuilder.CreateCallOrInvoke(checkThreadLocal, voidFnType, ArrayList<LLVMValueRef>())

            let unwindBlock = irBuilder.CreateAndInsertBasicBlock("unwindDest")
            try (unwindScope = CodeGenUnwindBlockScope(cgMod, unwindBlock)) {
                CreateCJEntryTryScope(cgMod, irBuilder, zero, i32Type)
            }
            irBuilder.SetInsertPoint(unwindBlock)
            CreateUnwindBlockForTryCatchWrapper(cgMod, irBuilder, i32Type)
        }
    }
    return entryFunc
}

private func CreateCJEntryTryScope(cgMod: CGModule, irBuilder: IRBuilder2, zero: LLVMValueRef,
    i32Type: LLVMTypeRef): Unit {
    if (let Some(initFn) <- cgMod.GetCGContext().GetCHIRPackage().GetPackageInitFunc()) {
        let cgInit = cgMod.GetOrInsertCGFunction(initFn)
        let _ = irBuilder.CreateCallOrInvoke(cgInit)
    }
    if (let Some(_) <- FindMainEntryFunction(cgMod)) {
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            let i64Type = unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
            let wrapperType = unsafe { LLVMFunctionType(i64Type, CPointer<LLVMTypeRef>(), 0u32, 0) }
            let userMain = GetOrInsertLLVMFunction(moduleHandle, USER_MAIN_MANGLED_NAME, wrapperType)
            let callResult = irBuilder.CreateCallOrInvoke(userMain, wrapperType, ArrayList<LLVMValueRef>())
            irBuilder.CreateExecAtExitCallbacksCall()
            let _ = irBuilder.CreateRet(GenerateMainRetVal(irBuilder, callResult, i32Type))
            return
        }
    }
    irBuilder.CreateExecAtExitCallbacksCall()
    let _ = irBuilder.CreateRet(zero)
}

private func CreateUnwindBlockForTryCatchWrapper(cgMod: CGModule, irBuilder: IRBuilder2, i32Type: LLVMTypeRef): Unit {
    let landingPad = irBuilder.CreateLandingPad(0u32)
    irBuilder.AddLandingPadCatchAllClause(landingPad)
    let exceptionWrapper = irBuilder.CallExceptionIntrinsicGetExceptionValue()
    let exceptionValue = irBuilder.CallPostThrowExceptionIntrinsic(exceptionWrapper)
    let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>([
        "is.OOM", "judge.Error", "is.Error", "judge.Exception", "is.Exception", "judge.end", "rethrow"
    ]))
    if (blocks.size < 7) {
        let _ = irBuilder.CreateRet(unsafe { LLVMConstInt(i32Type, 1u64, 0) })
        return
    }
    let isOOMBb = blocks[0]
    let judgeErrorBb = blocks[1]
    let isErrorBb = blocks[2]
    let judgeExceptionBb = blocks[3]
    let isExceptionBb = blocks[4]
    let judgeEndBb = blocks[5]
    let rethrowBb = blocks[6]

    try (unwindScope = CodeGenUnwindBlockScope(cgMod, rethrowBb)) {
        let isOOM = irBuilder.CallClassIntrinsicInstanceOf(exceptionValue,
            GetTypeFromImplicitUsedFuncParam(cgMod, "_CNat16OutOfMemoryError6<init>Hv", 0))
        irBuilder.CreateCondBr(isOOM, isOOMBb, judgeErrorBb)

        irBuilder.SetInsertPoint(isOOMBb)
        irBuilder.CreateEPrintlnCall("An exception has occurred:")
        irBuilder.CreateEPrintlnCall("    Out of memory")
        irBuilder.CreateBr(judgeEndBb)

        irBuilder.SetInsertPoint(judgeErrorBb)
        let isError = irBuilder.CallClassIntrinsicInstanceOf(exceptionValue,
            GetTypeFromImplicitUsedFuncParam(cgMod, "_CNat5Error15printStackTraceHv", 0))
        irBuilder.CreateCondBr(isError, isErrorBb, judgeExceptionBb)

        irBuilder.SetInsertPoint(isErrorBb)
        CreatePrintStackTraceCall(cgMod, irBuilder, exceptionValue)
        irBuilder.CreateBr(judgeEndBb)

        irBuilder.SetInsertPoint(judgeExceptionBb)
        let isException = irBuilder.CallClassIntrinsicInstanceOf(exceptionValue,
            GetTypeFromImplicitUsedFuncParam(cgMod, "_CNat9Exception15printStackTraceHv", 0))
        irBuilder.CreateCondBr(isException, isExceptionBb, judgeEndBb)

        irBuilder.SetInsertPoint(isExceptionBb)
        irBuilder.CreateHandleExceptionCall(exceptionValue)
        irBuilder.CreateBr(judgeEndBb)
    }

    irBuilder.SetInsertPoint(judgeEndBb)
    irBuilder.CreateExecAtExitCallbacksCall()
    let _ = irBuilder.CreateRet(unsafe { LLVMConstInt(i32Type, 1u64, 0) })

    irBuilder.SetInsertPoint(rethrowBb)
    let landingPad1 = irBuilder.CreateLandingPad(0u32)
    irBuilder.AddLandingPadCatchAllClause(landingPad1)
    irBuilder.CreateExecAtExitCallbacksCall()
    let _ = irBuilder.CreateRet(unsafe { LLVMConstInt(i32Type, 1u64, 0) })
}

private func CreatePrintStackTraceCall(cgMod: CGModule, irBuilder: IRBuilder2, exceptionValue: LLVMValueRef): Unit {
    let printStackTraceName = "_CNat5Error15printStackTraceHv"
    if (let Some(printStackTraceFunc) <- cgMod.GetCGContext().GetImplicitUsedFunc(printStackTraceName)) {
        if (let Some(printStackTraceType) <- printStackTraceFunc.GetFuncType()) {
            let exceptionTypeInfo = irBuilder.GetTypeInfoFromObject(exceptionValue)
            let parentDef = printStackTraceFunc.GetParentCustomTypeDef() ?? return
            let ownerTy = parentDef.GetType() ?? return
            let funcPtrRaw = irBuilder.CallIntrinsicGetVTableFunc(exceptionTypeInfo, irBuilder.GetInt64(1),
                irBuilder.GetInt64(2), irBuilder.CreateTypeInfo(ownerTy))
            let cgFuncType = (CGType.GetOrCreate(cgMod, printStackTraceType) as CGFunctionType) ?? return
            let callee = irBuilder.CreateBitCast(funcPtrRaw,
                unsafe { LLVMPointerType(cgFuncType.GetLLVMFunctionType(), 0u32) })
            let paramRefTy = cgMod.GetCGContext().GetCHIRBuilder().context.GetRefTy(printStackTraceType.GetParamType(0))
            let args = ArrayList<CGValue>()
            args.add(CGValue(exceptionValue, CGType.GetOrCreate(cgMod, paramRefTy)))
            let _ = irBuilder.CreateCallOrInvoke(cgFuncType, callee, args)
        }
    }
}

private func GetTypeFromImplicitUsedFuncParam(cgMod: CGModule, funcName: String, paramIndex: Int64): Type {
    let helperFunc = cgMod.GetCGContext().GetImplicitUsedFunc(funcName) ?? throw IllegalStateException(
        "missing implicit used function: " + funcName)
    let funcType = helperFunc.GetFuncType() ?? throw IllegalStateException("missing function type: " + funcName)
    return funcType.GetParamType(paramIndex).StripAllRefs()
}

private func GenerateMainRetVal(irBuilder: IRBuilder2, userMainRetVal: LLVMValueRef, i32Type: LLVMTypeRef): LLVMValueRef {
    if (userMainRetVal.isNull()) {
        return unsafe { LLVMConstInt(i32Type, 0u64, 0) }
    }
    let retType = unsafe { LLVMTypeOf(userMainRetVal) }
    if (retType.isNull() || unsafe { LLVMGetTypeKind(retType) } == 0) {
        return unsafe { LLVMConstInt(i32Type, 0u64, 0) }
    }
    let i64Type = unsafe { LLVMInt64TypeInContext(irBuilder.GetLLVMContext().raw) }
    let minValue = irBuilder.GetInt64(-2147483648)
    let maxValue = irBuilder.GetInt64(2147483647)
    let saturated = SaturatingIntegerValue(irBuilder, userMainRetVal, minValue, maxValue, i64Type)
    return irBuilder.CreateTrunc(saturated, i32Type)
}

private func SaturatingIntegerValue(irBuilder: IRBuilder2, sourceValue: LLVMValueRef, minValue: LLVMValueRef,
    maxValue: LLVMValueRef, valueType: LLVMTypeRef): LLVMValueRef {
    let blocks = irBuilder.CreateAndInsertBasicBlocks(ArrayList<String>(["min.bb", "max.bb", "check.over"]))
    if (blocks.size < 3) {
        return sourceValue
    }
    let previousBB = irBuilder.GetInsertBlock()
    let downOverflow = irBuilder.CreateICmp(LLVMIntPredicate.SLT, sourceValue, minValue)
    let upOverflow = irBuilder.CreateICmp(LLVMIntPredicate.SGT, sourceValue, maxValue)
    let overflow = irBuilder.CreateBinary(ExprKind.OR, downOverflow, upOverflow)
    irBuilder.CreateCondBr(overflow, blocks[0], blocks[2])
    irBuilder.SetInsertPoint(blocks[0])
    irBuilder.CreateCondBr(downOverflow, blocks[2], blocks[1])
    irBuilder.SetInsertPoint(blocks[1])
    irBuilder.CreateBr(blocks[2])
    irBuilder.SetInsertPoint(blocks[2])
    let result = irBuilder.CreatePHI(valueType, name: "result")
    let values = ArrayList<LLVMValueRef>()
    values.add(sourceValue)
    values.add(minValue)
    values.add(maxValue)
    let incomingBlocks = ArrayList<LLVMBasicBlockRef>()
    incomingBlocks.add(previousBB)
    incomingBlocks.add(blocks[0])
    incomingBlocks.add(blocks[1])
    irBuilder.AddIncoming(result, values, incomingBlocks)
    return result
}

private func EmitImportedCFuncIR(cgMod: CGModule, chirFunc: Function): Unit {
    let chirFuncTy = if (let Some(funcTy) <- chirFunc.GetFuncType()) { funcTy } else { return }
    if (!chirFuncTy.IsCFunc() || (!chirFunc.TestAttr(Attribute.PRIVATE) && !chirFunc.TestAttr(Attribute.FOREIGN))) {
        return
    }
    let srcPkgName = chirFunc.GetPackageName()
    let funcPkgName = if (srcPkgName.isEmpty()) { cgMod.GetCGContext().GetCurrentPkgName() } else { srcPkgName }
    if (funcPkgName != cgMod.GetCGContext().GetCurrentPkgName()) {
        return
    }
    EmitFunctionIR(cgMod, chirFunc)
}

private func SpecifyPackageInitFunc(cgMod: CGModule): Unit {
    if (let Some(initFn) <- cgMod.GetCGContext().GetCHIRPackage().GetPackageInitFunc()) {
        let initFuncName = GetCodeGenGlobalName(initFn)
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            LLVMAddNamedMetadataStringOperand(moduleHandle, PKG_INIT_FUNC_METADATA, initFuncName)
        }
        cgMod.GetCGContext().AddLLVMUsedVars(initFuncName)
    }
}

private func CreatePackageInitResetFunction(cgMod: CGModule): Unit {
    let pkgInitFuncName = GetPackageInitFuncName(cgMod) ?? return
    let funcName = ReplaceLastMangleSpecialName(pkgInitFuncName, SPECIAL_NAME_FOR_INIT_RESET_FUNCTION)
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        if (!GetNamedFunction(moduleHandle, funcName).isNull()) {
            return
        }
    }
    let llvmContext = cgMod.GetLLVMContext().raw
    let voidType = unsafe { LLVMVoidTypeInContext(llvmContext) }
    let i8Type = unsafe { LLVMInt8TypeInContext(llvmContext) }
    let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
    let functionType = BuildLLVMFunctionType(voidType, SingleTypeList(i8PtrType))
    let resetFunc = cgMod.GetOrInsertFunction(funcName, functionType)
    SetLLVMValueName(resetFunc, 0u32, "param")
    AddFnAttr(resetFunc, "noinline")
    cgMod.SetExceptionIntrinsicPersonality(resetFunc)
    AddLinkageTypeMetadata(resetFunc, LLVMLinkage.External, cgMod.GetCGContext().IsCGParallelEnabled())
    SetCangjieGC(resetFunc)

    try (irBuilder = IRBuilder2(cgMod)) {
        let entry = irBuilder.CreateEntryBasicBlock(resetFunc, "entry")
        unsafe { LLVMPositionBuilderAtEnd(irBuilder.GetBuilder().raw, entry) }
        let flagResetFunc = CreatePackageInitFlagResetFunction(cgMod)
        let voidFnType = unsafe { LLVMFunctionType(voidType, CPointer<LLVMTypeRef>(), 0u32, 0) }
        let _ = irBuilder.CreateCallOrInvoke(flagResetFunc, voidFnType, ArrayList<LLVMValueRef>())

        if (let Some(literalInitFunc) <- GetPackageInitSiblingFunction(cgMod, pkgInitFuncName,
            SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION)) {
            let _ = irBuilder.CreateCallOrInvoke(literalInitFunc, voidFnType, ArrayList<LLVMValueRef>())
        }
        if (let Some(gvInitFunc) <- GetNamedFunctionOpt(cgMod, pkgInitFuncName)) {
            let _ = irBuilder.CreateCallOrInvoke(gvInitFunc, voidFnType, ArrayList<LLVMValueRef>())
        }

        let cFuncType = BuildLLVMFunctionType(voidType, SingleTypeList(i8PtrType))
        let paramType = GetOrCreateNamedStructType(cgMod.GetLLVMContext(), "struct._param")
        let paramFields = ArrayList<LLVMTypeRef>()
        paramFields.add(unsafe { LLVMPointerType(cFuncType, 0u32) })
        paramFields.add(i8PtrType)
        SetStructTypeBody(paramType, paramFields)
        let wrapperFunc = GetGVResetCallBack(cgMod, cFuncType)
        let castParam = irBuilder.CreateBitCast(unsafe { LLVMGetParam(resetFunc, 0u32) },
            unsafe { LLVMPointerType(paramType, 0u32) })
        let wrapperArgs = ArrayList<LLVMValueRef>()
        wrapperArgs.add(irBuilder.CreateLoad(paramFields[0], irBuilder.CreateStructGEP(paramType, castParam, 0u32)))
        wrapperArgs.add(irBuilder.CreateLoad(paramFields[1], irBuilder.CreateStructGEP(paramType, castParam, 1u32)))
        let wrapperType = BuildLLVMFunctionType(voidType, paramFields)
        let _ = irBuilder.CreateCallOrInvoke(wrapperFunc, wrapperType, wrapperArgs)
        let _ = unsafe { LLVMBuildRetVoid(irBuilder.GetBuilder().raw) }
    }
}

private func CreatePackageInitFlagResetFunction(cgMod: CGModule): LLVMValueRef {
    let pkgInitFuncName = GetPackageInitFuncName(cgMod) ?? return LLVMNullValue()
    let funcName = ReplaceLastMangleSpecialName(pkgInitFuncName, SPECIAL_NAME_FOR_INIT_FLAG_RESET_FUNCTION)
    if (let Some(existing) <- GetNamedFunctionOpt(cgMod, funcName)) {
        return existing
    }

    let llvmContext = cgMod.GetLLVMContext().raw
    let voidType = unsafe { LLVMVoidTypeInContext(llvmContext) }
    let functionType = unsafe { LLVMFunctionType(voidType, CPointer<LLVMTypeRef>(), 0u32, 0) }
    let flagResetFunc = cgMod.GetOrInsertFunction(funcName, functionType)
    AddFnAttr(flagResetFunc, "noinline")
    cgMod.SetExceptionIntrinsicPersonality(flagResetFunc)
    AddLinkageTypeMetadata(flagResetFunc, LLVMLinkage.External, cgMod.GetCGContext().IsCGParallelEnabled())
    SetCangjieGC(flagResetFunc)

    try (irBuilder = IRBuilder2(cgMod)) {
        let entry = irBuilder.CreateEntryBasicBlock(flagResetFunc, "entry")
        unsafe { LLVMPositionBuilderAtEnd(irBuilder.GetBuilder().raw, entry) }
        CallDependentPackageGlobalResetCall(irBuilder)
        StoreFalseIfGlobalExists(cgMod, irBuilder, HAS_INVOKED_PKG_INIT_LITERAL)
        StoreFalseIfGlobalExists(cgMod, irBuilder, GV_PKG_INIT_ONCE_FLAG)
        let _ = unsafe { LLVMBuildRetVoid(irBuilder.GetBuilder().raw) }
    }
    return flagResetFunc
}

private func GetGVResetCallBack(cgMod: CGModule, callBackFuncType: LLVMTypeRef): LLVMValueRef {
    let llvmContext = cgMod.GetLLVMContext().raw
    let voidType = unsafe { LLVMVoidTypeInContext(llvmContext) }
    let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(llvmContext), 0u32) }
    let wrapperParamTypes = ArrayList<LLVMTypeRef>()
    wrapperParamTypes.add(unsafe { LLVMPointerType(callBackFuncType, 0u32) })
    wrapperParamTypes.add(i8PtrType)
    let wrapperFuncType = BuildLLVMFunctionType(voidType, wrapperParamTypes)
    let wrapperFunc = cgMod.GetOrInsertFunction("wrapper.F0uPuE", wrapperFuncType)
    if (unsafe { LLVMGetFirstBasicBlock(wrapperFunc) }.isNull()) {
        try (irBuilder = IRBuilder2(cgMod)) {
            let entry = irBuilder.CreateEntryBasicBlock(wrapperFunc, "entry")
            unsafe { LLVMPositionBuilderAtEnd(irBuilder.GetBuilder().raw, entry) }
            let args = ArrayList<LLVMValueRef>()
            args.add(unsafe { LLVMGetParam(wrapperFunc, 1u32) })
            let _ = irBuilder.CreateCall(unsafe { LLVMGetParam(wrapperFunc, 0u32) }, callBackFuncType, args)
            let _ = unsafe { LLVMBuildRetVoid(irBuilder.GetBuilder().raw) }
        }
    }
    unsafe { LLVMSetLinkage(wrapperFunc, LLVMLinkageValue(LLVMLinkage.Private)) }
    AddFnAttr(wrapperFunc, "noinline")
    AddFnAttr(wrapperFunc, CJ2C_ATTR)
    return wrapperFunc
}

private func CallDependentPackageGlobalResetCall(irBuilder: IRBuilder2): Unit {
    let pkgInitFuncName = GetPackageInitFuncName(irBuilder.GetCGModule()) ?? return
    let initFunc = GetNamedFunctionOpt(irBuilder.GetCGModule(), pkgInitFuncName) ?? return
    let giList = ArrayList<String>()
    CollectDependentPackages(initFunc, giList)
    let giFuncType = unsafe {
        LLVMFunctionType(LLVMVoidTypeInContext(irBuilder.GetLLVMContext().raw), CPointer<LLVMTypeRef>(), 0u32, 0)
    }
    for (gi in giList) {
        let flagResetFunc = irBuilder.GetCGModule().GetOrInsertFunction(gi, giFuncType)
        AddFnAttr(flagResetFunc, "noinline")
        let _ = irBuilder.CreateCall(flagResetFunc, giFuncType, ArrayList<LLVMValueRef>())
    }
}

private func CollectDependentPackages(llvmFunc: LLVMValueRef, giList: ArrayList<String>): Unit {
    let isCallInstSymbol = LookupLLVMOptionalSymbol("LLVMIsACallInst")
    let getCalledValueSymbol = LookupLLVMOptionalSymbol("LLVMGetCalledValue")
    if (isCallInstSymbol.isNull() || getCalledValueSymbol.isNull()) {
        return
    }
    let isCallInst = LLVMIsACallInstFunc(isCallInstSymbol)
    let getCalledValue = LLVMGetCalledValueFunc(getCalledValueSymbol)
    let callDependentPackageInitSuffix = SPECIAL_NAME_FOR_INIT_FLAG_RESET_FUNCTION +
        MANGLE_FUNC_PARAM_TYPE_PREFIX + MANGLE_VOID_TY_SUFFIX
    let callDependentPackagesInitsSuffix = SPECIAL_NAME_FOR_IMPORTS_INIT_FUNCTION +
        MANGLE_FUNC_PARAM_TYPE_PREFIX + MANGLE_VOID_TY_SUFFIX

    var block = unsafe { LLVMGetFirstBasicBlock(llvmFunc) }
    while (!block.isNull()) {
        var inst = unsafe { LLVMGetFirstInstruction(block) }
        while (!inst.isNull()) {
            if (!unsafe { isCallInst(inst) }.isNull()) {
                let callee = unsafe { getCalledValue(inst) }
                if (!callee.isNull() && !unsafe { LLVMIsAFunction(callee) }.isNull()) {
                    let calleeName = LLVMCStringToString(unsafe { LLVMGetValueName(callee) }) ?? ""
                    CollectDependentPackageByCalleeName(callee, calleeName, callDependentPackageInitSuffix,
                        callDependentPackagesInitsSuffix, giList)
                }
            }
            inst = unsafe { LLVMGetNextInstruction(inst) }
        }
        block = unsafe { LLVMGetNextBasicBlock(block) }
    }
}

private func CollectDependentPackageByCalleeName(callee: LLVMValueRef, calleeName: String,
    callDependentPackageInitSuffix: String, callDependentPackagesInitsSuffix: String,
    giList: ArrayList<String>): Unit {
    if (calleeName.size < callDependentPackageInitSuffix.size) {
        return
    }
    let calleePrefixSize = calleeName.size - callDependentPackageInitSuffix.size
    let calleePrefix = calleeName[0..calleePrefixSize]
    let calleeSuffix = calleeName[calleePrefixSize..]
    if (calleeSuffix == callDependentPackagesInitsSuffix) {
        CollectDependentPackages(callee, giList)
    } else if (calleeName.startsWith(PKG_GV_INIT_PREFIX)) {
        giList.add(calleePrefix + callDependentPackageInitSuffix)
    }
}

private func StoreFalseIfGlobalExists(cgMod: CGModule, irBuilder: IRBuilder2, globalName: String): Unit {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let global = GetNamedGlobal(moduleHandle, globalName)
        if (!global.isNull()) {
            let _ = irBuilder.CreateStore(irBuilder.GetFalse(), global)
        }
    }
}

private func GetPackageInitSiblingFunction(cgMod: CGModule, pkgInitFuncName: String,
    specialName: String): Option<LLVMValueRef> {
    return GetNamedFunctionOpt(cgMod, ReplaceLastMangleSpecialName(pkgInitFuncName, specialName))
}

private func ReplaceLastMangleSpecialName(pkgInitFuncName: String, specialName: String): String {
    let targetSuffix = specialName + MANGLE_FUNC_PARAM_TYPE_PREFIX + MANGLE_VOID_TY_SUFFIX
    return pkgInitFuncName[0..(pkgInitFuncName.size - targetSuffix.size)] + targetSuffix
}

private func GetPackageInitFuncName(cgMod: CGModule): Option<String> {
    if (let Some(initFn) <- cgMod.GetCGContext().GetCHIRPackage().GetPackageInitFunc()) {
        return Some(GetCodeGenGlobalName(initFn))
    }
    return None
}

private func GetNamedFunctionOpt(cgMod: CGModule, name: String): Option<LLVMValueRef> {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let function = GetNamedFunction(moduleHandle, name)
        if (!function.isNull()) {
            return Some(function)
        }
    }
    return None
}

private func GetNamedFunction(moduleHandle: LLVMModuleHandle, name: String): LLVMValueRef {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
    }
    return result
}

private func GetNamedGlobal(moduleHandle: LLVMModuleHandle, name: String): LLVMValueRef {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
    }
    return result
}

private func SingleTypeList(ty: LLVMTypeRef): ArrayList<LLVMTypeRef> {
    let out = ArrayList<LLVMTypeRef>()
    out.add(ty)
    return out
}

private func SetLLVMValueName(parent: LLVMValueRef, paramIndex: UInt32, name: String): Unit {
    let setNameSymbol = LookupLLVMOptionalSymbol("LLVMSetValueName2")
    if (setNameSymbol.isNull()) {
        return
    }
    let setName = LLVMSetValueName2Func(setNameSymbol)
    let value = unsafe { LLVMGetParam(parent, paramIndex) }
    if (value.isNull()) {
        return
    }
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        unsafe { setName(value, nameCString.value, UIntNative(name.size)) }
    }
}

private func FindMainEntryFunction(cgMod: CGModule): Option<Function> {
    for (chirFunc in cgMod.GetCGContext().GetSubCHIRPackage().chirFuncs) {
        if (chirFunc.GetFuncKind() == FuncKind.MAIN_ENTRY) {
            return Some(chirFunc)
        }
    }
    for (chirFunc in cgMod.GetCGContext().GetCHIRPackage().GetGlobalFunctions(includePureAbstract: true)) {
        if (chirFunc.GetFuncKind() == FuncKind.MAIN_ENTRY) {
            return Some(chirFunc)
        }
    }
    return None
}

private func BuildLLVMFunctionType(returnType: LLVMTypeRef, paramTypes: ArrayList<LLVMTypeRef>): LLVMTypeRef {
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

private func GetOrInsertLLVMFunction(moduleHandle: LLVMModuleHandle, name: String, functionType: LLVMTypeRef): LLVMValueRef {
    var functionValue = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        functionValue = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
        if (functionValue.isNull()) {
            functionValue = unsafe { LLVMAddFunction(moduleHandle.raw, nameCString.value, functionType) }
        }
    }
    return functionValue
}

private func BuildVoidCall(builder: LLVMBuilderRef, functionType: LLVMTypeRef, callee: LLVMValueRef,
    args: ArrayList<LLVMValueRef>): Unit {
    try (callName = unsafe { LibC.mallocCString("") }.asResource()) {
        if (args.isEmpty()) {
            let _ = unsafe { LLVMBuildCall2(builder, functionType, callee, CPointer<LLVMValueRef>(), 0u32,
                callName.value) }
            return
        }
        try (argPtr = LibC.malloc<LLVMValueRef>(count: args.size).asResource()) {
            var idx: Int64 = 0
            while (idx < args.size) {
                unsafe { (argPtr.value + idx).write(args[idx]) }
                idx++
            }
            let _ = unsafe { LLVMBuildCall2(builder, functionType, callee, argPtr.value, UInt32(args.size),
                callName.value) }
        }
    }
}

private func KeepSomeTypesManually(cgMod: CGModule): LLVMValueRef {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let llvmContext = cgMod.GetLLVMContext().raw
        let functionType = unsafe {
            LLVMFunctionType(LLVMVoidTypeInContext(llvmContext), CPointer<LLVMTypeRef>(), 0u32, 0)
        }
        let functionValue = GetOrInsertLLVMFunction(moduleHandle, FOR_KEEPING_SOME_TYPES_FUNC_NAME, functionType)
        AddFnAttr(functionValue, "noinline")
        AddFnAttr(functionValue, "optnone")
        AddLinkageTypeMetadata(functionValue, LLVMLinkage.Private, false)
        try (blockName = unsafe { LibC.mallocCString("entry.unreachable") }.asResource(),
            allocaName = unsafe { LibC.mallocCString("") }.asResource()) {
            let builder = unsafe { LLVMCreateBuilderInContext(llvmContext) }
            let entryBlock = unsafe { LLVMAppendBasicBlockInContext(llvmContext, functionValue, blockName.value) }
            unsafe { LLVMPositionBuilderAtEnd(builder, entryBlock) }
            for (structTypeName in cgMod.GetCGContext().GetGeneratedStructType()) {
                try (typeName = unsafe { LibC.mallocCString(structTypeName) }.asResource()) {
                    let structType = unsafe { LLVMGetTypeByName2(llvmContext, typeName.value) }
                    if (!structType.isNull()) {
                        let _ = unsafe { LLVMBuildAlloca(builder, structType, allocaName.value) }
                    }
                }
            }
            unsafe {
                LLVMBuildRetVoid(builder)
                LLVMDisposeBuilder(builder)
            }
        }
        return functionValue
    }
    return LLVMNullValue()
}

private func EmitStaticGenericTIsAndLLVMUsed(cgMod: CGModule, keepTypesFunc: LLVMValueRef): Unit {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let usedValues = ArrayList<LLVMValueRef>()
        if (!keepTypesFunc.isNull()) {
            usedValues.add(keepTypesFunc)
        }
        let staticGITable = EmitStaticGenericTITable(cgMod)
        if (!staticGITable.isNull()) {
            usedValues.add(staticGITable)
        }
        let llvmContext = cgMod.GetLLVMContext().raw
        let llvmUsedNames = ArrayList<String>()
        for (usedName in cgMod.GetCGContext().GetLLVMUsedVars()) {
            llvmUsedNames.add(usedName)
        }
        sort(llvmUsedNames, by: { left: String, right: String => CompareString(left, right) })
        for (usedName in llvmUsedNames) {
            var usedValue = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(usedName) }.asResource()) {
                usedValue = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
                if (usedValue.isNull()) {
                    usedValue = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameCString.value) }
                }
            }
            if (!usedValue.isNull()) {
                usedValues.add(usedValue)
            }
        }
        if (usedValues.isEmpty()) {
            return
        }
        let i8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(llvmContext), 0u32) }
        let usedArrayType = unsafe { LLVMArrayType(i8PtrType, UInt32(usedValues.size)) }
        var llvmUsed = LLVMNullValue()
        try (nameCString = unsafe { LibC.mallocCString("llvm.used") }.asResource()) {
            llvmUsed = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
            if (llvmUsed.isNull()) {
                llvmUsed = unsafe { LLVMAddGlobal(moduleHandle.raw, usedArrayType, nameCString.value) }
            }
        }
        let initializerValues = ArrayList<LLVMValueRef>()
        for (value in usedValues) {
            initializerValues.add(unsafe { LLVMConstBitCast(value, i8PtrType) })
        }
        unsafe {
            LLVMSetInitializer(llvmUsed, ConstLLVMArray(i8PtrType, initializerValues))
            LLVMSetLinkage(llvmUsed, LLVMLinkageValue(LLVMLinkage.Appending))
        }
        try (sectionName = unsafe { LibC.mallocCString("llvm.metadata") }.asResource()) {
            unsafe { LLVMSetSection(llvmUsed, sectionName.value) }
        }
    }
}

private func EmitStaticGenericTITable(cgMod: CGModule): LLVMValueRef {
    let staticGINames = cgMod.GetCGContext().GetStaticGINames()
    if (staticGINames.isEmpty()) {
        return LLVMNullValue()
    }
    let typeInfoType = CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext())
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
    let values = ArrayList<LLVMValueRef>()
    for (typeInfoName in staticGINames) {
        values.add(GetOrInsertCodeGenGlobal(cgMod, typeInfoName, typeInfoType))
    }
    let arrayType = unsafe { LLVMArrayType(typeInfoPtrType, UInt32(values.size)) }
    let table = GetOrInsertCodeGenGlobal(cgMod, "StaticGenericTIs", arrayType)
    unsafe {
        LLVMSetInitializer(table, ConstLLVMArray(typeInfoPtrType, values))
        LLVMSetLinkage(table, LLVMLinkageValue(LLVMLinkage.Private))
        LLVMSetGlobalConstant(table, 0)
    }
    return table
}

private func ConstLLVMArray(elementType: LLVMTypeRef, values: ArrayList<LLVMValueRef>): LLVMValueRef {
    if (values.isEmpty()) {
        return unsafe { LLVMConstArray(elementType, CPointer<LLVMValueRef>(), 0u32) }
    }
    var result = LLVMNullValue()
    try (valuePtr = LibC.malloc<LLVMValueRef>(count: values.size).asResource()) {
        var idx: Int64 = 0
        while (idx < values.size) {
            unsafe { (valuePtr.value + idx).write(values[idx]) }
            idx++
        }
        result = unsafe { LLVMConstArray(elementType, valuePtr.value, UInt32(values.size)) }
    }
    return result
}

private func CompareString(left: String, right: String): Ordering {
    if (left < right) {
        return Ordering.LT
    }
    if (left > right) {
        return Ordering.GT
    }
    return Ordering.EQ
}

public func SavePackageModule(module: LLVMModuleHandle, bcFilePath: String): Bool {
    var result: Int32 = 1
    try (pathCString = unsafe { LibC.mallocCString(bcFilePath) }.asResource()) {
        result = unsafe { LLVMWriteBitcodeToFile(module.raw, pathCString.value) }
    }
    return result == 0
}

public func ClearPackageModules(packageModules: ArrayList<LLVMModuleHandle>): Unit {
    for (moduleHandle in packageModules) {
        unsafe { LLVMDisposeModule(moduleHandle.raw) }
    }
    packageModules.clear()
}
