package cjcj::codegen

import cjcj::chir.FuncKind
import cjcj::chir.FuncType
import cjcj::chir.Function

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
    return unsafe { LLVMGetTypeContext(LLVMTypeOf(value)) }
}

private func IsLLVMFunction(value: LLVMValueRef): Bool {
    return !value.isNull() && !unsafe { LLVMIsAFunction(value) }.isNull()
}

private func IsLLVMInt1Type(valueType: LLVMTypeRef): Bool {
    return !valueType.isNull() && unsafe { LLVMGetTypeKind(valueType) } == LLVM_INTEGER_TYPE_KIND &&
        unsafe { LLVMGetIntTypeWidth(valueType) } == 1u32
}

public func GetStringAttributeKindName(attr: LLVMAttributeRef): Option<String> {
    if (attr.isNull() || unsafe { LLVMIsStringAttribute(attr) } == 0) {
        return None
    }
    var result: Option<String> = None
    try (lenPtr = LibC.malloc<UInt32>().asResource()) {
        unsafe { lenPtr.value.write(0u32) }
        let rawKind = unsafe { LLVMGetStringAttributeKind(attr, lenPtr.value) }
        let kindLen = unsafe { lenPtr.value.read() }
        result = LLVMCStringToString(rawKind, UIntNative(kindLen))
    }
    return result
}

public func GetStringAttributeValue(attr: LLVMAttributeRef): Option<String> {
    if (attr.isNull() || unsafe { LLVMIsStringAttribute(attr) } == 0) {
        return None
    }
    var result: Option<String> = None
    try (lenPtr = LibC.malloc<UInt32>().asResource()) {
        unsafe { lenPtr.value.write(0u32) }
        let rawAttrValue = unsafe { LLVMGetStringAttributeValue(attr, lenPtr.value) }
        let attrValueLen = unsafe { lenPtr.value.read() }
        result = LLVMCStringToString(rawAttrValue, UIntNative(attrValueLen))
    }
    return result
}

public func GetStringAttributeAtIndex(llvmValue: LLVMValueRef, idx: UInt32, attrName: String): LLVMAttributeRef {
    if (llvmValue.isNull() || attrName.isEmpty()) {
        return LLVMNullAttribute()
    }
    var result = LLVMNullAttribute()
    try (attrCString = unsafe { LibC.mallocCString(attrName) }.asResource()) {
        result = unsafe { LLVMGetStringAttributeAtIndex(llvmValue, idx, attrCString.value, UInt32(attrName.size)) }
    }
    return result
}

public func HasStringAttributeAtIndex(llvmValue: LLVMValueRef, idx: UInt32, attrName: String): Bool {
    return !GetStringAttributeAtIndex(llvmValue, idx, attrName).isNull()
}

public func GetStringAttributeValueAtIndex(llvmValue: LLVMValueRef, idx: UInt32, attrName: String): Option<String> {
    return GetStringAttributeValue(GetStringAttributeAtIndex(llvmValue, idx, attrName))
}

public func GetAttributeAtIndex(llvmValue: LLVMValueRef, idx: UInt32, attrName: String): LLVMAttributeRef {
    if (llvmValue.isNull() || attrName.isEmpty()) {
        return LLVMNullAttribute()
    }
    let attrKind = GetAttributeKind(attrName)
    if (attrKind == 0u32) {
        return GetStringAttributeAtIndex(llvmValue, idx, attrName)
    }
    let attrCount = unsafe { LLVMGetAttributeCountAtIndex(llvmValue, idx) }
    if (attrCount == 0u32) {
        return LLVMNullAttribute()
    }
    try (attrs = LibC.malloc<LLVMAttributeRef>(count: Int64(attrCount)).asResource()) {
        unsafe { LLVMGetAttributesAtIndex(llvmValue, idx, attrs.value) }
        var attrIdx: Int64 = 0
        while (attrIdx < Int64(attrCount)) {
            let attr = unsafe { (attrs.value + attrIdx).read() }
            if (!attr.isNull() && unsafe { LLVMIsStringAttribute(attr) } == 0 &&
                unsafe { LLVMGetEnumAttributeKind(attr) } == attrKind) {
                return attr
            }
            attrIdx++
        }
    }
    return LLVMNullAttribute()
}

public func HasAttributeAtIndex(llvmValue: LLVMValueRef, idx: UInt32, attrName: String): Bool {
    return !GetAttributeAtIndex(llvmValue, idx, attrName).isNull()
}

