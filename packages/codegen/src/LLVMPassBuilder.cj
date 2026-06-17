package cangjie_compiler::codegen

public type LLVMErrorRef = CPointer<Unit>
public type LLVMPassBuilderOptionsRef = CPointer<Unit>

foreign {
    func LLVMRunPasses(module: LLVMModuleRef, passes: CString, targetMachine: LLVMTargetMachineRef,
        options: LLVMPassBuilderOptionsRef): LLVMErrorRef
    func LLVMRunPassesOnFunction(fn: LLVMValueRef, passes: CString, targetMachine: LLVMTargetMachineRef,
        options: LLVMPassBuilderOptionsRef): LLVMErrorRef
    func LLVMCreatePassBuilderOptions(): LLVMPassBuilderOptionsRef
    func LLVMDisposePassBuilderOptions(options: LLVMPassBuilderOptionsRef): Unit
    func LLVMPassBuilderOptionsSetVerifyEach(options: LLVMPassBuilderOptionsRef, verifyEach: Int32): Unit
    func LLVMPassBuilderOptionsSetDebugLogging(options: LLVMPassBuilderOptionsRef, debugLogging: Int32): Unit
    func LLVMPassBuilderOptionsSetAAPipeline(options: LLVMPassBuilderOptionsRef, aaPipeline: CString): Unit
    func LLVMPassBuilderOptionsSetLoopInterleaving(options: LLVMPassBuilderOptionsRef, loopInterleaving: Int32): Unit
    func LLVMPassBuilderOptionsSetLoopVectorization(options: LLVMPassBuilderOptionsRef, loopVectorization: Int32): Unit
    func LLVMPassBuilderOptionsSetSLPVectorization(options: LLVMPassBuilderOptionsRef, slpVectorization: Int32): Unit
    func LLVMPassBuilderOptionsSetLoopUnrolling(options: LLVMPassBuilderOptionsRef, loopUnrolling: Int32): Unit
    func LLVMPassBuilderOptionsSetCallGraphProfile(options: LLVMPassBuilderOptionsRef, callGraphProfile: Int32): Unit
    func LLVMPassBuilderOptionsSetMergeFunctions(options: LLVMPassBuilderOptionsRef, mergeFunctions: Int32): Unit
    func LLVMPassBuilderOptionsSetInlinerThreshold(options: LLVMPassBuilderOptionsRef, threshold: Int32): Unit
    func LLVMConsumeError(error: LLVMErrorRef): Unit
    func LLVMGetErrorMessage(error: LLVMErrorRef): CString
    func LLVMDisposeErrorMessage(message: CString): Unit
}

public class LLVMPassBuilderOptionsHandle <: Resource {
    public let raw: LLVMPassBuilderOptionsRef
    private var closed: Bool = false

    public init(raw: LLVMPassBuilderOptionsRef) {
        this.raw = raw
    }

    public static func Create(): LLVMPassBuilderOptionsHandle {
        return LLVMPassBuilderOptionsHandle(unsafe { LLVMCreatePassBuilderOptions() })
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        if (!raw.isNull()) {
            unsafe { LLVMDisposePassBuilderOptions(raw) }
        }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }
}

public class LLVMRunPassesResult {
    public let ok: Bool
    public let message: String

    public init(ok: Bool, message!: String = "") {
        this.ok = ok
        this.message = message
    }
}

public func RunLLVMPasses(module: LLVMModuleHandle, passes: String, targetMachine!: LLVMTargetMachineRef =
    LLVMNullTargetMachine(), options!: LLVMPassBuilderOptionsRef = LLVMNullPassBuilderOptions()): LLVMRunPassesResult {
    var result = LLVMRunPassesResult(false, message: "failed to run LLVM passes")
    try (passesCString = unsafe { LibC.mallocCString(passes) }.asResource()) {
        let error = unsafe { LLVMRunPasses(module.raw, passesCString.value, targetMachine, options) }
        result = ConsumeLLVMError(error)
    }
    return result
}

public func ConsumeLLVMError(error: LLVMErrorRef): LLVMRunPassesResult {
    if (error.isNull()) {
        return LLVMRunPassesResult(true)
    }
    let rawMessage = unsafe { LLVMGetErrorMessage(error) }
    let message = LLVMCStringToString(rawMessage) ?? ""
    if (!rawMessage.isNull()) {
        unsafe { LLVMDisposeErrorMessage(rawMessage) }
    }
    return LLVMRunPassesResult(false, message: message)
}

public func LLVMNullPassBuilderOptions(): LLVMPassBuilderOptionsRef { return CPointer<Unit>() }
