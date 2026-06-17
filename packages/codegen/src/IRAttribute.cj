package cangjie_compiler::codegen

import cangjie_compiler::chir.FuncKind
import cangjie_compiler::chir.Function

private let LLVM_INTEGER_TYPE_KIND: Int32 = 8
private let LLVM_ZEROEXT_ATTR: String = "zeroext"

private func GetAttributeKind(attrName: String): UInt32 {
    var attrKind: UInt32 = 0u32
    try (attrCString = unsafe { LibC.mallocCString(attrName) }.asResource()) {
        attrKind = unsafe { LLVMGetEnumAttributeKindForName(attrCString.value, UIntNative(attrName.size)) }
    }
    return attrKind
}

private func GetLLVMValueContext(value: LLVMValueRef): LLVMContextRef {
    if (value.isNull()) {
        return LLVMNullContext()
    }
    return unsafe { LLVMGetValueContext(value) }
}

private func IsLLVMFunction(value: LLVMValueRef): Bool {
    return !value.isNull() && !unsafe { LLVMIsAFunction(value) }.isNull()
}

private func IsLLVMInt1Type(valueType: LLVMTypeRef): Bool {
    return !valueType.isNull() && unsafe { LLVMGetTypeKind(valueType) } == LLVM_INTEGER_TYPE_KIND &&
        unsafe { LLVMGetIntTypeWidth(valueType) } == 1u32
}

public func GetAttributeAtIndex(value: LLVMValueRef, idx: UInt32, attrName: String): LLVMAttributeRef {
    if (value.isNull()) {
        return LLVMNullAttribute()
    }
    let attrKind = GetAttributeKind(attrName)
    if (attrKind == 0u32) {
        return LLVMNullAttribute()
    }
    let attrCount = unsafe { LLVMGetAttributeCountAtIndex(value, idx) }
    if (attrCount == 0u32) {
        return LLVMNullAttribute()
    }
    try (attrs = LibC.malloc<LLVMAttributeRef>(count: Int64(attrCount)).asResource()) {
        unsafe { LLVMGetAttributesAtIndex(value, idx, attrs.value) }
        var attrIdx: Int64 = 0
        while (attrIdx < Int64(attrCount)) {
            let attr = unsafe { (attrs.value + attrIdx).read() }
            if (!attr.isNull() && unsafe { LLVMGetEnumAttributeKind(attr) } == attrKind) {
                return attr
            }
            attrIdx++
        }
    }
    return LLVMNullAttribute()
}

public func HasAttributeAtIndex(value: LLVMValueRef, idx: UInt32, attrName: String): Bool {
    return !GetAttributeAtIndex(value, idx, attrName).isNull()
}

public func GetTypeAttributeValueAtIndex(value: LLVMValueRef, idx: UInt32, attrName: String): Option<LLVMTypeRef> {
    let attr = GetAttributeAtIndex(value, idx, attrName)
    if (attr.isNull() || unsafe { LLVMIsTypeAttribute(attr) } == 0) {
        return None
    }
    let attrType = unsafe { LLVMGetTypeAttributeValue(attr) }
    if (attrType.isNull()) {
        return None
    }
    return Some(attrType)
}

public func AddAttributeAtIndex(callBase: LLVMValueRef, idx: UInt32, attrName: String): Unit {
    if (callBase.isNull() || HasAttributeAtIndex(callBase, idx, attrName)) {
        return
    }
    let attrKind = GetAttributeKind(attrName)
    let attrContext = GetLLVMValueContext(callBase)
    if (attrKind == 0u32 || attrContext.isNull()) {
        return
    }
    let attr = unsafe { LLVMCreateEnumAttribute(attrContext, attrKind, 0u64) }
    unsafe { LLVMAddAttributeAtIndex(callBase, idx, attr) }
}

public func AddTypeAttributeAtIndex(callBase: LLVMValueRef, idx: UInt32, attrName: String,
    attrType: LLVMTypeRef): Unit {
    if (callBase.isNull() || attrType.isNull() || HasAttributeAtIndex(callBase, idx, attrName)) {
        return
    }
    let attrKind = GetAttributeKind(attrName)
    let attrContext = GetLLVMValueContext(callBase)
    if (attrKind == 0u32 || attrContext.isNull()) {
        return
    }
    let attr = unsafe { LLVMCreateTypeAttribute(attrContext, attrKind, attrType) }
    unsafe { LLVMAddAttributeAtIndex(callBase, idx, attr) }
}

