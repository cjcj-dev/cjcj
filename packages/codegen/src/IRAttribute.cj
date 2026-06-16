package cangjie_compiler::codegen

import cangjie_compiler::chir.FuncKind
import cangjie_compiler::chir.Function

public func AddAttributeAtIndex(callBase: LLVMValueRef, idx: UInt32, attrName: String): Unit {
    try (attrCString = unsafe { LibC.mallocCString(attrName) }.asResource()) {
        let attrKind = unsafe { LLVMGetEnumAttributeKindForName(attrCString.value, UIntNative(attrName.size)) }
        if (attrKind == 0u32) {
            return
        }
        let parentModule = unsafe { LLVMGetGlobalParent(callBase) }
        let attrContext = unsafe { LLVMGetModuleContext(parentModule) }
        let attr = unsafe { LLVMCreateEnumAttribute(attrContext, attrKind, 0u64) }
        unsafe { LLVMAddAttributeAtIndex(callBase, idx, attr) }
    }
}

public func AddParamAttr(callBase: LLVMValueRef, paramIdx: UInt32, attrName: String): Unit {
    AddAttributeAtIndex(callBase, paramIdx + 1u32, attrName)
}

public func AddRetAttr(callBase: LLVMValueRef, attrName: String): Unit {
    AddAttributeAtIndex(callBase, 0u32, attrName)
}

public func AddSRetAttribute(value: LLVMValueRef): Unit {
    AddAttributeAtIndex(value, 1u32, "sret")
}

public func ShouldReturnVoid(fn: Function): Bool {
    let kind = fn.GetFuncKind()
    return kind == FuncKind.CLASS_CONSTRUCTOR || kind == FuncKind.PRIMAL_CLASS_CONSTRUCTOR ||
        kind == FuncKind.STRUCT_CONSTRUCTOR || kind == FuncKind.PRIMAL_STRUCT_CONSTRUCTOR ||
        kind == FuncKind.GLOBALVAR_INIT || kind == FuncKind.FINALIZER
}
