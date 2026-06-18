package cangjie_compiler::codegen

public type LLVMTargetDataRef = CPointer<Unit>
public type LLVMTargetLibraryInfoRef = CPointer<Unit>
public type LLVMTargetRef = CPointer<Unit>
public type LLVMTargetMachineOptionsRef = CPointer<Unit>
public type LLVMTargetMachineRef = CPointer<Unit>
public type LLVMPassManagerRef = CPointer<Unit>

public enum LLVMCodeGenOptLevel {
    | CodeGenLevelNone | CodeGenLevelLess | CodeGenLevelDefault | CodeGenLevelAggressive
}

public enum LLVMRelocMode {
    | RelocDefault | RelocStatic | RelocPIC | RelocDynamicNoPic | RelocROPI | RelocRWPI | RelocROPI_RWPI
}

public enum LLVMCodeModel {
    | CodeModelDefault | CodeModelJITDefault | CodeModelTiny | CodeModelSmall | CodeModelKernel | CodeModelMedium
    | CodeModelLarge
}

public enum LLVMCodeGenFileType {
    | AssemblyFile | ObjectFile
}

public enum LLVMGlobalISelAbortMode {
    | GlobalISelAbortEnable | GlobalISelAbortDisable | GlobalISelAbortDisableWithDiag
}

public func LLVMCodeGenOptLevelValue(level: LLVMCodeGenOptLevel): Int32 {
    return match (level) {
        case LLVMCodeGenOptLevel.CodeGenLevelNone => 0
        case LLVMCodeGenOptLevel.CodeGenLevelLess => 1
        case LLVMCodeGenOptLevel.CodeGenLevelDefault => 2
        case LLVMCodeGenOptLevel.CodeGenLevelAggressive => 3
    }
}

public func LLVMRelocModeValue(mode: LLVMRelocMode): Int32 {
    return match (mode) {
        case LLVMRelocMode.RelocDefault => 0
        case LLVMRelocMode.RelocStatic => 1
        case LLVMRelocMode.RelocPIC => 2
        case LLVMRelocMode.RelocDynamicNoPic => 3
        case LLVMRelocMode.RelocROPI => 4
        case LLVMRelocMode.RelocRWPI => 5
        case LLVMRelocMode.RelocROPI_RWPI => 6
    }
}

public func LLVMCodeModelValue(model: LLVMCodeModel): Int32 {
    return match (model) {
        case LLVMCodeModel.CodeModelDefault => 0
        case LLVMCodeModel.CodeModelJITDefault => 1
        case LLVMCodeModel.CodeModelTiny => 2
        case LLVMCodeModel.CodeModelSmall => 3
        case LLVMCodeModel.CodeModelKernel => 4
        case LLVMCodeModel.CodeModelMedium => 5
        case LLVMCodeModel.CodeModelLarge => 6
    }
}

public func LLVMCodeGenFileTypeValue(fileType: LLVMCodeGenFileType): Int32 {
    return match (fileType) {
        case LLVMCodeGenFileType.AssemblyFile => 0
        case LLVMCodeGenFileType.ObjectFile => 1
    }
}

public func LLVMGlobalISelAbortModeValue(mode: LLVMGlobalISelAbortMode): Int32 {
    return match (mode) {
        case LLVMGlobalISelAbortMode.GlobalISelAbortEnable => 0
        case LLVMGlobalISelAbortMode.GlobalISelAbortDisable => 1
        case LLVMGlobalISelAbortMode.GlobalISelAbortDisableWithDiag => 2
    }
}

