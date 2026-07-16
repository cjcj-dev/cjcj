package cjcj::codegen

import std.collection.*
import cjcj::basic.Errorln
@When[os == "Windows"]
import cjcj::basic.StringConvertor
import cjcj::incremental_compilation.CachedMangleMap
import cjcj::utils.{CJC_ASSERT, FileUtil}

// Mirrors IncrementalGen.cpp:35-42.
private func AllowFunctionBodyBeReplaced(`func`: LLVMValueRef): Bool {
    return GetLLVMValueName(`func`) != FOR_KEEPING_SOME_TYPES_FUNC_NAME
}

// Mirrors IncrementalGen.cpp:44-48.
private func IsFileInitFuncName(funcName: String): Bool {
    return funcName.startsWith(FILE_GV_INIT_PREFIX)
}

// Mirrors IncrementalGen.cpp:88-91.
private func IsGVForExtensionDefs(gv: LLVMValueRef): Bool {
    return HasGlobalVariableAttribute(gv, "InnerTypeExtensions") ||
        HasGlobalVariableAttribute(gv, "OuterTypeExtensions")
}

// Mirrors IncrementalGen.cpp:50-66.
private func CopyGlobalVariableTo(destModule: LLVMModuleHandle, name: String, gv: LLVMValueRef): LLVMValueRef {
    var newGV = GetNamedGlobal(destModule, name)
    if (newGV.isNull()) {
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            newGV = unsafe { LLVMAddGlobal(destModule.raw, LLVMGlobalGetValueType(gv), nameCString.value) }
        }
    }
    unsafe {
        LLVMSetLinkage(newGV, LLVMGetLinkage(gv))
        LLVMSetAlignment(newGV, LLVMGetAlignment(gv))
        LLVMSetUnnamedAddress(newGV, LLVMGetUnnamedAddress(gv))
        LLVMSetGlobalConstant(newGV, LLVMIsGlobalConstant(gv))
        LLVMSetVisibility(newGV, LLVMGetVisibility(gv))
        LLVMSelfhostGlobalVariableCopyAttributes(newGV, gv)
        LLVMSetThreadLocalMode(newGV, LLVMGetThreadLocalMode(gv))
        LLVMSelfhostGlobalVariableCopyAttributesFrom(newGV, gv)
    }
    return newGV
}

// Mirrors IncrementalGen.cpp:68-74.
private func UpdateCompileUnitWith(function: LLVMValueRef, newCU: LLVMMetadataRef): Unit {
    let subprogram = unsafe { LLVMGetSubprogram(function) }
    if (!subprogram.isNull()) {
        unsafe { LLVMSelfhostDISubprogramReplaceUnit(subprogram, newCU) }
    }
}

// Mirrors IncrementalGen.cpp:76-86.
private func DeleteFuncBody(function: LLVMValueRef): Unit {
    CJC_ASSERT(!function.isNull())
    var block = unsafe { LLVMGetFirstBasicBlock(function) }
    while (!block.isNull()) {
        unsafe { LLVMSelfhostBasicBlockDropAllReferences(block) }
        block = unsafe { LLVMGetNextBasicBlock(block) }
    }
    block = unsafe { LLVMGetFirstBasicBlock(function) }
    while (!block.isNull()) {
        let next = unsafe { LLVMGetNextBasicBlock(block) }
        unsafe { LLVMDeleteBasicBlock(block) }
        block = next
    }
    unsafe { LLVMSelfhostGlobalObjectClearMetadata(function) }
}

private func HasGlobalVariableAttribute(gv: LLVMValueRef, name: String): Bool {
    var result = false
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe {
            LLVMSelfhostGlobalVariableHasAttribute(gv, nameCString.value, UInt32(name.size)) != 0
        }
    }
    return result
}

private func GetLLVMValueName(value: LLVMValueRef): String {
    return LLVMCStringToString(unsafe { LLVMGetValueName(value) }) ?? ""
}

private func SetLLVMValueName(value: LLVMValueRef, name: String): Unit {
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        unsafe { LLVMSetValueName2(value, nameCString.value, UIntNative(name.size)) }
    }
}

private func GetNamedFunction(module: LLVMModuleHandle, name: String): LLVMValueRef {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetNamedFunction(module.raw, nameCString.value) }
    }
    return result
}

