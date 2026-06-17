package cangjie_compiler::codegen

foreign {
    func LLVMVerifyFunction(fn: LLVMValueRef, action: Int32): Int32
    func LLVMViewFunctionCFG(fn: LLVMValueRef): Unit
    func LLVMViewFunctionCFGOnly(fn: LLVMValueRef): Unit
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