foreign {
    func LLVMGetFirstTarget(): LLVMTargetRef
    func LLVMGetNextTarget(target: LLVMTargetRef): LLVMTargetRef
    func LLVMGetTargetFromName(name: CString): LLVMTargetRef
    func LLVMGetTargetFromTriple(triple: CString, outTarget: CPointer<LLVMTargetRef>,
        outMessage: CPointer<CString>): Int32
    func LLVMGetTargetName(target: LLVMTargetRef): CString
    func LLVMGetTargetDescription(target: LLVMTargetRef): CString
    func LLVMTargetHasJIT(target: LLVMTargetRef): Int32
    func LLVMTargetHasTargetMachine(target: LLVMTargetRef): Int32
    func LLVMTargetHasAsmBackend(target: LLVMTargetRef): Int32

    func LLVMCreateTargetMachine(target: LLVMTargetRef, triple: CString, cpu: CString, features: CString,
        level: Int32, reloc: Int32, codeModel: Int32): LLVMTargetMachineRef
    func LLVMDisposeTargetMachine(targetMachine: LLVMTargetMachineRef): Unit
    func LLVMGetTargetMachineTarget(targetMachine: LLVMTargetMachineRef): LLVMTargetRef
    func LLVMGetTargetMachineTriple(targetMachine: LLVMTargetMachineRef): CString
    func LLVMGetTargetMachineCPU(targetMachine: LLVMTargetMachineRef): CString
    func LLVMGetTargetMachineFeatureString(targetMachine: LLVMTargetMachineRef): CString
    func LLVMCreateTargetDataLayout(targetMachine: LLVMTargetMachineRef): LLVMTargetDataRef
    func LLVMSetTargetMachineAsmVerbosity(targetMachine: LLVMTargetMachineRef, verboseAsm: Int32): Unit
    func LLVMSetTargetMachineFastISel(targetMachine: LLVMTargetMachineRef, enable: Int32): Unit
    func LLVMSetTargetMachineGlobalISel(targetMachine: LLVMTargetMachineRef, enable: Int32): Unit
    func LLVMSetTargetMachineGlobalISelAbort(targetMachine: LLVMTargetMachineRef, mode: Int32): Unit
    func LLVMSetTargetMachineMachineOutliner(targetMachine: LLVMTargetMachineRef, enable: Int32): Unit
    func LLVMTargetMachineEmitToFile(targetMachine: LLVMTargetMachineRef, module: LLVMModuleRef, filename: CString,
        codegen: Int32, outMessage: CPointer<CString>): Int32
    func LLVMTargetMachineEmitToMemoryBuffer(targetMachine: LLVMTargetMachineRef, module: LLVMModuleRef,
        codegen: Int32, outMessage: CPointer<CString>, outMemBuf: CPointer<LLVMMemoryBufferRef>): Int32
    func LLVMGetDefaultTargetTriple(): CString
    func LLVMNormalizeTargetTriple(triple: CString): CString
    func LLVMGetHostCPUName(): CString
    func LLVMGetHostCPUFeatures(): CString
    func LLVMAddAnalysisPasses(targetMachine: LLVMTargetMachineRef, passManager: LLVMPassManagerRef): Unit

    func LLVMGetModuleDataLayout(module: LLVMModuleRef): LLVMTargetDataRef
    func LLVMSetModuleDataLayout(module: LLVMModuleRef, dataLayout: LLVMTargetDataRef): Unit
    func LLVMCreateTargetData(stringRep: CString): LLVMTargetDataRef
    func LLVMDisposeTargetData(targetData: LLVMTargetDataRef): Unit
    func LLVMCopyStringRepOfTargetData(targetData: LLVMTargetDataRef): CString
    func LLVMByteOrder(targetData: LLVMTargetDataRef): Int32
    func LLVMPointerSize(targetData: LLVMTargetDataRef): UInt32
    func LLVMPointerSizeForAS(targetData: LLVMTargetDataRef, addressSpace: UInt32): UInt32
    func LLVMIntPtrType(targetData: LLVMTargetDataRef): LLVMTypeRef
    func LLVMIntPtrTypeForAS(targetData: LLVMTargetDataRef, addressSpace: UInt32): LLVMTypeRef
    func LLVMIntPtrTypeInContext(context: LLVMContextRef, targetData: LLVMTargetDataRef): LLVMTypeRef
    func LLVMIntPtrTypeForASInContext(context: LLVMContextRef, targetData: LLVMTargetDataRef,
        addressSpace: UInt32): LLVMTypeRef
    func LLVMSizeOfTypeInBits(targetData: LLVMTargetDataRef, valueType: LLVMTypeRef): UInt64
    func LLVMStoreSizeOfType(targetData: LLVMTargetDataRef, valueType: LLVMTypeRef): UInt64
    func LLVMABISizeOfType(targetData: LLVMTargetDataRef, valueType: LLVMTypeRef): UInt64
    func LLVMABIAlignmentOfType(targetData: LLVMTargetDataRef, valueType: LLVMTypeRef): UInt32
    func LLVMCallFrameAlignmentOfType(targetData: LLVMTargetDataRef, valueType: LLVMTypeRef): UInt32
    func LLVMPreferredAlignmentOfType(targetData: LLVMTargetDataRef, valueType: LLVMTypeRef): UInt32
    func LLVMPreferredAlignmentOfGlobal(targetData: LLVMTargetDataRef, globalVar: LLVMValueRef): UInt32
    func LLVMElementAtOffset(targetData: LLVMTargetDataRef, structTy: LLVMTypeRef, offset: UInt64): UInt32
    func LLVMOffsetOfElement(targetData: LLVMTargetDataRef, structTy: LLVMTypeRef, element: UInt32): UInt64
}