private func GetNamedGlobal(module: LLVMModuleHandle, name: String): LLVMValueRef {
    var result = LLVMNullValue()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetNamedGlobal(module.raw, nameCString.value) }
    }
    return result
}

private func AddUniqueLLVMValue(values: ArrayList<LLVMValueRef>, value: LLVMValueRef): Unit {
    for (existing in values) {
        if (existing.toUIntNative() == value.toUIntNative()) {
            return
        }
    }
    values.add(value)
}

public class IncrementalGen {
    private let cgParallelEnabled: Bool
    private var incrementalModule: Option<LLVMModuleHandle> = None
    private var injectedModule: Option<LLVMModuleHandle> = None
    private let codegenAddedCachedMap: HashMap<String, HashSet<String>> = HashMap<String, HashSet<String>>()
    private let uselessDefinitions: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()
    private let deferErase: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()
    private let llvmUsedGVNames: ArrayList<String> = ArrayList<String>()
    private let staticGINames: ArrayList<String> = ArrayList<String>()

    public init(cgParallelEnabled: Bool) {
        this.cgParallelEnabled = cgParallelEnabled
    }

    // Mirrors IncrementalGen.cpp:98-118, including the _WIN32 path conversion.
    public func Init(cachedIRPath: String, llvmContext: LLVMContextHandle): Bool {
        if (!FileUtil.FileExist(cachedIRPath)) {
            Errorln("the cached bitcode file is lost.")
            return false
        }
        @When[os == "Windows"]
        let tempPath = StringConvertor.NormalizeStringToUTF8(cachedIRPath)
        @When[os == "Windows"]
        let path = if (let Some(value) <- tempPath) {
            value
        } else {
            CJC_ASSERT(false)
            cachedIRPath
        }
        @When[os != "Windows"]
        let path = cachedIRPath
        let result = LLVMParseIRFile(llvmContext, path)
        if (!result.ok) {
            Errorln("Illegal bitcode cache detected during incremental compilation.")
            return false
        }
        injectedModule = result.module
        return true
    }

    // Mirrors IncrementalGen.cpp:120-131.
    private func InitCodeGenAddedCachedMap(): Unit {
        let module = injectedModule.getOrThrow()
        let metadata = LLVMGetNamedMetadataOperandValues(module, "CodeGenAddedForIncr")
        for (md in metadata) {
            let operands = LLVMGetMDNodeOperands(md)
            if (operands.isEmpty()) {
                continue
            }
            let key = LLVMGetMDStringValue(operands[0]).getOrThrow()
            if (!codegenAddedCachedMap.contains(key)) {
                codegenAddedCachedMap[key] = HashSet<String>()
            }
            var idx: Int64 = 1
            while (idx < operands.size) {
                codegenAddedCachedMap[key].add(LLVMGetMDStringValue(operands[idx]).getOrThrow())
                idx++
            }
        }
    }

    // Mirrors IncrementalGen.cpp:133-136.
    public func GetIncrLLVMUsedNames(): ArrayList<String> {
        return ArrayList<String>(llvmUsedGVNames)
    }

    // Mirrors IncrementalGen.cpp:138-141.
    public func GetIncrCachedStaticGINames(): ArrayList<String> {
        return ArrayList<String>(staticGINames)
    }

