package cangjie_compiler::codegen

import cangjie_compiler::chir.FuncKind
import cangjie_compiler::chir.Function

public func AddAttributeAtIndex(callBase: LLVMValueRef, idx: UInt32, attrName: String): Unit {
    // TODO(selfhost:CodeGen): bind LLVM attribute APIs for calls/functions/arguments.
}

public func AddParamAttr(callBase: LLVMValueRef, paramIdx: UInt32, attrName: String): Unit {
    AddAttributeAtIndex(callBase, paramIdx + 1u32, attrName)
}

public func AddRetAttr(callBase: LLVMValueRef, attrName: String): Unit {
    AddAttributeAtIndex(callBase, 0u32, attrName)
}

public func AddSRetAttribute(value: LLVMValueRef): Unit {
    // TODO(selfhost:CodeGen): attach sret(<element type>) through LLVM C API or native adapter.
}

public func ShouldReturnVoid(fn: Function): Bool {
    let kind = fn.GetFuncKind()
    return kind == FuncKind.CLASS_CONSTRUCTOR || kind == FuncKind.PRIMAL_CLASS_CONSTRUCTOR ||
        kind == FuncKind.STRUCT_CONSTRUCTOR || kind == FuncKind.PRIMAL_STRUCT_CONSTRUCTOR ||
        kind == FuncKind.GLOBALVAR_INIT || kind == FuncKind.FINALIZER
}
