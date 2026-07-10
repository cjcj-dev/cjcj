package cjcj::codegen

foreign {
    func LLVMVerifyModule(module: LLVMModuleRef, action: Int32, outMessage: CPointer<CString>): Int32
    func LLVMVerifyFunction(fn: LLVMValueRef, action: Int32): Int32
    func LLVMViewFunctionCFG(fn: LLVMValueRef): Unit
    func LLVMViewFunctionCFGOnly(fn: LLVMValueRef): Unit
}

public class LLVMModuleVerifyResult {
    public let ok: Bool
    public let message: String

    public init(ok: Bool, message!: String = "") {
        this.ok = ok
        this.message = message
    }
}

public func VerifyModule(module: LLVMModuleHandle,
    action!: LLVMVerifierFailureAction = LLVMVerifierFailureAction.ReturnStatus): LLVMModuleVerifyResult {
    if (module.raw.isNull()) {
        return LLVMModuleVerifyResult(false, message: "cannot verify null LLVM module")
    }
    var result = LLVMModuleVerifyResult(false, message: "failed to verify LLVM module")
    try (outMessage = LibC.malloc<CString>().asResource()) {
        unsafe { outMessage.value.write(CString(CPointer<UInt8>())) }
        let status = unsafe { LLVMVerifyModule(module.raw, LLVMVerifierFailureActionValue(action), outMessage.value) }
        let message = LLVMConsumeMessage(unsafe { outMessage.value.read() })
        result = LLVMModuleVerifyResult(status == 0, message: message)
    }
    return result
}

public func VerifyFunction(fn: LLVMValueRef): Bool {
    if (fn.isNull()) {
        return false
    }
    let status = unsafe {
        LLVMVerifyFunction(fn, LLVMVerifierFailureActionValue(LLVMVerifierFailureAction.ReturnStatus))
    }
    return status == 0
}