    // Mirrors IncrementalGen.cpp:178-226.
    private func UpdateCachedDeclsFromInjectedModule(cachedMangles: CachedMangleMap): Unit {
        let module = injectedModule.getOrThrow()
        for (name in cachedMangles.incrRemovedDecls) {
            let oldF = GetNamedFunction(module, name)
            if (!oldF.isNull()) {
                SetLLVMValueName(oldF, name + "$useless$")
                CollectUselessDefinitions(oldF)
                if (name.startsWith("macroCall_c_") || name.startsWith("macroCall_a_")) {
                    let nameWrapper = name + "$real"
                    let oldFWrapper = GetNamedFunction(module, nameWrapper)
                    SetLLVMValueName(oldFWrapper, nameWrapper + "$useless$")
                    CollectUselessDefinitions(oldFWrapper)
                }
            } else {
                let oldV = GetNamedGlobal(module, name)
                if (!oldV.isNull()) {
                    SetLLVMValueName(oldV, name + "$useless$")
                    CollectUselessDefinitions(oldV)
                }
            }

            if (codegenAddedCachedMap.contains(name)) {
                for (codegenAddedName in codegenAddedCachedMap[name]) {
                    let old = GetNamedGlobal(module, codegenAddedName)
                    if (!old.isNull()) {
                        SetLLVMValueName(old, name + "$useless$")
                        CollectUselessDefinitions(old)
                    }
                }
                codegenAddedCachedMap.remove(name)
            }
        }

        for (name in cachedMangles.newExternalDecls) {
            let oldF = GetNamedFunction(module, name)
            if (!oldF.isNull()) {
                AddLinkageTypeMetadata(oldF, LLVMLinkage.External, cgParallelEnabled)
            } else {
                let oldV = GetNamedGlobal(module, name)
                if (!oldV.isNull()) {
                    AddLinkageTypeMetadata(oldV, LLVMLinkage.External, cgParallelEnabled)
                }
            }
        }

        for (name in cachedMangles.importedInlineDecls) {
            let oldF = GetNamedFunction(module, name)
            if (!oldF.isNull()) {
                DeleteFuncBody(oldF)
                AddLinkageTypeMetadata(oldF, LLVMLinkage.External, cgParallelEnabled)
                unsafe {
                    LLVMSelfhostGlobalValueSetDSOLocal(oldF, 0)
                    LLVMSetPersonalityFn(oldF, LLVMNullValue())
                }
            } else {
                let oldV = GetNamedGlobal(module, name)
                if (!oldV.isNull()) {
                    AddLinkageTypeMetadata(oldV, LLVMLinkage.External, cgParallelEnabled)
                    unsafe {
                        LLVMSetInitializer(oldV, LLVMNullValue())
                        LLVMSelfhostGlobalValueSetDSOLocal(oldV, 0)
                    }
                }
            }
        }
    }

    // Mirrors IncrementalGen.cpp:228-273.
    private func CopyDeclarationsToInjectedModule(): Unit {
        let incremental = incrementalModule.getOrThrow()
        let injected = injectedModule.getOrThrow()
        var gv = unsafe { LLVMGetFirstGlobal(incremental.raw) }
        while (!gv.isNull()) {
            let nextGV = unsafe { LLVMGetNextGlobal(gv) }
            let gvName = GetLLVMValueName(gv)
            if (IsGVForExtensionDefs(gv)) {
                var idx: Int64 = 0
                var found = GetNamedGlobal(injected, gvName + idx.toString())
                while (!found.isNull()) {
                    idx++
                    found = GetNamedGlobal(injected, gvName + idx.toString())
                }
                try (nameCString = unsafe { LibC.mallocCString(gvName + idx.toString()) }.asResource()) {
                    found = unsafe { LLVMAddGlobal(injected.raw, LLVMGlobalGetValueType(gv), nameCString.value) }
                }
                SetLLVMValueName(gv, GetLLVMValueName(found))
                let _ = CopyGlobalVariableTo(injected, GetLLVMValueName(found), gv)
                gv = nextGV
                continue
            }
            var injectedGv = GetNamedGlobal(injected, gvName)
            if (!injectedGv.isNull() &&
                (unsafe { LLVMTypeOf(injectedGv) }.toUIntNative() !=
                    unsafe { LLVMTypeOf(gv) }.toUIntNative() ||
                (unsafe { LLVMIsGlobalConstant(injectedGv) } != unsafe { LLVMIsGlobalConstant(gv) } &&
                unsafe { LLVMIsDeclaration(gv) } == 0))) {
                SetLLVMValueName(injectedGv, gvName + "$useless$")
                injectedGv = LLVMNullValue()
            }
            if (injectedGv.isNull()) {
                let _ = CopyGlobalVariableTo(injected, gvName, gv)
            }
            gv = nextGV
        }

        var function = unsafe { LLVMGetFirstFunction(incremental.raw) }
        while (!function.isNull()) {
            let funcName = GetLLVMValueName(function)
            var injectedFunc = GetNamedFunction(injected, funcName)
            if (!injectedFunc.isNull() &&
                unsafe { LLVMGlobalGetValueType(injectedFunc) }.toUIntNative() !=
                    unsafe { LLVMGlobalGetValueType(function) }.toUIntNative()) {
                SetLLVMValueName(injectedFunc, funcName + "$useless$")
                CollectUselessDefinitions(injectedFunc)
                injectedFunc = LLVMNullValue()
            }
            if (injectedFunc.isNull()) {
                try (nameCString = unsafe { LibC.mallocCString(funcName) }.asResource()) {
                    injectedFunc = unsafe {
                        LLVMSelfhostFunctionCreateWithAddressSpace(LLVMGlobalGetValueType(function),
                            UInt32(LLVMGetLinkage(function)), LLVMSelfhostFunctionGetAddressSpace(function),
                            nameCString.value, UInt32(funcName.size), injected.raw)
                    }
                }
                unsafe { LLVMSelfhostFunctionCopyAttributesFrom(injectedFunc, function) }
            }
            function = unsafe { LLVMGetNextFunction(function) }
        }
    }