public func GetTypeAttributeValueAtIndex(llvmValue: LLVMValueRef, idx: UInt32, attrName: String): Option<LLVMTypeRef> {
    let attr = GetAttributeAtIndex(llvmValue, idx, attrName)
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
    if (callBase.isNull() || attrName.isEmpty()) {
        return
    }
    if (IsLLVMFunction(callBase) && HasAttributeAtIndex(callBase, idx, attrName)) {
        return
    }
    let attrKind = GetAttributeKind(attrName)
    let attrContext = GetLLVMValueContext(callBase)
    if (attrContext.isNull()) {
        return
    }
    if (attrKind == 0u32) {
        AddStringAttributeAtIndex(callBase, idx, attrName)
        return
    }
    let attr = unsafe { LLVMCreateEnumAttribute(attrContext, attrKind, 0u64) }
    if (IsLLVMFunction(callBase)) {
        unsafe { LLVMAddAttributeAtIndex(callBase, idx, attr) }
    } else {
        unsafe { LLVMAddCallSiteAttribute(callBase, idx, attr) }
    }
}

public func AddStringAttributeAtIndex(llvmValue: LLVMValueRef, idx: UInt32, attrName: String,
    attrValue!: String = ""): Unit {
    if (llvmValue.isNull() || attrName.isEmpty()) {
        return
    }
    if (IsLLVMFunction(llvmValue) && HasStringAttributeAtIndex(llvmValue, idx, attrName)) {
        return
    }
    let attrContext = GetLLVMValueContext(llvmValue)
    if (attrContext.isNull()) {
        return
    }
    try (attrCString = unsafe { LibC.mallocCString(attrName) }.asResource(),
        attrValueCString = unsafe { LibC.mallocCString(attrValue) }.asResource()) {
        let attr = unsafe {
            LLVMCreateStringAttribute(attrContext, attrCString.value, UInt32(attrName.size), attrValueCString.value,
                UInt32(attrValue.size))
        }
        if (!attr.isNull()) {
            if (IsLLVMFunction(llvmValue)) {
                unsafe { LLVMAddAttributeAtIndex(llvmValue, idx, attr) }
            } else {
                unsafe { LLVMAddCallSiteAttribute(llvmValue, idx, attr) }
            }
        }
    }
}

public func AddTypeAttributeAtIndex(callBase: LLVMValueRef, idx: UInt32, attrName: String,
    attrType: LLVMTypeRef): Unit {
    if (callBase.isNull() || attrType.isNull()) {
        return
    }
    if (IsLLVMFunction(callBase) && HasAttributeAtIndex(callBase, idx, attrName)) {
        return
    }
    let attrKind = GetAttributeKind(attrName)
    let attrContext = GetLLVMValueContext(callBase)
    if (attrKind == 0u32 || attrContext.isNull()) {
        return
    }
    let attr = unsafe { LLVMCreateTypeAttribute(attrContext, attrKind, attrType) }
    if (IsLLVMFunction(callBase)) {
        unsafe { LLVMAddAttributeAtIndex(callBase, idx, attr) }
    } else {
        unsafe { LLVMAddCallSiteAttribute(callBase, idx, attr) }
    }
}

public func RemoveAttributeAtIndex(llvmValue: LLVMValueRef, idx: UInt32, attrName: String): Unit {
    if (llvmValue.isNull() || attrName.isEmpty()) {
        return
    }
    let attrKind = GetAttributeKind(attrName)
    if (attrKind != 0u32) {
        if (IsLLVMFunction(llvmValue)) {
            unsafe { LLVMRemoveEnumAttributeAtIndex(llvmValue, idx, attrKind) }
        } else {
            unsafe { LLVMRemoveCallSiteEnumAttribute(llvmValue, idx, attrKind) }
        }
    }
    try (attrCString = unsafe { LibC.mallocCString(attrName) }.asResource()) {
        if (IsLLVMFunction(llvmValue)) {
            unsafe { LLVMRemoveStringAttributeAtIndex(llvmValue, idx, attrCString.value, UInt32(attrName.size)) }
        } else {
            unsafe { LLVMRemoveCallSiteStringAttribute(llvmValue, idx, attrCString.value, UInt32(attrName.size)) }
        }
    }
}

public func AddParamAttr(callBase: LLVMValueRef, paramIdx: UInt32, attrName: String): Unit {
    AddAttributeAtIndex(callBase, paramIdx + 1u32, attrName)
}

public func AddRetAttr(callBase: LLVMValueRef, attrName: String): Unit {
    AddAttributeAtIndex(callBase, 0u32, attrName)
}

public func AddFnAttr(fn: LLVMValueRef, attrName: String, attrValue!: String = ""): Unit {
    if (attrValue.isEmpty()) {
        AddAttributeAtIndex(fn, UInt32.Max, attrName)
        return
    }
    AddStringAttributeAtIndex(fn, UInt32.Max, attrName, attrValue: attrValue)
}

