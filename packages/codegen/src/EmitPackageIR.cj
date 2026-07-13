package cjcj::codegen

import std.collection.*
import std.sort.*
import cjcj::chir.Attribute
import cjcj::chir.CustomDefKind
import cjcj::chir.EnumType
import cjcj::chir.ExprKind
import cjcj::chir.Function
import cjcj::chir.NoHeapAllocChecker
import cjcj::chir.NoWriteBarrierRecChecker
import cjcj::chir.Type
import cjcj::option.EnvironmentType
import cjcj::mangle.MANGLE_FUNC_PARAM_TYPE_PREFIX
import cjcj::mangle.MANGLE_VOID_TY_SUFFIX
import cjcj::mangle.SPECIAL_NAME_FOR_IMPORTS_INIT_FUNCTION
import cjcj::mangle.SPECIAL_NAME_FOR_INIT_FLAG_RESET_FUNCTION
import cjcj::mangle.SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION
import cjcj::mangle.SPECIAL_NAME_FOR_INIT_RESET_FUNCTION
import cjcj::option.GlobalOptions
import cjcj::utils.{CJC_ASSERT, CORE_PACKAGE_NAME, StaticCast}

// GAP_TODO(sdk-version-injection): C++ derives this from the CJ_SDK_VERSION build macro
// (src/Basic/Version.cpp:18 CANGJIE_VERSION = CJ_SDK_VERSION), so it always matches the
// toolchain that builds the compiler. The self-host build has no equivalent build-time
// injection yet, so the value is hard-coded to the current toolchain version; it must be
// bumped in lock-step with the runtime until an injection mechanism exists, otherwise the
// runtime's CheckPackageCompatibility rejects (or, when absent, null-derefs on) the .so.
private let CANGJIE_SDK_VERSION: String = "1.2.0-alpha.20260619020029"
private let PKG_INIT_FUNC_METADATA: String = "pkg_init_func"
private let HAS_INVOKED_PKG_INIT_LITERAL: String = "has_invoked_pkg_init_literal"

private type LLVMIsACallInstFunc = CFunc<(LLVMValueRef) -> LLVMValueRef>
private type LLVMGetCalledValueFunc = CFunc<(LLVMValueRef) -> LLVMValueRef>
private type LLVMSetValueName2Func = CFunc<(LLVMValueRef, CString, UIntNative) -> Unit>

public func GenPackageModules(chirData: CHIRData, options: GlobalOptions, enableIncrement: Bool,
    noHeapAllocChecker: NoHeapAllocChecker, noWriteBarrierRecChecker: NoWriteBarrierRecChecker,
    cachedMangleMap!: CachedMangleMap = CachedMangleMap()): ArrayList<LLVMModuleHandle> {
    let cgPkgContext = CGPkgContext(chirData, options, enableIncrement, noHeapAllocChecker,
        noWriteBarrierRecChecker, cachedMangleMap)
    let splitter = CHIRSplitter(cgPkgContext)
    let subPackages = splitter.SplitCHIRPackage()
    for (subPackageToRegister in subPackages) {
        let cgModToRegister = CGModule(subPackageToRegister, cgPkgContext)
        cgPkgContext.AddCGModule(cgModToRegister)
    }
    let cgModules = cgPkgContext.GetCGModules()
    var emitIdx: Int64 = 0
    while (emitIdx < subPackages.size) {
        let subPackageToEmit = subPackages[emitIdx]
        let cgModToEmit = cgModules[emitIdx]
        EmitTIOrTTForCustomDefs(cgModToEmit)
        for (globalVar in subPackageToEmit.chirGVs) {
            EmitGlobalVariableIR(cgModToEmit, globalVar)
        }
        for (chirFunc in subPackageToEmit.chirFuncs) {
            EmitFunctionIR(cgModToEmit, chirFunc)
        }
        for (chirFunc in subPackageToEmit.chirImportedCFuncs) {
            EmitImportedCFuncIR(cgModToEmit, chirFunc)
        }
        if (subPackageToEmit.mainModule) {
            // Mirror C++ EmitPackageIR.cpp:359: the main-module block runs for every output type,
            // including libraries. Emitting the SDK version and the package-init-reset function is
            // required for a shared/static library to be loadable by the runtime (the runtime reads
            // the SDK version at dlopen time via CheckPackageCompatibility). Only the executable
            // entry (main/cj_entry$) is output-type-specific, so its guard lives inside
            // EmitMain (mirroring C++ EmitMain's internal CompileExecutable() early-return).
            EmitCJSDKVersion(cgModToEmit)
            EmitMain(cgModToEmit)
            RegisterExceptionRaiser(cgModToEmit)
            CreatePackageInitResetFunction(cgModToEmit)
            SpecifyPackageInitFunc(cgModToEmit)
        }
        GenerateInterfaceExtensionDefs(cgModToEmit)
        // Mirror C++ EmitPackageIR.cpp:370 cgMod.GenTypeTemplate(): drain delayed generic
        // TypeTemplate definitions before TypeInfo generation.
        cgModToEmit.GenTypeTemplate()
        // Mirror C++ EmitPackageIR.cpp:372 cgMod.GenTypeInfo(): drain the delayed concrete-TypeInfo
        // definitions (queued by CGType.GetOrCreateTypeInfo) before optimization.
        cgModToEmit.GenTypeInfo()
        ReplaceFunction(cgModToEmit)
        cgModToEmit.Opt()
        GenerateReflectionMetadata(cgModToEmit, subPackageToEmit)
        cgModToEmit.GenTypeInfo()
        InitializeCjStringLiteral(cgModToEmit)
        GenerateBinarySectionInfo(cgModToEmit)
        KeepSomeTypesManually(cgModToEmit)
        cgModToEmit.EraseUselessInstsAndDeclarations()
        SetSymbolLinkageType(cgModToEmit)
        EmitStaticGenericTIsAndLLVMUsed(cgModToEmit)
        emitIdx++
    }
    let localizedSymbols = cgPkgContext.GetLocalizedSymbols()
    let localizedSymbolsVec = ArrayList<String>()
    for (symbol in localizedSymbols) {
        localizedSymbolsVec.add(symbol)
    }
    sort(localizedSymbolsVec, by: { left: String, right: String => CompareString(left, right) })
    options.symbolsNeedLocalized.clear()
    for (symbol in localizedSymbolsVec) {
        options.symbolsNeedLocalized.add(symbol)
    }
    let localizedSymbolsForPkg = ArrayList<String>()
    for (symbol in localizedSymbolsVec) {
        localizedSymbolsForPkg.add(symbol)
    }
    options.symbolsNeedLocalizedPerPkg[cgPkgContext.GetCHIRPackage().GetName()] = localizedSymbolsForPkg
    return cgPkgContext.ReleaseLLVMModules()
}