    // Mirrors IncrementalGen.cpp:275-296.
    private func FillValueMap(valueMap: LLVMSelfhostValueToValueMapRef): Unit {
        let incremental = incrementalModule.getOrThrow()
        let injected = injectedModule.getOrThrow()
        var function = unsafe { LLVMGetFirstFunction(incremental.raw) }
        while (!function.isNull()) {
            let oldFunction = GetNamedFunction(injected, GetLLVMValueName(function))
            if (!oldFunction.isNull()) {
                unsafe { LLVMSelfhostValueToValueMapSet(valueMap, function, oldFunction) }
                let paramCount = unsafe { LLVMCountParams(function) }
                if (unsafe { LLVMCountParams(oldFunction) } == paramCount) {
                    var idx: UInt32 = 0u32
                    while (idx < paramCount) {
                        let source = unsafe { LLVMGetParam(function, idx) }
                        let dest = unsafe { LLVMGetParam(oldFunction, idx) }
                        SetLLVMValueName(dest, GetLLVMValueName(source))
                        unsafe { LLVMSelfhostValueToValueMapSet(valueMap, source, dest) }
                        idx++
                    }
                }
            }
            function = unsafe { LLVMGetNextFunction(function) }
        }
        var gv = unsafe { LLVMGetFirstGlobal(incremental.raw) }
        while (!gv.isNull()) {
            let existed = GetNamedGlobal(injected, GetLLVMValueName(gv))
            if (!existed.isNull()) {
                unsafe { LLVMSelfhostValueToValueMapSet(valueMap, gv, existed) }
            }
            gv = unsafe { LLVMGetNextGlobal(gv) }
        }
    }

    // Mirrors IncrementalGen.cpp:298-335.
    private func UpdateInitializationsOfGlobalVariables(valueMap: LLVMSelfhostValueToValueMapRef): Unit {
        let incremental = incrementalModule.getOrThrow()
        let injected = injectedModule.getOrThrow()
        let compileUnit = unsafe { LLVMSelfhostModuleGetFirstDICompileUnit(injected.raw) }
        let currentGlobalVars = unsafe { LLVMSelfhostDICompileUnitGetGlobalVariables(compileUnit) }
        let newGlobalVars = unsafe { LLVMSelfhostCreateTempGlobalsTuple(injected.raw, currentGlobalVars) }
        let context = LLVMContextHandle(unsafe { LLVMGetModuleContext(injected.raw) }, owned: false)
        let debugKind = LLVMGetMDKindID(context, "dbg")
        var gv = unsafe { LLVMGetFirstGlobal(incremental.raw) }
        while (!gv.isNull()) {
            let nextGV = unsafe { LLVMGetNextGlobal(gv) }
            if (HasGlobalVariableAttribute(gv, "nonRecompile")) {
                try (nameCString = unsafe { LibC.mallocCString("nonRecompile") }.asResource()) {
                    unsafe { LLVMSelfhostGlobalVariableRemoveAttribute(gv, nameCString.value,
                        UInt32("nonRecompile".size)) }
                }
                gv = nextGV
                continue
            }
            let gvToBeUpdated = GetNamedGlobal(injected, GetLLVMValueName(gv))
            CJC_ASSERT(!gvToBeUpdated.isNull())
            if (IsGVForExtensionDefs(gv)) {
                unsafe { LLVMSetInitializer(gvToBeUpdated,
                    LLVMSelfhostMapValue(LLVMGetInitializer(gv), valueMap)) }
                gv = nextGV
                continue
            }
            unsafe { LLVMSelfhostGlobalObjectClearMetadata(gvToBeUpdated) }
            try (countPtr = LibC.malloc<UIntNative>().asResource()) {
                unsafe { countPtr.value.write(UIntNative(0)) }
                let entries = unsafe { LLVMGlobalCopyAllMetadata(gv, countPtr.value) }
                let count = unsafe { countPtr.value.read() }
                if (!entries.isNull()) {
                    var idx: UInt32 = 0u32
                    while (idx < UInt32(count)) {
                        let kind = unsafe { LLVMValueMetadataEntriesGetKind(entries, idx) }
                        let sourceMetadata = unsafe { LLVMValueMetadataEntriesGetMetadata(entries, idx) }
                        let mappedMetadata = unsafe { LLVMSelfhostMapMetadata(sourceMetadata, valueMap) }
                        unsafe { LLVMGlobalSetMetadata(gvToBeUpdated, kind, mappedMetadata) }
                        if (kind == debugKind) {
                            unsafe { LLVMSelfhostTempTuplePushBack(newGlobalVars, mappedMetadata) }
                        }
                        idx++
                    }
                    unsafe { LLVMDisposeValueMetadataEntries(entries) }
                }
            }
            if (unsafe { LLVMIsDeclaration(gv) } == 0) {
                unsafe {
                    LLVMSetInitializer(gvToBeUpdated, LLVMSelfhostMapValue(LLVMGetInitializer(gv), valueMap))
                    LLVMSetLinkage(gvToBeUpdated, LLVMGetLinkage(gv))
                }
            }
            gv = nextGV
        }
        let permanentNode = unsafe { LLVMSelfhostTempTupleReplaceWithPermanent(newGlobalVars) }
        unsafe { LLVMSelfhostDICompileUnitReplaceGlobalVariables(compileUnit, permanentNode) }
    }