public func AddParamAttr(callBase: LLVMValueRef, paramIdx: UInt32, attrName: String): Unit {
    AddAttributeAtIndex(callBase, paramIdx + 1u32, attrName)
}

public func AddRetAttr(callBase: LLVMValueRef, attrName: String): Unit {
    AddAttributeAtIndex(callBase, 0u32, attrName)
}

public func AddFnAttr(fn: LLVMValueRef, attrName: String): Unit {
    AddAttributeAtIndex(fn, UInt32.Max, attrName)
}

public func AddSRetAttribute(value: LLVMValueRef): Unit {
    AddAttributeAtIndex(value, 1u32, "sret")
}

public func AddSRetAttribute(value: LLVMValueRef, sretType: LLVMTypeRef): Unit {
    AddTypeAttributeAtIndex(value, 1u32, "sret", sretType)
}

public func AddNoAliasAttribute(value: LLVMValueRef): Unit {
    AddAttributeAtIndex(value, 1u32, "noalias")
}

public func SetZExtAttrForCFunc(callBase: LLVMValueRef, functionType: LLVMTypeRef): Unit {
    if (callBase.isNull() || functionType.isNull()) {
        return
    }
    if (IsLLVMInt1Type(unsafe { LLVMGetReturnType(functionType) })) {
        AddRetAttr(callBase, LLVM_ZEROEXT_ATTR)
    }
    let paramCount = unsafe { LLVMCountParamTypes(functionType) }
    if (paramCount == 0u32) {
        return
    }
    try (paramTypes = LibC.malloc<LLVMTypeRef>(count: Int64(paramCount)).asResource()) {
        unsafe { LLVMGetParamTypes(functionType, paramTypes.value) }
        var idx: UInt32 = 0u32
        while (idx < paramCount) {
            let paramType = unsafe { (paramTypes.value + Int64(idx)).read() }
            if (IsLLVMInt1Type(paramType)) {
                AddParamAttr(callBase, idx, LLVM_ZEROEXT_ATTR)
            }
            idx++
        }
    }
}

private func PropagateZExtAttributeFromCallee(callee: LLVMValueRef, callBase: LLVMValueRef): Unit {
    if (!IsLLVMFunction(callee) || callBase.isNull()) {
        return
    }
    if (HasAttributeAtIndex(callee, 0u32, LLVM_ZEROEXT_ATTR)) {
        AddRetAttr(callBase, LLVM_ZEROEXT_ATTR)
    }
    let paramCount = unsafe { LLVMCountParams(callee) }
    var idx: UInt32 = 0u32
    while (idx < paramCount) {
        if (HasAttributeAtIndex(callee, idx + 1u32, LLVM_ZEROEXT_ATTR)) {
            AddParamAttr(callBase, idx, LLVM_ZEROEXT_ATTR)
        }
        idx++
    }
}

private func PropagateSRetAttributeFromCallee(callee: LLVMValueRef, callBase: LLVMValueRef): Unit {
    if (!IsLLVMFunction(callee) || callBase.isNull()) {
        return
    }
    if (let Some(sretType) <- GetTypeAttributeValueAtIndex(callee, 1u32, "sret")) {
        AddSRetAttribute(callBase, sretType)
        AddNoAliasAttribute(callBase)
        return
    }
    if (HasAttributeAtIndex(callee, 1u32, "sret")) {
        AddSRetAttribute(callBase)
        AddNoAliasAttribute(callBase)
    }
}

public func PropagateCallABIAttributesFromCallee(callee: LLVMValueRef, callBase: LLVMValueRef): Unit {
    PropagateSRetAttributeFromCallee(callee, callBase)
    PropagateZExtAttributeFromCallee(callee, callBase)
}

public func ShouldReturnVoid(fn: Function): Bool {
    let kind = fn.GetFuncKind()
    return kind == FuncKind.CLASS_CONSTRUCTOR || kind == FuncKind.PRIMAL_CLASS_CONSTRUCTOR ||
        kind == FuncKind.STRUCT_CONSTRUCTOR || kind == FuncKind.PRIMAL_STRUCT_CONSTRUCTOR ||
        kind == FuncKind.GLOBALVAR_INIT || kind == FuncKind.FINALIZER
}