public func LLVMNullTargetMachine(): LLVMTargetMachineRef { return CPointer<Unit>() }
public func LLVMNullTarget(): LLVMTargetRef { return CPointer<Unit>() }
public func LLVMNullTargetData(): LLVMTargetDataRef { return CPointer<Unit>() }
public func LLVMNullTargetMachineOptions(): LLVMTargetMachineOptionsRef { return CPointer<Unit>() }

public func LLVMGetDefaultTargetTripleString(): String {
    return LLVMConsumeMessage(unsafe { LLVMGetDefaultTargetTriple() })
}

public func LLVMNormalizeTargetTripleString(triple: String): String {
    var result = ""
    try (tripleCString = unsafe { LibC.mallocCString(triple) }.asResource()) {
        result = LLVMConsumeMessage(unsafe { LLVMNormalizeTargetTriple(tripleCString.value) })
    }
    return result
}

public class LLVMTargetLookupResult {
    public let ok: Bool
    public let target: LLVMTargetRef
    public let message: String

    public init(target: LLVMTargetRef) {
        ok = true
        this.target = target
        message = ""
    }

    public init(message: String) {
        ok = false
        target = LLVMNullTarget()
        this.message = message
    }
}

public class LLVMTargetEmissionResult {
    public let ok: Bool
    public let message: String
    public let buffer: Option<LLVMMemoryBufferHandle>

    public init(ok: Bool, message: String, buffer: Option<LLVMMemoryBufferHandle>) {
        this.ok = ok
        this.message = message
        this.buffer = buffer
    }

    public static func Success(): LLVMTargetEmissionResult {
        return LLVMTargetEmissionResult(true, "", None)
    }

    public static func Success(buffer: LLVMMemoryBufferHandle): LLVMTargetEmissionResult {
        return LLVMTargetEmissionResult(true, "", Some(buffer))
    }

    public static func Failure(message: String): LLVMTargetEmissionResult {
        return LLVMTargetEmissionResult(false, message, None)
    }
}

public func LLVMGetTargetFromTripleChecked(triple: String): LLVMTargetLookupResult {
    var result = LLVMTargetLookupResult("failed to get LLVM target for triple: " + triple)
    try (tripleCString = unsafe { LibC.mallocCString(triple) }.asResource(),
        outTarget = LibC.malloc<LLVMTargetRef>().asResource(),
        outMessage = LibC.malloc<CString>().asResource()) {
        unsafe { outTarget.value.write(LLVMNullTarget()) }
        unsafe { outMessage.value.write(CString(CPointer<UInt8>())) }
        let status = unsafe { LLVMGetTargetFromTriple(tripleCString.value, outTarget.value, outMessage.value) }
        if (status == 0) {
            result = LLVMTargetLookupResult(unsafe { outTarget.value.read() })
        } else {
            let message = LLVMConsumeMessage(unsafe { outMessage.value.read() })
            if (!message.isEmpty()) {
                result = LLVMTargetLookupResult(message)
            }
        }
    }
    return result
}