public func AddFnStringAttr(fn: LLVMValueRef, attrName: String, attrValue!: String = ""): Unit {
    AddStringAttributeAtIndex(fn, UInt32.Max, attrName, attrValue: attrValue)
}

public func addAttribute(gv: LLVMValueRef, name: String, value!: String = ""): Unit {
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource(),
        valueCString = unsafe { LibC.mallocCString(value) }.asResource()) {
        unsafe {
            LLVMGlobalObjectAddStringAttribute(gv, nameCString.value, UInt32(name.toArray().size),
                valueCString.value, UInt32(value.toArray().size))
        }
    }
}

public func RemoveParamAttr(callBase: LLVMValueRef, paramIdx: UInt32, attrName: String): Unit {
    RemoveAttributeAtIndex(callBase, paramIdx + 1u32, attrName)
}

public func RemoveRetAttr(callBase: LLVMValueRef, attrName: String): Unit {
    RemoveAttributeAtIndex(callBase, 0u32, attrName)
}

public func RemoveFnAttr(fn: LLVMValueRef, attrName: String): Unit {
    RemoveAttributeAtIndex(fn, UInt32.Max, attrName)
}

public func AddSRetAttribute(value: LLVMValueRef): Unit {
    AddAttributeAtIndex(value, 1u32, "sret")
}

public func AddSRetAttribute(value: LLVMValueRef, sretType: LLVMTypeRef): Unit {
    AddTypeAttributeAtIndex(value, 1u32, "sret", sretType)
}

public func AddByValAttribute(value: LLVMValueRef, byValType: LLVMTypeRef, align!: UInt64 = 8u64): Unit {
    AddByValAttribute(value, 0u32, byValType, align: align)
}

public func AddByValAttribute(value: LLVMValueRef, paramIdx: UInt32, byValType: LLVMTypeRef,
    align!: UInt64 = 8u64): Unit {
    if (value.isNull() || byValType.isNull()) {
        return
    }
    let idx = paramIdx + 1u32
    if (IsLLVMFunction(value) && HasAttributeAtIndex(value, idx, "byval")) {
        return
    }
    let attrKind = GetAttributeKind("byval")
    let attrContext = GetLLVMValueContext(value)
    if (attrKind == 0u32 || attrContext.isNull()) {
        return
    }
    let attr = unsafe { LLVMCreateTypeAttribute(attrContext, attrKind, byValType) }
    if (IsLLVMFunction(value)) {
        unsafe { LLVMAddAttributeAtIndex(value, idx, attr) }
    } else {
        unsafe { LLVMAddCallSiteAttribute(value, idx, attr) }
    }
    let alignKind = GetAttributeKind("align")
    if (alignKind == 0u32) {
        return
    }
    let alignAttr = unsafe { LLVMCreateEnumAttribute(attrContext, alignKind, align) }
    if (IsLLVMFunction(value)) {
        unsafe { LLVMAddAttributeAtIndex(value, idx, alignAttr) }
    } else {
        unsafe { LLVMAddCallSiteAttribute(value, idx, alignAttr) }
    }
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
    if (!IsLLVMFunction(callee) || callBase.isNull() ||
        unsafe { LLVMSelfhostFunctionHasStructRetAttr(callee) } == 0) {
        return
    }
    AddNoAliasAttribute(callBase)
    if (let Some(sretType) <- GetTypeAttributeValueAtIndex(callee, 1u32, "sret")) {
        AddSRetAttribute(callBase, sretType)
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

public func SetSRetAttrForStructReturnType(chirFuncTy: FuncType, llvmFunc: LLVMValueRef): Unit {
    var shouldSetSRet = false
    if (chirFuncTy.IsCFunc()) {
        shouldSetSRet = HasAttributeAtIndex(llvmFunc, 1u32, "sret")
    } else {
        let llvmFuncTy = unsafe { LLVMGlobalGetValueType(llvmFunc) }
        let llvmRetTy = unsafe { LLVMGetReturnType(llvmFuncTy) }
        shouldSetSRet = !llvmRetTy.isNull() && unsafe { LLVMGetTypeKind(llvmRetTy) } == 0
    }

    if (unsafe { LLVMCountParams(llvmFunc) } > 0u32 && shouldSetSRet) {
        let sretArgType = GetPointerElementType(unsafe { LLVMTypeOf(LLVMGetParam(llvmFunc, 0u32)) })
        AddNoAliasAttribute(llvmFunc)
        AddSRetAttribute(llvmFunc, sretArgType)
    }
}
