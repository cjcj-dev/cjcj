package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.FuncKind
import cangjie_compiler::chir.Function
import cangjie_compiler::option.GlobalOptions

private let CANGJIE_SDK_VERSION: String = "1.1.0-alpha.20260331010029"

public func GenPackageModules(chirData: CHIRData, options: GlobalOptions, enableIncrement: Bool,
    cachedMangleMap!: CachedMangleMap = CachedMangleMap()): ArrayList<LLVMModuleHandle> {
    let cgPkgContext = CGPkgContext(chirData, options, enableIncrement, cachedMangleMap)
    let splitter = CHIRSplitter(cgPkgContext)
    for (subPackage in splitter.SplitCHIRPackage()) {
        let cgMod = CGModule(subPackage, cgPkgContext)
        cgPkgContext.AddCGModule(cgMod)
        for (globalVar in subPackage.chirGVs) {
            EmitGlobalVariableIR(cgMod, globalVar)
        }
        for (chirFunc in subPackage.chirFuncs) {
            EmitFunctionIR(cgMod, chirFunc)
        }
        if (subPackage.mainModule) {
            EmitCJSDKVersion(cgMod)
            EmitMainFunctionIR(cgMod)
        }
        InitializeCjStringLiteral(cgMod)
        cgMod.EraseUselessInstsAndDeclarations()
        cgMod.Opt()
    }
    return cgPkgContext.ReleaseLLVMModules()
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

private func CreateCJEntryFunction(cgMod: CGModule, moduleHandle: LLVMModuleHandle, llvmContext: LLVMContextRef,
    i32Type: LLVMTypeRef): LLVMValueRef {
    let entryType = unsafe { LLVMFunctionType(i32Type, CPointer<LLVMTypeRef>(), 0u32, 0) }
    let entryFunc = GetOrInsertLLVMFunction(moduleHandle, CJ_ENTRY_FUNC_NAME, entryType)
    SetCangjieGC(entryFunc)
    let zero = unsafe { LLVMConstInt(i32Type, 0u64, 0) }
    try (blockName = unsafe { LibC.mallocCString("entry") }.asResource(),
        callName = unsafe { LibC.mallocCString("") }.asResource()) {
        let builder = unsafe { LLVMCreateBuilderInContext(llvmContext) }
        let entryBlock = unsafe { LLVMAppendBasicBlockInContext(llvmContext, entryFunc, blockName.value) }
        unsafe {
            LLVMPositionBuilderAtEnd(builder, entryBlock)
        }
        // Default exit status is 0. A `main(): Int64` returns its value; a `main(): Unit` returns 0.
        var exitCode = zero
        if (let Some(mainEntry) <- FindMainEntryFunction(cgMod)) {
            let cgMain = cgMod.GetOrInsertCGFunction(mainEntry)
            if (let Some(mainFnType) <- cgMain.GetCGFunctionType()) {
                let llvmMainType = mainFnType.GetLLVMFunctionType()
                let callArgs = ArrayList<LLVMValueRef>()
                if (cgMain.IsSRet()) {
                    if (let Some(retTy) <- mainEntry.GetReturnType()) {
                        let retCGType = CGType.GetOrCreate(cgMod, retTy)
                        try (sretName = unsafe { LibC.mallocCString("main.sret") }.asResource()) {
                            callArgs.add(unsafe { LLVMBuildAlloca(builder, retCGType.GetLLVMType(), sretName.value) })
                        }
                    }
                }
                var callResult = LLVMNullValue()
                if (callArgs.isEmpty()) {
                    callResult = unsafe {
                        LLVMBuildCall2(builder, llvmMainType, cgMain.GetRawFunction(), CPointer<LLVMValueRef>(),
                            0u32, callName.value)
                    }
                } else {
                    try (argPtr = LibC.malloc<LLVMValueRef>(count: callArgs.size).asResource()) {
                        var idx: Int64 = 0
                        while (idx < callArgs.size) {
                            unsafe { (argPtr.value + idx).write(callArgs[idx]) }
                            idx++
                        }
                        callResult = unsafe {
                            LLVMBuildCall2(builder, llvmMainType, cgMain.GetRawFunction(), argPtr.value,
                                UInt32(callArgs.size), callName.value)
                        }
                    }
                }
                let mainRetType = unsafe { LLVMGetReturnType(llvmMainType) }
                // LLVMIntegerTypeKind == 8: an integer-returning main (e.g. `main(): Int64`)
                // supplies the process exit code, narrowed to the i32 entry result.
                if (unsafe { LLVMGetTypeKind(mainRetType) } == 8) {
                    let width = unsafe { LLVMGetIntTypeWidth(mainRetType) }
                    if (width > 32u32) {
                        exitCode = unsafe { LLVMBuildTrunc(builder, callResult, i32Type, callName.value) }
                    } else if (width < 32u32) {
                        exitCode = unsafe { LLVMBuildZExt(builder, callResult, i32Type, callName.value) }
                    } else {
                        exitCode = callResult
                    }
                }
            }
        }
        unsafe {
            LLVMBuildRet(builder, exitCode)
            LLVMDisposeBuilder(builder)
        }
    }
    return entryFunc
}

private func FindMainEntryFunction(cgMod: CGModule): Option<Function> {
    for (chirFunc in cgMod.GetCGContext().GetSubCHIRPackage().chirFuncs) {
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
