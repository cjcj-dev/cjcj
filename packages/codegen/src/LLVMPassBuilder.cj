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
    func LLVMPassBuilderOptionsSetForgetAllSCEVInLoopUnroll(options: LLVMPassBuilderOptionsRef,
        forgetAllSCEVInLoopUnroll: Int32): Unit
    func LLVMPassBuilderOptionsSetLicmMssaOptCap(options: LLVMPassBuilderOptionsRef, licmMssaOptCap: UInt32): Unit
    func LLVMPassBuilderOptionsSetLicmMssaNoAccForPromotionCap(options: LLVMPassBuilderOptionsRef,
        licmMssaNoAccForPromotionCap: UInt32): Unit
    func LLVMPassBuilderOptionsSetCallGraphProfile(options: LLVMPassBuilderOptionsRef, callGraphProfile: Int32): Unit
    func LLVMPassBuilderOptionsSetMergeFunctions(options: LLVMPassBuilderOptionsRef, mergeFunctions: Int32): Unit
    func LLVMPassBuilderOptionsSetInlinerThreshold(options: LLVMPassBuilderOptionsRef, threshold: Int32): Unit
    func LLVMConsumeError(error: LLVMErrorRef): Unit
    func LLVMGetErrorMessage(error: LLVMErrorRef): CString
    func LLVMDisposeErrorMessage(message: CString): Unit
}

public class LLVMPassBuilderOptionsHandle <: Resource {
    public let raw: LLVMPassBuilderOptionsRef
    private var aaPipelineCString: Option<CStringResource> = None
    private var closed: Bool = false

    public init(raw: LLVMPassBuilderOptionsRef) {
        this.raw = raw
    }

    public static func Create(): LLVMPassBuilderOptionsHandle {
        return LLVMPassBuilderOptionsHandle(unsafe { LLVMCreatePassBuilderOptions() })
    }

    public func SetVerifyEach(enable: Bool): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetVerifyEach(raw, LLVMBoolValue(enable)) }
        }
    }

    public func SetDebugLogging(enable: Bool): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetDebugLogging(raw, LLVMBoolValue(enable)) }
        }
    }

    public func SetAAPipeline(aaPipeline: String): Unit {
        if (raw.isNull()) {
            return
        }
        let pipelineCString = unsafe { LibC.mallocCString(aaPipeline) }.asResource()
        unsafe { LLVMPassBuilderOptionsSetAAPipeline(raw, pipelineCString.value) }
        ClearAAPipelineCString()
        aaPipelineCString = Some(pipelineCString)
    }

    public func SetLoopInterleaving(enable: Bool): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetLoopInterleaving(raw, LLVMBoolValue(enable)) }
        }
    }

    public func SetLoopVectorization(enable: Bool): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetLoopVectorization(raw, LLVMBoolValue(enable)) }
        }
    }

    public func SetSLPVectorization(enable: Bool): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetSLPVectorization(raw, LLVMBoolValue(enable)) }
        }
    }

    public func SetLoopUnrolling(enable: Bool): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetLoopUnrolling(raw, LLVMBoolValue(enable)) }
        }
    }

    public func SetForgetAllSCEVInLoopUnroll(enable: Bool): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetForgetAllSCEVInLoopUnroll(raw, LLVMBoolValue(enable)) }
        }
    }

    public func SetLicmMssaOptCap(cap: UInt32): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetLicmMssaOptCap(raw, cap) }
        }
    }

    public func SetLicmMssaNoAccForPromotionCap(cap: UInt32): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetLicmMssaNoAccForPromotionCap(raw, cap) }
        }
    }

    public func SetCallGraphProfile(enable: Bool): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetCallGraphProfile(raw, LLVMBoolValue(enable)) }
        }
    }

    public func SetMergeFunctions(enable: Bool): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetMergeFunctions(raw, LLVMBoolValue(enable)) }
        }
    }

    public func SetInlinerThreshold(threshold: Int32): Unit {
        if (!raw.isNull()) {
            unsafe { LLVMPassBuilderOptionsSetInlinerThreshold(raw, threshold) }
        }
    }

    public func close(): Unit {
        if (closed) {
            return
        }
        ClearAAPipelineCString()
        if (!raw.isNull()) {
            unsafe { LLVMDisposePassBuilderOptions(raw) }
        }
        closed = true
    }

    public func isClosed(): Bool {
        return closed
    }

    private func ClearAAPipelineCString(): Unit {
        if (let Some(pipelineCString) <- aaPipelineCString) {
            pipelineCString.close()
            aaPipelineCString = None
        }
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

private func LLVMBoolValue(value: Bool): Int32 {
    return if (value) { 1 } else { 0 }
}

public func RunLLVMPasses(module: LLVMModuleHandle, passes: String,
    targetMachine!: LLVMTargetMachineRef = LLVMNullTargetMachine(),
    options!: LLVMPassBuilderOptionsRef = LLVMNullPassBuilderOptions()): LLVMRunPassesResult {
    var result = LLVMRunPassesResult(false, message: "failed to run LLVM passes")
    try (passesCString = unsafe { LibC.mallocCString(passes) }.asResource()) {
        let error = unsafe { LLVMRunPasses(module.raw, passesCString.value, targetMachine, options) }
        result = ConsumeLLVMError(error)
    }
    return result
}

public func RunLLVMPasses(module: LLVMModuleHandle, passes: String, targetMachine: LLVMTargetMachineHandle,
    options: LLVMPassBuilderOptionsHandle): LLVMRunPassesResult {
    return RunLLVMPasses(module, passes, targetMachine: targetMachine.raw, options: options.raw)
}

public func RunLLVMPasses(module: LLVMModuleHandle, passes: String,
    options: LLVMPassBuilderOptionsHandle): LLVMRunPassesResult {
    return RunLLVMPasses(module, passes, options: options.raw)
}

public func RunLLVMPassesOnFunction(fn: LLVMValueRef, passes: String,
    targetMachine!: LLVMTargetMachineRef = LLVMNullTargetMachine(),
    options!: LLVMPassBuilderOptionsRef = LLVMNullPassBuilderOptions()): LLVMRunPassesResult {
    if (fn.isNull()) {
        return LLVMRunPassesResult(false, message: "cannot run LLVM passes on null function")
    }
    var result = LLVMRunPassesResult(false, message: "failed to run LLVM function passes")
    try (passesCString = unsafe { LibC.mallocCString(passes) }.asResource()) {
        let error = unsafe { LLVMRunPassesOnFunction(fn, passesCString.value, targetMachine, options) }
        result = ConsumeLLVMError(error)
    }
    return result
}

public func RunLLVMPassesOnFunction(fn: LLVMValueRef, passes: String, targetMachine: LLVMTargetMachineHandle,
    options: LLVMPassBuilderOptionsHandle): LLVMRunPassesResult {
    return RunLLVMPassesOnFunction(fn, passes, targetMachine: targetMachine.raw, options: options.raw)
}

public func RunLLVMPassesOnFunction(fn: LLVMValueRef, passes: String,
    options: LLVMPassBuilderOptionsHandle): LLVMRunPassesResult {
    return RunLLVMPassesOnFunction(fn, passes, options: options.raw)
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