    // Mirrors IncrementalGen.cpp:337-358.
    private func UpdateDefinitionsOfFunction(valueMap: LLVMSelfhostValueToValueMapRef): Unit {
        let incremental = incrementalModule.getOrThrow()
        let injected = injectedModule.getOrThrow()
        var function = unsafe { LLVMGetFirstFunction(incremental.raw) }
        while (!function.isNull()) {
            if (unsafe { LLVMIsDeclaration(function) } != 0 || !AllowFunctionBodyBeReplaced(function)) {
                function = unsafe { LLVMGetNextFunction(function) }
                continue
            }
            let funcToBeUpdated = GetNamedFunction(injected, GetLLVMValueName(function))
            DeleteFuncBody(funcToBeUpdated)
            unsafe {
                LLVMSelfhostCloneFunctionInto(funcToBeUpdated, function, valueMap)
                LLVMSetLinkage(funcToBeUpdated, LLVMGetLinkage(function))
            }
            UpdateCompileUnitWith(funcToBeUpdated,
                unsafe { LLVMSelfhostModuleGetFirstDICompileUnit(injected.raw) })
            function = unsafe { LLVMGetNextFunction(function) }
        }
    }

    // Mirrors IncrementalGen.cpp:360-366.
    private func UpdateBodyOfKeepTypesFunction(valueMap: LLVMSelfhostValueToValueMapRef): Unit {
        let incremental = incrementalModule.getOrThrow()
        let injected = injectedModule.getOrThrow()
        let sourceFunction = GetNamedFunction(incremental, FOR_KEEPING_SOME_TYPES_FUNC_NAME)
        let targetFunction = GetNamedFunction(injected, FOR_KEEPING_SOME_TYPES_FUNC_NAME)
        var block = unsafe { LLVMGetFirstBasicBlock(sourceFunction) }
        while (!block.isNull()) {
            unsafe { let _ = LLVMSelfhostCloneBasicBlock(block, valueMap, targetFunction) }
            block = unsafe { LLVMGetNextBasicBlock(block) }
        }
    }

    // Mirrors IncrementalGen.cpp:368-374.
    private func CollectUselessDefinitions(uselessDefinition: LLVMValueRef): Unit {
        if (uselessDefinition.isNull()) {
            return
        }
        AddUniqueLLVMValue(uselessDefinitions, uselessDefinition)
    }

    // Mirrors IncrementalGen.cpp:550-558.
    private func UpdateIncrLLVMUsedNames(): Unit {
        let module = injectedModule.getOrThrow()
        for (name in ["ExternalExtensionDefs", "NonExternalExtensionDefs"]) {
            if (!GetNamedGlobal(module, name).isNull()) {
                llvmUsedGVNames.add(name)
            }
        }
    }
}