private func SetSymbolLinkageType(cgMod: CGModule): Unit {
    let moduleHandle = cgMod.GetLLVMModule() ?? return
    let linkageTypeKind = LLVMGetMDKindID(cgMod.GetLLVMContext(), "LinkageType")
    var globalObject = unsafe { LLVMGetFirstGlobal(moduleHandle.raw) }
    while (!globalObject.isNull()) {
        var hasLinkageType = false
        if (linkageTypeKind != 0u32) {
            try (countPtr = LibC.malloc<UIntNative>().asResource()) {
                unsafe { countPtr.value.write(UIntNative(0)) }
                let entries = unsafe { LLVMGlobalCopyAllMetadata(globalObject, countPtr.value) }
                let count = unsafe { countPtr.value.read() }
                if (!entries.isNull()) {
                    var idx: UInt32 = 0u32
                    while (idx < UInt32(count)) {
                        if (unsafe { LLVMValueMetadataEntriesGetKind(entries, idx) } == linkageTypeKind) {
                            hasLinkageType = true
                            break
                        }
                        idx++
                    }
                    unsafe { LLVMDisposeValueMetadataEntries(entries) }
                }
            }
        }
        if (hasLinkageType) {
            let linkageType = GetLinkageTypeOfGlobalObject(globalObject)
            LLVMEraseGlobalMetadata(cgMod.GetLLVMContext(), globalObject, "LinkageType")
            if (unsafe { LLVMIsDeclaration(globalObject) } == 0) {
                if (LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.WeakODR) ||
                    LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.LinkOnceAny) ||
                    LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.LinkOnceODR)) {
                    unsafe { LLVMSetLinkage(globalObject, LLVMLinkageValue(linkageType)) }
                } else if (LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.Internal) ||
                    LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.Private)) {
                    cgMod.GetCGContext().AddLocalizedSymbol(
                        LLVMCStringToString(unsafe { LLVMGetValueName(globalObject) }) ?? "")
                }
            }
        }
        globalObject = unsafe { LLVMGetNextGlobal(globalObject) }
    }
    var functionObject = unsafe { LLVMGetFirstFunction(moduleHandle.raw) }
    while (!functionObject.isNull()) {
        var hasLinkageType = false
        if (linkageTypeKind != 0u32) {
            try (countPtr = LibC.malloc<UIntNative>().asResource()) {
                unsafe { countPtr.value.write(UIntNative(0)) }
                let entries = unsafe { LLVMGlobalCopyAllMetadata(functionObject, countPtr.value) }
                let count = unsafe { countPtr.value.read() }
                if (!entries.isNull()) {
                    var idx: UInt32 = 0u32
                    while (idx < UInt32(count)) {
                        if (unsafe { LLVMValueMetadataEntriesGetKind(entries, idx) } == linkageTypeKind) {
                            hasLinkageType = true
                            break
                        }
                        idx++
                    }
                    unsafe { LLVMDisposeValueMetadataEntries(entries) }
                }
            }
        }
        if (hasLinkageType) {
            let linkageType = GetLinkageTypeOfGlobalObject(functionObject)
            LLVMEraseGlobalMetadata(cgMod.GetLLVMContext(), functionObject, "LinkageType")
            if (unsafe { LLVMIsDeclaration(functionObject) } == 0) {
                if (LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.WeakODR) ||
                    LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.LinkOnceAny) ||
                    LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.LinkOnceODR)) {
                    unsafe { LLVMSetLinkage(functionObject, LLVMLinkageValue(linkageType)) }
                } else if (LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.Internal) ||
                    LLVMLinkageValue(linkageType) == LLVMLinkageValue(LLVMLinkage.Private)) {
                    cgMod.GetCGContext().AddLocalizedSymbol(
                        LLVMCStringToString(unsafe { LLVMGetValueName(functionObject) }) ?? "")
                }
            }
        }
        functionObject = unsafe { LLVMGetNextFunction(functionObject) }
    }
}

