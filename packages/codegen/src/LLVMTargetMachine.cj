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

    func LLVMCreateTargetMachineOptions(): LLVMTargetMachineOptionsRef
    func LLVMDisposeTargetMachineOptions(options: LLVMTargetMachineOptionsRef): Unit
    func LLVMTargetMachineOptionsSetCPU(options: LLVMTargetMachineOptionsRef, cpu: CString): Unit
    func LLVMTargetMachineOptionsSetFeatures(options: LLVMTargetMachineOptionsRef, features: CString): Unit
    func LLVMTargetMachineOptionsSetABI(options: LLVMTargetMachineOptionsRef, abi: CString): Unit
    func LLVMTargetMachineOptionsSetCodeGenOptLevel(options: LLVMTargetMachineOptionsRef, level: Int32): Unit
    func LLVMTargetMachineOptionsSetRelocMode(options: LLVMTargetMachineOptionsRef, reloc: Int32): Unit
    func LLVMTargetMachineOptionsSetCodeModel(options: LLVMTargetMachineOptionsRef, codeModel: Int32): Unit
    func LLVMCreateTargetMachineWithOptions(target: LLVMTargetRef, triple: CString,
        options: LLVMTargetMachineOptionsRef): LLVMTargetMachineRef
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

public class LLVMTargetMachineOptionsHandle <: Resource {
    public let raw: LLVMTargetMachineOptionsRef
    private var closed: Bool = false

    public init(raw: LLVMTargetMachineOptionsRef) {
        this.raw = raw
    }

    public static func Create(): LLVMTargetMachineOptionsHandle {
        return LLVMTargetMachineOptionsHandle(unsafe { LLVMCreateTargetMachineOptions() })
    }

    public func SetCPU(cpu: String): Unit {
        if (raw.isNull()) {
            return
        }
        try (cpuCString = unsafe { LibC.mallocCString(cpu) }.asResource()) {
            unsafe { LLVMTargetMachineOptionsSetCPU(raw, cpuCString.value) }
        }
    }

    public func SetFeatures(features: String): Unit {
        if (raw.isNull()) {
            return
        }
        try (featuresCString = unsafe { LibC.mallocCString(features) }.asResource()) {
            unsafe { LLVMTargetMachineOptionsSetFeatures(raw, featuresCString.value) }
        }
    }

    public func SetABI(abi: String): Unit {
        if (raw.isNull()) {
            return
        }
        try (abiCString = unsafe { LibC.mallocCString(abi) }.asResource()) {
            unsafe { LLVMTargetMachineOptionsSetABI(raw, abiCString.value) }
        }
    }

    public func SetCodeGenOptLevel(level: LLVMCodeGenOptLevel): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMTargetMachineOptionsSetCodeGenOptLevel(raw, LLVMCodeGenOptLevelValue(level)) }
        }
    }

    public func SetRelocMode(mode: LLVMRelocMode): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMTargetMachineOptionsSetRelocMode(raw, LLVMRelocModeValue(mode)) }
        }
    }

    public func SetCodeModel(model: LLVMCodeModel): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMTargetMachineOptionsSetCodeModel(raw, LLVMCodeModelValue(model)) }
        }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        if (!raw.isNull()) {
            unsafe { LLVMDisposeTargetMachineOptions(raw) }
        }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

public class LLVMTargetMachineHandle <: Resource {
    public let raw: LLVMTargetMachineRef
    private var closed: Bool = false

    public init(raw: LLVMTargetMachineRef) {
        this.raw = raw
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

public func LLVMCreateTargetMachineWithOptionsChecked(target: LLVMTargetRef, triple: String,
    options: LLVMTargetMachineOptionsHandle): Option<LLVMTargetMachineHandle> {
    if (target.isNull() || options.raw.isNull()) {
        return None
    }
    var result: Option<LLVMTargetMachineHandle> = None
    try (tripleCString = unsafe { LibC.mallocCString(triple) }.asResource()) {
        let rawTargetMachine = unsafe { LLVMCreateTargetMachineWithOptions(target, tripleCString.value, options.raw) }
        if (!rawTargetMachine.isNull()) {
            result = LLVMTargetMachineHandle(rawTargetMachine)
        }
    }
    return result
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
