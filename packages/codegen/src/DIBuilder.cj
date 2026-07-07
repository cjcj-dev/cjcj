package cangjie_compiler::codegen

import cangjie_compiler::basic.SourceManager

let LLVM_MODULE_FLAG_WARNING: Int32 = 1
private let LLVM_DWARF_LANG_CPP14: Int32 = 32
private let LLVM_DWARF_EMISSION_NONE: Int32 = 0
private let LLVM_DWARF_EMISSION_FULL: Int32 = 1
private let LLVM_DWARF_EMISSION_LINE_TABLES_ONLY: Int32 = 2
private let DW_ATE_signed: UInt32 = 5u32
private let FlagZero: UInt32 = 0u32
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
    private var refDIType: LLVMMetadataRef = LLVMNullMetadata()

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

    private func createBasicType(name: String, sizeInBits: UInt64, encoding: UInt32): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreateBasicType(raw, nameCString.value, UIntNative(name.size), sizeInBits, encoding,
                    FlagZero)
            }
        }
        return result
    }

    private func CreateRefType(): LLVMMetadataRef {
        if (refDIType.isNull()) {
            let basicType = createBasicType("Int64", 64u64, DW_ATE_signed)
            refDIType = CreatePointerType(basicType)
        }
        return refDIType
    }

    private func CreatePointerType(diType: LLVMMetadataRef, sizeInBits!: UInt64 = 64u64): LLVMMetadataRef {
        return createPointerType(diType, sizeInBits: sizeInBits)
    }

    private func createPointerType(diType: LLVMMetadataRef, sizeInBits!: UInt64 = 64u64): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString("") }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreatePointerType(raw, diType, sizeInBits, 0u32, 0u32, nameCString.value, 0)
            }
        }
        return result
    }

    private func createNullPtrType(): LLVMMetadataRef {
        return unsafe { LLVMDIBuilderCreateNullPtrType(raw) }
    }

    private func createMemberType(scope: LLVMMetadataRef, name: String, file: LLVMMetadataRef, lineNo: UInt32,
        sizeInBits: UInt64, alignInBits: UInt32, offsetInBits: UInt64, flags: UInt32,
        diType: LLVMMetadataRef): LLVMMetadataRef {
        var result = LLVMNullMetadata()
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            result = unsafe {
                LLVMDIBuilderCreateMemberType(raw, scope, nameCString.value, UIntNative(name.size), file, lineNo,
                    sizeInBits, alignInBits, offsetInBits, flags, diType)
            }
        }
        return result
    }

    private func CreateTypeInfoMember(fwdDecl: LLVMMetadataRef, diFile: LLVMMetadataRef): LLVMMetadataRef {
        return createMemberType(fwdDecl, "$ti", diFile, 0u32, 64u64, 0u32, 0u64, FlagZero,
            CreateRefType())
    }
}

public func CreateUInt32Metadata(context: LLVMContextHandle, value: UInt64): LLVMMetadataRef {
    let constantValue = unsafe { LLVMConstInt(LLVMInt32TypeInContext(context.raw), value, 0) }
    return unsafe { LLVMValueAsMetadata(constantValue) }
}
