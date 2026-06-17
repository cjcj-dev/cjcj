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

public class LLVMTargetMachineOptionsHandle <: Resource {
    public let raw: LLVMTargetMachineOptionsRef
    private var closed: Bool = false

    public init(raw: LLVMTargetMachineOptionsRef) {
        this.raw = raw
    }

    public static func Create(): LLVMTargetMachineOptionsHandle {
        return LLVMTargetMachineOptionsHandle(unsafe { LLVMCreateTargetMachineOptions() })
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