private func ReplaceFunction(cgMod: CGModule): Unit {
    if (!cgMod.GetCGContext().GetCompileOptions().enableCompileDebug) {
        return
    }

    try (irBuilder = IRBuilder2(cgMod)) {
        let callBasesToReplace = cgMod.GetCGContext().GetCallBasesToReplace()
        for (item in callBasesToReplace) {
            irBuilder.SetInsertCGFunction(item.cgFuncCaller)
            let oldCall = item.callWithoutTI
            irBuilder.SetInsertPointBefore(oldCall)
            let hasSRet = unsafe { LLVMSelfhostCallBaseHasStructRetAttr(oldCall) } != 0
            let thisParamOffset: Int64 = if (hasSRet) { 1 } else { 0 }
            let thisParamWithoutTI = unsafe { LLVMSelfhostCallBaseGetArgOperand(oldCall, UInt32(thisParamOffset)) }
            let argsVal = ArrayList<LLVMValueRef>()
            let argCount = unsafe { LLVMSelfhostCallBaseArgSize(oldCall) }
            var argIdx: UInt32 = 0u32
            while (argIdx < argCount) {
                argsVal.add(unsafe { LLVMSelfhostCallBaseGetArgOperand(oldCall, argIdx) })
                argIdx++
            }
            var basePtr = LLVMNullValue()
            if (item.isCalleeMutOrCtor) {
                let basePtrIndex = thisParamOffset + 1
                basePtr = argsVal[basePtrIndex]
                argsVal.remove(at: basePtrIndex)
            }

            let thisCHIRType = DeRef(item.thisParamType)
            let typeInfoCacheMap = cgMod.GetCGContext().genericParamsCacheMap
            let insertFunctionKey = irBuilder.GetInsertFunction().toUIntNative()
            if (!typeInfoCacheMap.contains(insertFunctionKey)) {
                typeInfoCacheMap[insertFunctionKey] = HashMap<Int64, LLVMValueRef>()
            }
            typeInfoCacheMap[insertFunctionKey].clear()
            let blockKey = irBuilder.GetInsertBlock().toUIntNative()
            let sizeCacheMap = cgMod.GetCGContext().genericParamsSizeBlockLevelCacheMap
            if (!sizeCacheMap.contains(blockKey)) {
                sizeCacheMap[blockKey] = HashMap<UIntNative, LLVMValueRef>()
            }
            sizeCacheMap[blockKey].clear()
            let thisParamTypeInfo = irBuilder.CreateTypeInfo(thisCHIRType)
            let size32 = irBuilder.GetLayoutSize_32(thisCHIRType)
            let size64 = irBuilder.CreateSExt(size32, unsafe { LLVMInt64TypeInContext(cgMod.GetLLVMContext().raw) })
            let thisParamWithTI = irBuilder.CallIntrinsicAllocaGeneric(ArrayList<LLVMValueRef>(
                [thisParamTypeInfo, size32]))
            argsVal[thisParamOffset] = thisParamWithTI

            let payloadPtr = irBuilder.GetPayloadFromObject(thisParamWithTI)
            let thisLLVMType = CGType.GetOrCreate(cgMod, thisCHIRType).GetLLVMType()
            if (irBuilder.IsLLVMTypeContainsRef(thisLLVMType)) {
                if (item.isCalleeMutOrCtor) {
                    let load = irBuilder.CreateEntryAlloca(thisLLVMType)
                    let _ = irBuilder.CreateCJMemsetStructWith0(load, thisLLVMType)
                    irBuilder.CallGCReadAgg(thisLLVMType, ArrayList<LLVMValueRef>(
                        [load, basePtr, thisParamWithoutTI, size64]))
                    irBuilder.CallGCWriteAgg(thisLLVMType, ArrayList<LLVMValueRef>(
                        [thisParamWithTI, payloadPtr, load, size64]))
                } else {
                    irBuilder.CallGCWriteAgg(thisLLVMType, ArrayList<LLVMValueRef>(
                        [thisParamWithTI, payloadPtr, thisParamWithoutTI, size64]))
                }
            } else {
                irBuilder.CreateMemCpy(payloadPtr, 0u32, thisParamWithoutTI, 0u32, size32)
            }

            let callee = item.cgFuncCallee.GetWrapperFunction()
            CJC_ASSERT(!callee.isNull())
            let calleeType = unsafe { LLVMGlobalGetValueType(callee) }
            var newCall = LLVMNullValue()
            if (unsafe { LLVMSelfhostIsCallInst(oldCall) } != 0) {
                newCall = irBuilder.CreateCall(callee, calleeType, argsVal)
                irBuilder.SetInsertPointBefore(unsafe { LLVMGetNextInstruction(oldCall) })
            } else if (unsafe { LLVMSelfhostIsInvokeInst(oldCall) } != 0) {
                let normalDest = unsafe { LLVMSelfhostInvokeGetNormalDest(oldCall) }
                let unwindDest = unsafe { LLVMSelfhostInvokeGetUnwindDest(oldCall) }
                newCall = irBuilder.CreateInvoke(callee, calleeType, normalDest, unwindDest, argsVal)
                let firstInsertionPoint = unsafe { LLVMSelfhostBasicBlockGetFirstInsertionPoint(normalDest) }
                if (firstInsertionPoint.isNull()) {
                    irBuilder.SetInsertPoint(normalDest)
                } else {
                    irBuilder.SetInsertPointBefore(firstInsertionPoint)
                }
            }
            CJC_ASSERT(!newCall.isNull())
            if (hasSRet) {
                let sretAttr = unsafe { LLVMSelfhostCallBaseGetStructRetAttr(oldCall) }
                unsafe { LLVMSelfhostCallBaseAddAttributeAtIndex(newCall, 1u32, sretAttr) }
                AddAttributeAtIndex(newCall, 1u32, "noalias")
            }
            unsafe {
                LLVMSelfhostInstructionCopyMetadata(newCall, oldCall)
                LLVMReplaceAllUsesWith(oldCall, newCall)
                LLVMInstructionEraseFromParent(oldCall)
            }

            if (!item.isCalleeMutOrCtor) {
                continue
            }
            if (irBuilder.IsLLVMTypeContainsRef(thisLLVMType)) {
                let load = irBuilder.CreateEntryAlloca(thisLLVMType)
                let _ = irBuilder.CreateCJMemsetStructWith0(load, thisLLVMType)
                irBuilder.CallGCReadAgg(thisLLVMType, ArrayList<LLVMValueRef>(
                    [load, thisParamWithTI, payloadPtr, size64]))
                irBuilder.CallGCWriteAgg(thisLLVMType, ArrayList<LLVMValueRef>(
                    [basePtr, thisParamWithoutTI, load, size64]))
            } else {
                irBuilder.CreateMemCpy(thisParamWithoutTI, 0u32, payloadPtr, 0u32, size32)
            }
        }
    }
}

