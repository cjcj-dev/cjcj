package cangjie_compiler::codegen

import cangjie_compiler::basic.SourceManager

let LLVM_MODULE_FLAG_WARNING: Int32 = 1
private let LLVM_DWARF_LANG_CPP14: Int32 = 32
private let LLVM_DWARF_EMISSION_NONE: Int32 = 0
private let LLVM_DWARF_EMISSION_FULL: Int32 = 1
private let LLVM_DWARF_EMISSION_LINE_TABLES_ONLY: Int32 = 2
let DWARF_VERSION: UInt64 = 4u64

public class DIBuilder {
    private let cgMod: CGModule
    private let raw: LLVMDIBuilderRef
    private let enabled: Bool
    private let enableLineInfo: Bool
    private var finalized: Bool = false
    private var defaultFile: LLVMMetadataRef = LLVMNullMetadata()
    private var compileUnit: LLVMMetadataRef = LLVMNullMetadata()
    private var namespaceScope: LLVMMetadataRef = LLVMNullMetadata()

    public init(cgMod: CGModule) {
        this.cgMod = cgMod
        let options = cgMod.GetCGContext().GetCompileOptions()
        enabled = options.enableCompileDebug || options.enableCoverage
        enableLineInfo = options.displayLineInfo
        raw = if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
            unsafe { LLVMCreateDIBuilder(moduleHandle.raw) }
        } else {
            LLVMNullDIBuilder()
        }
    }

    public func CreateCompileUnit(pkgName: String): Unit {
        if (raw.isNull()) {
            return
        }
        var compileUnitName = pkgName
        let options = cgMod.GetCGContext().GetCompileOptions()
        if (options.enableCoverage) {
            if (options.parseTest && !options.compileTestsOnly) {
                compileUnitName += SourceManager.testPkgSuffix
            }
            if (pkgName.contains(".")) {
                compileUnitName += ".pkg"
            }
        }
        defaultFile = CreateFile(pkgName, ".")
        let unitFile = CreateFile(compileUnitName, ".")
        let emissionKind = if (enabled) {
            LLVM_DWARF_EMISSION_FULL
        } else if (enableLineInfo) {
            LLVM_DWARF_EMISSION_LINE_TABLES_ONLY
        } else {
            LLVM_DWARF_EMISSION_NONE
        }
        try (producer = unsafe { LibC.mallocCString("Cangjie Compiler") }.asResource(),
            empty = unsafe { LibC.mallocCString("") }.asResource()) {
            compileUnit = unsafe {
                LLVMDIBuilderCreateCompileUnit(raw, LLVM_DWARF_LANG_CPP14, unitFile, producer.value,
                    UIntNative("Cangjie Compiler".size), 0, empty.value, 0, 0u32, empty.value, 0,
                    emissionKind, 0u32, 0, 0, empty.value, 0, empty.value, 0)
            }
        }
    }

    public func CreateNameSpace(pkgName: String): Unit {
        if (raw.isNull() || compileUnit.isNull()) {
            return
        }
        try (pkgCString = unsafe { LibC.mallocCString(pkgName) }.asResource()) {
            namespaceScope = unsafe {
                LLVMDIBuilderCreateNameSpace(raw, compileUnit, pkgCString.value, UIntNative(pkgName.size), 0)
            }
        }
    }

    public func CreateDILoc(line: UInt32, column: UInt32): LLVMMetadataRef {
        let scope = if (!namespaceScope.isNull()) {
            namespaceScope
        } else {
            compileUnit
        }
        if (scope.isNull()) {
            return LLVMNullMetadata()
        }
        return unsafe {
            LLVMDIBuilderCreateDebugLocation(cgMod.GetLLVMContext().raw, line, column, scope, LLVMNullMetadata())
        }
    }

    public func Finalize(): Unit {
        if (finalized || raw.isNull()) {
            return
        }
        if (enabled || enableLineInfo) {
            unsafe { LLVMDIBuilderFinalize(raw) }
        }
        unsafe { LLVMDisposeDIBuilder(raw) }
        finalized = true
    }

    public func GetDefaultFile(): LLVMMetadataRef { return defaultFile }
    public func GetCompileUnit(): LLVMMetadataRef { return compileUnit }
    public func GetNameSpace(): LLVMMetadataRef { return namespaceScope }

    private func CreateFile(filename: String, directory: String): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (filenameCString = unsafe { LibC.mallocCString(filename) }.asResource(),
            directoryCString = unsafe { LibC.mallocCString(directory) }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreateFile(raw, filenameCString.value, UIntNative(filename.size),
                    directoryCString.value, UIntNative(directory.size))
            }
        }
        return result
    }
}

public func CreateUInt32Metadata(context: LLVMContextHandle, value: UInt64): LLVMMetadataRef {
    let constantValue = unsafe { LLVMConstInt(LLVMInt32TypeInContext(context.raw), value, 0) }
    return unsafe { LLVMValueAsMetadata(constantValue) }
}