public class LLVMTargetMachineHandle <: Resource {
    public let raw: LLVMTargetMachineRef
    private var closed: Bool = false

    public init(raw: LLVMTargetMachineRef) {
        this.raw = raw
    }

    public func GetTarget(): LLVMTargetRef {
        if (raw.isNull()) {
            return LLVMNullTarget()
        }
        return unsafe { LLVMGetTargetMachineTarget(raw) }
    }

    public func GetTriple(): String {
        if (raw.isNull()) {
            return ""
        }
        return LLVMConsumeMessage(unsafe { LLVMGetTargetMachineTriple(raw) })
    }

    public func GetCPU(): String {
        if (raw.isNull()) {
            return ""
        }
        return LLVMConsumeMessage(unsafe { LLVMGetTargetMachineCPU(raw) })
    }

    public func GetFeatureString(): String {
        if (raw.isNull()) {
            return ""
        }
        return LLVMConsumeMessage(unsafe { LLVMGetTargetMachineFeatureString(raw) })
    }

    public func CreateDataLayout(): Option<LLVMTargetDataHandle> {
        if (raw.isNull()) {
            return None
        }
        let targetData = unsafe { LLVMCreateTargetDataLayout(raw) }
        if (targetData.isNull()) {
            return None
        }
        return LLVMTargetDataHandle(targetData)
    }