private func EmitTIOrTTForCustomDefs(cgMod: CGModule): Unit {
    for (def in cgMod.GetCGContext().GetSubCHIRPackage().chirCustomDefs) {
        if (!def.IsExtend()) {
            let cgType = CGType.GetOrCreate(cgMod, def.GetType().getOrThrow())
            if (cgType.IsConcrete()) {
                cgType.GetOrCreateTypeInfo()
            }
            if (def.IsGenericDef()) {
                cgType.GetOrCreateTypeTemplate()
            }
        }
        if (def.TestAttr(Attribute.IMPORTED) || def.TestAttr(Attribute.NON_RECOMPILE)) {
            continue
        }
        if (def.GetCustomKind() == CustomDefKind.TYPE_ENUM) {
            let enumTy = StaticCast<EnumType>(def.GetType().getOrThrow())
            let cgEnumType = StaticCast<CGEnumType>(CGType.GetOrCreate(cgMod, enumTy))
            if ((!cgEnumType.IsTrivial() && !cgEnumType.IsZeroSizeEnum()) ||
                (!cgMod.GetCGContext().GetCompileOptions().disableReflection &&
                    cgMod.GetCGContext().GetCompileOptions().target.env != EnvironmentType.OHOS)) {
                let ctors = enumTy.GetEnumDef().GetConstructorInfos(builder: Some(cgMod.GetCGContext().GetCHIRBuilder()))
                var idx: Int64 = 0
                while (idx < ctors.size) {
                    cgMod.GetOrCreateEnumCtorTIOrTT(enumTy, idx)
                    idx++
                }
            }
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
                LLVMSetAlignment(versionGlobal, 1u32)
                LLVMSetLinkage(versionGlobal, LLVMLinkageValue(LLVMLinkage.Private))
            }
            cgMod.GetCGContext().AddLLVMUsedVars("cj.sdk.version")
        }
    }
}

