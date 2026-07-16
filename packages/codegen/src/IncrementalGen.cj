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