    public func SetAsmVerbosity(verboseAsm: Bool): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMSetTargetMachineAsmVerbosity(raw, if (verboseAsm) { 1 } else { 0 }) }
        }
    }

    public func SetFastISel(enable: Bool): Unit {
        if (!raw.isNull()) {
            let _ = enable
        }
    }

    public func SetGlobalISel(enable: Bool): Unit {
        if (!raw.isNull()) {
            let _ = enable
        }
    }

    public func SetGlobalISelAbort(mode: LLVMGlobalISelAbortMode): Unit {
        if (!raw.isNull()) {
            let _ = mode
        }
    }

    public func SetMachineOutliner(enable: Bool): Unit {
        if (!raw.isNull()) {
            let _ = enable
        }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        if (!raw.isNull()) {
            unsafe { LLVMDisposeTargetMachine(raw) }
        }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

public class LLVMTargetDataHandle <: Resource {
    public let raw: LLVMTargetDataRef
    private let owned: Bool
    private var closed: Bool = false

    public init(raw: LLVMTargetDataRef, owned!: Bool = true) {
        this.raw = raw
        this.owned = owned
    }

    public static func Create(dataLayout: String): Option<LLVMTargetDataHandle> {
        var result: Option<LLVMTargetDataHandle> = None
        try (layoutCString = unsafe { LibC.mallocCString(dataLayout) }.asResource()) {
            let targetData = unsafe { LLVMCreateTargetData(layoutCString.value) }
            if (!targetData.isNull()) {
                result = LLVMTargetDataHandle(targetData)
            }
        }
        return result
    }

    public static func FromModule(module: LLVMModuleHandle): LLVMTargetDataHandle {
        return LLVMTargetDataHandle(unsafe { LLVMGetModuleDataLayout(module.raw) }, owned: false)
    }

    public func CopyStringRep(): String {
        if (raw.isNull()) {
            return ""
        }
        return LLVMConsumeMessage(unsafe { LLVMCopyStringRepOfTargetData(raw) })
    }

    public func GetByteOrder(): Int32 {
        if (raw.isNull()) {
            return 0
        }
        return unsafe { LLVMByteOrder(raw) }
    }

    public func GetPointerSize(addressSpace!: UInt32 = 0u32): UInt32 {
        if (raw.isNull()) {
            return 0u32
        }
        if (addressSpace == 0u32) {
            return unsafe { LLVMPointerSize(raw) }
        }
        return unsafe { LLVMPointerSizeForAS(raw, addressSpace) }
    }

    public func GetIntPtrType(context: LLVMContextHandle, addressSpace!: UInt32 = 0u32): LLVMTypeRef {
        if (raw.isNull()) {
            return LLVMNullType()
        }
        if (addressSpace == 0u32) {
            return unsafe { LLVMIntPtrTypeInContext(context.raw, raw) }
        }
        return unsafe { LLVMIntPtrTypeForASInContext(context.raw, raw, addressSpace) }
    }

    public func GetTypeSizeInBits(valueType: LLVMTypeRef): UInt64 {
        if (raw.isNull() || valueType.isNull()) {
            return 0u64
        }
        return unsafe { LLVMSizeOfTypeInBits(raw, valueType) }
    }

    public func GetTypeStoreSize(valueType: LLVMTypeRef): UInt64 {
        if (raw.isNull() || valueType.isNull()) {
            return 0u64
        }
        return unsafe { LLVMStoreSizeOfType(raw, valueType) }
    }

    public func GetTypeAllocSize(valueType: LLVMTypeRef): UInt64 {
        if (raw.isNull() || valueType.isNull()) {
            return 0u64
        }
        return unsafe { LLVMABISizeOfType(raw, valueType) }
    }

    public func GetABITypeAlignment(valueType: LLVMTypeRef): UInt32 {
        if (raw.isNull() || valueType.isNull()) {
            return 0u32
        }
        return unsafe { LLVMABIAlignmentOfType(raw, valueType) }
    }

    public func GetCallFrameTypeAlignment(valueType: LLVMTypeRef): UInt32 {
        if (raw.isNull() || valueType.isNull()) {
            return 0u32
        }
        return unsafe { LLVMCallFrameAlignmentOfType(raw, valueType) }
    }

    public func GetPrefTypeAlignment(valueType: LLVMTypeRef): UInt32 {
        if (raw.isNull() || valueType.isNull()) {
            return 0u32
        }
        return unsafe { LLVMPreferredAlignmentOfType(raw, valueType) }
    }

    public func GetPreferredAlignmentOfGlobal(globalVar: LLVMValueRef): UInt32 {
        if (raw.isNull() || globalVar.isNull()) {
            return 0u32
        }
        return unsafe { LLVMPreferredAlignmentOfGlobal(raw, globalVar) }
    }

    public func GetElementContainingOffset(structTy: LLVMTypeRef, offset: UInt64): UInt32 {
        if (raw.isNull() || structTy.isNull()) {
            return 0u32
        }
        return unsafe { LLVMElementAtOffset(raw, structTy, offset) }
    }

    public func GetOffsetOfElement(structTy: LLVMTypeRef, element: UInt32): UInt64 {
        if (raw.isNull() || structTy.isNull()) {
            return 0u64
        }
        return unsafe { LLVMOffsetOfElement(raw, structTy, element) }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        if (owned && !raw.isNull()) {
            unsafe { LLVMDisposeTargetData(raw) }
        }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}


public func LLVMCreateTargetMachineForTriple(triple: String, cpu!: String = "", features!: String = "",
    level!: LLVMCodeGenOptLevel = LLVMCodeGenOptLevel.CodeGenLevelDefault,
    reloc!: LLVMRelocMode = LLVMRelocMode.RelocDefault,
    codeModel!: LLVMCodeModel = LLVMCodeModel.CodeModelDefault): Option<LLVMTargetMachineHandle> {
    let targetResult = LLVMGetTargetFromTripleChecked(triple)
    if (!targetResult.ok || targetResult.target.isNull()) {
        return None
    }
    var result: Option<LLVMTargetMachineHandle> = None
    try (tripleCString = unsafe { LibC.mallocCString(triple) }.asResource(),
        cpuCString = unsafe { LibC.mallocCString(cpu) }.asResource(),
        featuresCString = unsafe { LibC.mallocCString(features) }.asResource()) {
        let rawTargetMachine = unsafe {
            LLVMCreateTargetMachine(targetResult.target, tripleCString.value, cpuCString.value, featuresCString.value,
                LLVMCodeGenOptLevelValue(level), LLVMRelocModeValue(reloc), LLVMCodeModelValue(codeModel))
        }
        if (!rawTargetMachine.isNull()) {
            result = LLVMTargetMachineHandle(rawTargetMachine)
        }
    }
    return result
}

public func LLVMCreateHostTargetMachine(level!: LLVMCodeGenOptLevel = LLVMCodeGenOptLevel.CodeGenLevelDefault,
    reloc!: LLVMRelocMode = LLVMRelocMode.RelocDefault,
    codeModel!: LLVMCodeModel = LLVMCodeModel.CodeModelDefault): Option<LLVMTargetMachineHandle> {
    let triple = LLVMGetDefaultTargetTripleString()
    let cpu = LLVMConsumeMessage(unsafe { LLVMGetHostCPUName() })
    let features = LLVMConsumeMessage(unsafe { LLVMGetHostCPUFeatures() })
    return LLVMCreateTargetMachineForTriple(triple, cpu: cpu, features: features, level: level, reloc: reloc,
        codeModel: codeModel)
}

public func LLVMTargetMachineEmitToFileChecked(targetMachine: LLVMTargetMachineHandle, module: LLVMModuleHandle,
    filename: String, fileType: LLVMCodeGenFileType): LLVMTargetEmissionResult {
    if (targetMachine.raw.isNull() || module.raw.isNull()) {
        return LLVMTargetEmissionResult.Failure("cannot emit LLVM module with null target machine or module")
    }
    var result = LLVMTargetEmissionResult.Failure("failed to emit LLVM module: " + filename)
    try (filenameCString = unsafe { LibC.mallocCString(filename) }.asResource(),
        outMessage = LibC.malloc<CString>().asResource()) {
        unsafe { outMessage.value.write(CString(CPointer<UInt8>())) }
        let status = unsafe {
            LLVMTargetMachineEmitToFile(targetMachine.raw, module.raw, filenameCString.value,
                LLVMCodeGenFileTypeValue(fileType), outMessage.value)
        }
        if (status == 0) {
            result = LLVMTargetEmissionResult.Success()
            let rawMessage = unsafe { outMessage.value.read() }
            if (!rawMessage.isNull()) {
                let _ = LLVMConsumeMessage(rawMessage)
            }
        } else {
            let message = LLVMConsumeMessage(unsafe { outMessage.value.read() })
            if (!message.isEmpty()) {
                result = LLVMTargetEmissionResult.Failure(message)
            }
        }
    }
    return result
}

public func LLVMTargetMachineEmitToMemoryBufferChecked(targetMachine: LLVMTargetMachineHandle,
    module: LLVMModuleHandle, fileType: LLVMCodeGenFileType): LLVMTargetEmissionResult {
    if (targetMachine.raw.isNull() || module.raw.isNull()) {
        return LLVMTargetEmissionResult.Failure("cannot emit LLVM module with null target machine or module")
    }
    var result = LLVMTargetEmissionResult.Failure("failed to emit LLVM module to memory buffer")
    try (outMessage = LibC.malloc<CString>().asResource(),
        outBuffer = LibC.malloc<LLVMMemoryBufferRef>().asResource()) {
        unsafe { outMessage.value.write(CString(CPointer<UInt8>())) }
        unsafe { outBuffer.value.write(CPointer<Unit>()) }
        let status = unsafe {
            LLVMTargetMachineEmitToMemoryBuffer(targetMachine.raw, module.raw, LLVMCodeGenFileTypeValue(fileType),
                outMessage.value, outBuffer.value)
        }
        if (status == 0) {
            let rawBuffer = unsafe { outBuffer.value.read() }
            if (rawBuffer.isNull()) {
                result = LLVMTargetEmissionResult.Failure("LLVM target emission returned a null memory buffer")
            } else {
                result = LLVMTargetEmissionResult.Success(LLVMMemoryBufferHandle(rawBuffer))
            }
            let rawMessage = unsafe { outMessage.value.read() }
            if (!rawMessage.isNull()) {
                let _ = LLVMConsumeMessage(rawMessage)
            }
        } else {
            let message = LLVMConsumeMessage(unsafe { outMessage.value.read() })
            if (!message.isEmpty()) {
                result = LLVMTargetEmissionResult.Failure(message)
            }
        }
    }
    return result
}