private func EmitMain(cgMod: CGModule): Unit {
    // Mirror C++ EmitMain (EmitPackageIR.cpp:253): the executable entry is only emitted when
    // compiling an executable; for a library the runtime provides no `main`.
    if (!cgMod.GetCGContext().GetCompileOptions().CompileExecutable()) {
        return
    }
    // Mirror C++ EmitMain (EmitPackageIR.cpp:258-267): only the package that actually defines the
    // user main emits `main`/`cj_entry$`. When mutually-dependent source packages are compiled
    // together into one executable, a sibling package may *find* the user main as an IMPORTED
    // declaration in its own CHIR; emitting the entry for it causes "multiple definition of
    // `main`/`cj_entry$`" at link time. Skip when no user main is visible, or the visible one is
    // imported from another package.
    let userMainEntry = FindUserMainFunction(cgMod)
    if (userMainEntry.isNone() || userMainEntry.getOrThrow().TestAttr(Attribute.IMPORTED)) {
        return
    }
    let userMainFunc = cgMod.GetOrInsertCGFunction(userMainEntry.getOrThrow())
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
                let cjEntryFunc = CreateCJEntryFunction(cgMod, moduleHandle, llvmContext, i32Type,
                    userMainFunc.GetRawFunction())
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

private func CreateCJEntryFunction(cgMod: CGModule, moduleHandle: LLVMModuleHandle, llvmContext: LLVMContextRef,
    i32Type: LLVMTypeRef, userMain: LLVMValueRef): LLVMValueRef {
    let entryType = unsafe { LLVMFunctionType(i32Type, CPointer<LLVMTypeRef>(), 0u32, 0) }
    let entryFunc = GetOrInsertLLVMFunction(moduleHandle, CJ_ENTRY_FUNC_NAME, entryType)
    SetCangjieGC(entryFunc)
    cgMod.SetExceptionIntrinsicPersonality(entryFunc)
    try (blockName = unsafe { LibC.mallocCString("entry") }.asResource()) {
        let entryBlock = unsafe { LLVMAppendBasicBlockInContext(llvmContext, entryFunc, blockName.value) }
        try (irBuilder = IRBuilder2(cgMod, entryBlock)) {
            let voidType = unsafe { LLVMVoidTypeInContext(llvmContext) }
            let voidFnType = unsafe { LLVMFunctionType(voidType, CPointer<LLVMTypeRef>(), 0u32, 0) }
            let checkThreadLocal = GetOrInsertLLVMFunction(moduleHandle,
                PREFIX_OF_BACKEND_SYMS + "CheckThreadLocalDataOffset", voidFnType)
            let _ = irBuilder.CreateCallOrInvoke(checkThreadLocal, ArrayList<LLVMValueRef>())

            let unwindBlock = irBuilder.CreateAndInsertBasicBlock("unwindDest")
            try (unwindScope = CodeGenUnwindBlockScope(cgMod, unwindBlock)) {
                CreateCJEntryTryScope(cgMod, irBuilder, userMain, i32Type)
            }
            irBuilder.SetInsertPoint(unwindBlock)
            CreateUnwindBlockForTryCatchWrapper(cgMod, irBuilder, i32Type)
        }
    }
    return entryFunc
}

private func CreateCJEntryTryScope(cgMod: CGModule, irBuilder: IRBuilder2, userMain: LLVMValueRef,
    i32Type: LLVMTypeRef): Unit {
    let initFn = cgMod.GetCGContext().GetCHIRPackage().GetPackageInitFunc().getOrThrow()
    let cgInit = cgMod.GetOrInsertCGFunction(initFn)
    let _ = irBuilder.CreateCallOrInvoke(cgInit.GetRawFunction(), ArrayList<LLVMValueRef>())

    let userMainArgs = ArrayList<LLVMValueRef>()
    if (unsafe { LLVMCountParams(userMain) } > 0u32) {
        let getCommandLineArgsFuncCHIRNode = cgMod.GetCGContext().GetImplicitUsedFunc(
            "_CNat18getCommandLineArgsHv").getOrThrow()
        let getCommandLineArgsFuncReturnType = getCommandLineArgsFuncCHIRNode.GetFuncType().getOrThrow().GetReturnType()
        let retCGType = CGType.GetOrCreate(cgMod, getCommandLineArgsFuncReturnType)
        let commandLineArgs = irBuilder.CreateEntryAlloca(retCGType.GetLLVMType())
        let _ = irBuilder.CreateCJMemsetStructWith0(commandLineArgs, retCGType.GetLLVMType())
        let commandLineArgsCallArgs = ArrayList<LLVMValueRef>()
        commandLineArgsCallArgs.add(commandLineArgs)
        let _ = irBuilder.CreateGetCommandLineArgsCall(commandLineArgsCallArgs)
        userMainArgs.add(irBuilder.CreatePointerCast(commandLineArgs,
            unsafe { LLVMTypeOf(LLVMGetParam(userMain, 0u32)) }))
    }
    let userMainRetVal = irBuilder.CreateCallOrInvoke(userMain, userMainArgs)
    irBuilder.CreateExecAtExitCallbacksCall()
    let _ = irBuilder.CreateRet(GenerateMainRetVal(irBuilder, userMainRetVal, i32Type))
}

private func CreateUnwindBlockForTryCatchWrapper(cgMod: CGModule, irBuilder: IRBuilder2, i32Type: LLVMTypeRef): Unit {
    let landingPad = irBuilder.CreateLandingPad(CGType.GetLandingPadType(cgMod.GetLLVMContext()), 0u32)
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
    let landingPad1 = irBuilder.CreateLandingPad(CGType.GetLandingPadType(cgMod.GetLLVMContext()), 0u32)
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

private func RegisterExceptionRaiser(cgMod: CGModule): Unit {
    if (cgMod.GetCGContext().GetCurrentPkgName() == CORE_PACKAGE_NAME) {
        let moduleHandle = cgMod.GetLLVMModule().getOrThrow()
        let chirPkgInitFunc = cgMod.GetCGContext().GetCHIRPackage().GetPackageInitFunc().getOrThrow()
        let pkgInitFuncName = chirPkgInitFunc.GetIdentifierWithoutPrefix()
        let llvmPkgInitFunc = GetNamedFunction(moduleHandle, pkgInitFuncName)
        let entryBlock = unsafe { LLVMGetEntryBasicBlock(llvmPkgInitFunc) }
        let terminator = unsafe { LLVMGetBasicBlockTerminator(entryBlock) }
        CJC_ASSERT(!terminator.isNull())
        let registerBlock = unsafe { LLVMGetSuccessor(terminator, 1u32) }
        CJC_ASSERT(!registerBlock.isNull())
        let registerTerminator = unsafe { LLVMGetBasicBlockTerminator(registerBlock) }
        try (irBuilder = IRBuilder2(cgMod)) {
            irBuilder.SetInsertPointBefore(registerTerminator)
            let int8PtrType = unsafe { LLVMPointerType(LLVMInt8TypeInContext(cgMod.GetLLVMContext().raw), 0u32) }
            let chirFunc = cgMod.GetCGContext().GetCGPkgContext().FindCHIRGlobalValue(
                "rt$ThrowImplicitException").getOrThrow()
            let rawFunc = cgMod.GetOrInsertCGFunction(chirFunc).GetRawFunction()
            let param = irBuilder.CreateBitCast(rawFunc, int8PtrType)
            let args = ArrayList<LLVMValueRef>()
            args.add(param)
            let _ = irBuilder.CreateIntrinsicCallNoInvoke("llvm.cj.register.implicit.exception.raisers",
                ArrayList<LLVMTypeRef>(), args)
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
        let _ = irBuilder.CreateCallOrInvoke(flagResetFunc, ArrayList<LLVMValueRef>())

        if (let Some(literalInitFunc) <- GetPackageInitSiblingFunction(cgMod, pkgInitFuncName,
            SPECIAL_NAME_FOR_INIT_LITERAL_FUNCTION)) {
            let _ = irBuilder.CreateCallOrInvoke(literalInitFunc, ArrayList<LLVMValueRef>())
        }
        if (let Some(gvInitFunc) <- GetNamedFunctionOpt(cgMod, pkgInitFuncName)) {
            let _ = irBuilder.CreateCallOrInvoke(gvInitFunc, ArrayList<LLVMValueRef>())
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
        let _ = irBuilder.CreateCallOrInvoke(wrapperFunc, wrapperArgs)
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

private func TraverseAndGenerateCallSetFrom(
    ret: HashMap<UIntNative, LLVMSelfhostCallGraphNodeRef>, root: LLVMSelfhostCallGraphNodeRef): Unit {
    let queue = ArrayList<LLVMSelfhostCallGraphNodeRef>()
    queue.add(root)
    var queueIndex: Int64 = 0
    while (queueIndex < queue.size) {
        let node = queue[queueIndex]
        queueIndex++
        let nodeKey = node.toUIntNative()
        if (ret.contains(nodeKey)) {
            continue
        }
        ret[nodeKey] = node
        let calleeCount = unsafe { LLVMSelfhostCallGraphNodeSize(node) }
        var calleeIndex: UInt32 = 0u32
        while (calleeIndex < calleeCount) {
            let calleeNode = unsafe { LLVMSelfhostCallGraphNodeGetCallee(node, calleeIndex) }
            if (!ret.contains(calleeNode.toUIntNative())) {
                queue.add(calleeNode)
            }
            calleeIndex++
        }
    }
}

private func GenerateBinarySectionInfo(cgMod: CGModule): Unit {
    if (cgMod.GetCGContext().GetCGPkgContext().IsCGParallelEnabled()) {
        return
    }
    let moduleHandle = cgMod.GetLLVMModule().getOrThrow()
    let cjInitAttrStr = "cjinit"
    let callGraph = unsafe { LLVMSelfhostCreateCallGraphWrapperPass(moduleHandle.raw) }
    let globalInitFuncName = cgMod.GetCGContext().GetCHIRPackage().GetPackageInitFunc().getOrThrow()
        .GetIdentifierWithoutPrefix()
    let pkgInitFunc = GetNamedFunction(moduleHandle, globalInitFuncName)
    CJC_ASSERT(!pkgInitFunc.isNull())
    let pkgInitNode = unsafe { LLVMSelfhostCallGraphGetNode(callGraph, pkgInitFunc) }
    let callSet = HashMap<UIntNative, LLVMSelfhostCallGraphNodeRef>()
    TraverseAndGenerateCallSetFrom(callSet, pkgInitNode)
    if (unsafe { LLVMSelfhostGlobalObjectHasEmptySection(pkgInitFunc) } != 0) {
        AddFnAttr(pkgInitFunc, cjInitAttrStr)
    }
    let mainFuncs = [CJ_ENTRY_FUNC_NAME, "main"]
    for (functionName in mainFuncs) {
        let functionValue = GetNamedFunction(moduleHandle, functionName)
        if (!functionValue.isNull() && unsafe { LLVMSelfhostGlobalObjectHasEmptySection(functionValue) } != 0) {
            AddFnAttr(functionValue, cjInitAttrStr)
        }
    }
    let userMainFunc = GetNamedFunction(moduleHandle, USER_MAIN_MANGLED_NAME)
    if (!userMainFunc.isNull() && unsafe { LLVMSelfhostGlobalObjectHasEmptySection(userMainFunc) } != 0) {
        AddFnAttr(userMainFunc, cjInitAttrStr)
        let userMainNode = unsafe { LLVMSelfhostCallGraphGetNode(callGraph, userMainFunc) }
        let calleeCount = unsafe { LLVMSelfhostCallGraphNodeSize(userMainNode) }
        var calleeIndex: UInt32 = 0u32
        while (calleeIndex < calleeCount) {
            let calleeNode = unsafe { LLVMSelfhostCallGraphNodeGetCallee(userMainNode, calleeIndex) }
            let calleeFunc = unsafe { LLVMSelfhostCallGraphNodeGetFunction(calleeNode) }
            if (!calleeFunc.isNull() && unsafe { LLVMSelfhostGlobalObjectHasEmptySection(calleeFunc) } != 0) {
                AddFnAttr(calleeFunc, cjInitAttrStr)
            }
            calleeIndex++
        }
    }
    for ((_, node) in callSet) {
        let functionValue = unsafe { LLVMSelfhostCallGraphNodeGetFunction(node) }
        if (functionValue.isNull()) {
            continue
        }
        if (unsafe { LLVMSelfhostGlobalObjectHasEmptySection(functionValue) } != 0) {
            AddFnAttr(functionValue, cjInitAttrStr)
        }
    }
    unsafe { LLVMSelfhostDisposeCallGraphWrapperPass(callGraph) }
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

private func FindUserMainFunction(cgMod: CGModule): Option<Function> {
    if (let Some(value) <- cgMod.GetCGContext().GetCGPkgContext().FindCHIRGlobalValue(USER_MAIN_MANGLED_NAME)) {
        return value as Function
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

private func KeepSomeTypesManually(cgMod: CGModule): Unit {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let llvmContext = cgMod.GetLLVMContext().raw
        let functionType = unsafe {
            LLVMFunctionType(LLVMVoidTypeInContext(llvmContext), CPointer<LLVMTypeRef>(), 0u32, 0)
        }
        let functionValue = GetOrInsertLLVMFunction(moduleHandle, FOR_KEEPING_SOME_TYPES_FUNC_NAME, functionType)
        AddFnAttr(functionValue, "noinline")
        AddFnAttr(functionValue, "optnone")
        AddLinkageTypeMetadata(functionValue, LLVMLinkage.Private, false)
        cgMod.GetCGContext().AddLLVMUsedVars(FOR_KEEPING_SOME_TYPES_FUNC_NAME)
        try (blockName = unsafe { LibC.mallocCString("entry.unreachable") }.asResource(),
            allocaName = unsafe { LibC.mallocCString("") }.asResource()) {
            let builder = unsafe { LLVMCreateBuilderInContext(llvmContext) }
            let entryBlock = unsafe { LLVMAppendBasicBlockInContext(llvmContext, functionValue, blockName.value) }
            unsafe { LLVMPositionBuilderAtEnd(builder, entryBlock) }
            for (structTypeName in cgMod.GetCGContext().GetGeneratedStructType()) {
                try (typeName = unsafe { LibC.mallocCString(structTypeName) }.asResource()) {
                    let structType = unsafe { LLVMGetTypeByName2(llvmContext, typeName.value) }
                    if (!structType.isNull() && unsafe { LLVMTypeIsSized(structType) } != 0) {
                        let _ = unsafe { LLVMBuildAlloca(builder, structType, allocaName.value) }
                    }
                }
            }
            unsafe {
                LLVMBuildRetVoid(builder)
                LLVMDisposeBuilder(builder)
            }
        }
    }
}

private func EmitStaticGenericTIsAndLLVMUsed(cgMod: CGModule): Unit {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let usedValues = ArrayList<LLVMValueRef>()
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
    let typeInfoType = CGType.GetOrCreateTypeInfoType(cgMod.GetLLVMContext())
    let typeInfoPtrType = CGType.GetOrCreateTypeInfoPtrType(cgMod.GetLLVMContext())
    let values = ArrayList<LLVMValueRef>()
    let emittedNames = HashSet<String>()
    let orderedStaticGINames = ArrayList<String>()
    for (typeInfoName in staticGINames) {
        orderedStaticGINames.add(typeInfoName)
    }
    sort(orderedStaticGINames, by: { left: String, right: String => CompareString(left, right) })
    for (typeInfoName in orderedStaticGINames) {
        let staticGI = GetOrInsertCodeGenGlobal(cgMod, typeInfoName, typeInfoType)
        if (ShouldEmitStaticGI(staticGI)) {
            CJC_ASSERT(unsafe { LLVMIsDeclaration(staticGI) } == 0)
            values.add(staticGI)
            emittedNames.add(typeInfoName)
        }
    }
    for (reflectStaticGIName in cgMod.GetCGContext().GetReflectGeneratedStaticGINames()) {
        if (emittedNames.contains(reflectStaticGIName)) {
            continue
        }
        if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            var staticGI = LLVMNullValue()
            try (nameCString = unsafe { LibC.mallocCString(reflectStaticGIName) }.asResource()) {
                staticGI = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameCString.value) }
            }
            if (!staticGI.isNull()) {
                CJC_ASSERT(unsafe { LLVMIsDeclaration(staticGI) } == 0)
                values.add(staticGI)
                emittedNames.add(reflectStaticGIName)
            }
        }
    }
    if (values.isEmpty()) {
        return LLVMNullValue()
    }
    let sortedValues = TopologicalSortStaticGIs(cgMod, values)
    let arrayType = unsafe { LLVMArrayType(typeInfoPtrType, UInt32(values.size)) }
    let table = GetOrInsertCodeGenGlobal(cgMod, "StaticGenericTIs", arrayType)
    unsafe {
        LLVMSetInitializer(table, ConstLLVMArray(typeInfoPtrType, sortedValues))
        LLVMSetLinkage(table, LLVMLinkageValue(LLVMLinkage.Private))
        LLVMSetGlobalConstant(table, 0)
    }
    addAttribute(table, "CFileStaticGenericTI")
    return table
}

private func ShouldEmitStaticGI(staticGI: LLVMValueRef): Bool {
    if (!CGFunction.HasNoUse(staticGI)) {
        return true
    }
    let linkage = unsafe { LLVMGetLinkage(staticGI) }
    return !IsLocalLinkageValue(linkage) && linkage != LLVMLinkageValue(LLVMLinkage.LinkOnceODR)
}

private func IsLocalLinkageValue(linkage: Int32): Bool {
    return linkage == LLVMLinkageValue(LLVMLinkage.Internal) || linkage == LLVMLinkageValue(LLVMLinkage.Private)
}

private func TopologicalSortStaticGIs(cgMod: CGModule, content: ArrayList<LLVMValueRef>): ArrayList<LLVMValueRef> {
    let partialOrder = cgMod.GetCGContext().GetDependentPartialOrderOfTypes()
    let indegrees = ArrayList<Int64>()
    for (_ in content) {
        indegrees.add(0)
    }
    for (pair in partialOrder) {
        let biggerIdx = IndexOfStaticGI(content, pair.bigger)
        if (biggerIdx >= 0) {
            indegrees[biggerIdx] = indegrees[biggerIdx] + 1
        }
    }
    let queue = ArrayList<LLVMValueRef>()
    var contentIdx: Int64 = 0
    while (contentIdx < content.size) {
        if (indegrees[contentIdx] == 0) {
            queue.add(content[contentIdx])
        }
        contentIdx++
    }
    let result = ArrayList<LLVMValueRef>()
    var queueIdx: Int64 = 0
    while (queueIdx < queue.size) {
        let current = queue[queueIdx]
        queueIdx++
        result.add(current)
        var targetIdx: Int64 = 0
        while (targetIdx < content.size) {
            if (HasStaticGIPartialOrder(partialOrder, current, content[targetIdx])) {
                indegrees[targetIdx] = indegrees[targetIdx] - 1
                if (indegrees[targetIdx] == 0) {
                    queue.add(content[targetIdx])
                }
            }
            targetIdx++
        }
    }
    CJC_ASSERT(result.size == content.size)
    return result
}

private func IndexOfStaticGI(content: ArrayList<LLVMValueRef>, value: LLVMValueRef): Int64 {
    var idx: Int64 = 0
    while (idx < content.size) {
        if (content[idx].toUIntNative() == value.toUIntNative()) {
            return idx
        }
        idx++
    }
    return -1
}

private func HasStaticGIPartialOrder(partialOrder: ArrayList<PartialOrderPair>, smaller: LLVMValueRef,
    bigger: LLVMValueRef): Bool {
    for (pair in partialOrder) {
        if (pair.smaller.toUIntNative() == smaller.toUIntNative() &&
            pair.bigger.toUIntNative() == bigger.toUIntNative()) {
            return true
        }
    }
    return false
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
