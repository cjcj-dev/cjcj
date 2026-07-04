package cangjie_compiler::codegen

import std.collection.*

private type LLVMReplaceMDNodeOperandWithFunc = CFunc<(LLVMValueRef, UInt32, LLVMMetadataRef) -> Unit>

public func LLVMNullNamedMDNode(): LLVMNamedMDNodeRef { return CPointer<Unit>() }

private func LLVMGetModuleContextHandle(module: LLVMModuleHandle): Option<LLVMContextHandle> {
    return module.context
}

public func LLVMGetMDKindID(context: LLVMContextHandle, name: String): UInt32 {
    if (context.raw.isNull() || name.isEmpty()) {
        return 0u32
    }
    var result: UInt32 = 0u32
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetMDKindIDInContext(context.raw, nameCString.value, UInt32(name.size)) }
    }
    return result
}

public func LLVMGetGlobalMDKindID(name: String): UInt32 {
    if (name.isEmpty()) {
        return 0u32
    }
    var result: UInt32 = 0u32
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetMDKindID(nameCString.value, UInt32(name.size)) }
    }
    return result
}

public func LLVMCreateMDString(context: LLVMContextHandle, value: String): LLVMMetadataRef {
    if (context.raw.isNull()) {
        return LLVMNullMetadata()
    }
    var result = LLVMNullMetadata()
    try (valueCString = unsafe { LibC.mallocCString(value) }.asResource()) {
        result = unsafe { LLVMMDStringInContext2(context.raw, valueCString.value, UIntNative(value.size)) }
    }
    return result
}

public func LLVMCreateMDTuple(context: LLVMContextHandle, operands: ArrayList<LLVMMetadataRef>): LLVMMetadataRef {
    if (context.raw.isNull()) {
        return LLVMNullMetadata()
    }
    if (operands.isEmpty()) {
        return unsafe { LLVMMDNodeInContext2(context.raw, CPointer<LLVMMetadataRef>(), 0) }
    }
    var result = LLVMNullMetadata()
    try (operandPtr = LibC.malloc<LLVMMetadataRef>(count: operands.size).asResource()) {
        var idx: Int64 = 0
        while (idx < operands.size) {
            unsafe { (operandPtr.value + idx).write(operands[idx]) }
            idx++
        }
        result = unsafe { LLVMMDNodeInContext2(context.raw, operandPtr.value, UIntNative(operands.size)) }
    }
    return result
}

public func LLVMCreateMDTuple(context: LLVMContextHandle, operand: LLVMMetadataRef): LLVMMetadataRef {
    let operands = ArrayList<LLVMMetadataRef>()
    operands.add(operand)
    return LLVMCreateMDTuple(context, operands)
}

public func LLVMCreateMDTupleFromStrings(context: LLVMContextHandle, values: ArrayList<String>): LLVMMetadataRef {
    let operands = ArrayList<LLVMMetadataRef>()
    for (value in values) {
        operands.add(LLVMCreateMDString(context, value))
    }
    return LLVMCreateMDTuple(context, operands)
}

public func LLVMCreateMDTupleFromString(context: LLVMContextHandle, value: String): LLVMMetadataRef {
    return LLVMCreateMDTuple(context, LLVMCreateMDString(context, value))
}

public func LLVMMetadataToValue(context: LLVMContextHandle, metadata: LLVMMetadataRef): LLVMValueRef {
    if (context.raw.isNull() || metadata.isNull()) {
        return LLVMNullValue()
    }
    return unsafe { LLVMMetadataAsValue(context.raw, metadata) }
}

public func LLVMValueToMetadata(value: LLVMValueRef): LLVMMetadataRef {
    if (value.isNull()) {
        return LLVMNullMetadata()
    }
    return unsafe { LLVMValueAsMetadata(value) }
}

public func LLVMGetMDStringValue(value: LLVMValueRef): Option<String> {
    if (value.isNull() || unsafe { LLVMIsAMDString(value) }.isNull()) {
        return None
    }
    var result: Option<String> = None
    try (lenPtr = LibC.malloc<UInt32>().asResource()) {
        unsafe { lenPtr.value.write(0u32) }
        let rawValue = unsafe { LLVMGetMDString(value, lenPtr.value) }
        let valueLen = unsafe { lenPtr.value.read() }
        result = LLVMCStringToString(rawValue, UIntNative(valueLen))
    }
    return result
}

public func LLVMGetMDNodeOperands(value: LLVMValueRef): ArrayList<LLVMValueRef> {
    let operands = ArrayList<LLVMValueRef>()
    if (value.isNull() || unsafe { LLVMIsAMDNode(value) }.isNull()) {
        return operands
    }
    let count = unsafe { LLVMGetMDNodeNumOperands(value) }
    if (count == 0u32) {
        return operands
    }
    try (operandPtr = LibC.malloc<LLVMValueRef>(count: Int64(count)).asResource()) {
        unsafe { LLVMGetMDNodeOperands(value, operandPtr.value) }
        var idx: Int64 = 0
        while (idx < Int64(count)) {
            operands.add(unsafe { (operandPtr.value + idx).read() })
            idx++
        }
    }
    return operands
}

public func LLVMReplaceMDNodeOperand(value: LLVMValueRef, index: UInt32, replacement: LLVMMetadataRef): Unit {
    if (value.isNull() || replacement.isNull()) {
        return
    }
    let symbol = LookupLLVMOptionalSymbol("LLVMReplaceMDNodeOperandWith")
    if (symbol.isNull()) {
        return
    }
    let replaceOperand = LLVMReplaceMDNodeOperandWithFunc(symbol)
    unsafe { replaceOperand(value, index, replacement) }
}

public func LLVMGetNamedMetadata(module: LLVMModuleHandle, name: String): LLVMNamedMDNodeRef {
    if (module.raw.isNull() || name.isEmpty()) {
        return LLVMNullNamedMDNode()
    }
    var result = LLVMNullNamedMDNode()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetNamedMetadata(module.raw, nameCString.value, UIntNative(name.size)) }
    }
    return result
}

public func LLVMGetOrInsertNamedMetadata(module: LLVMModuleHandle, name: String): LLVMNamedMDNodeRef {
    if (module.raw.isNull() || name.isEmpty()) {
        return LLVMNullNamedMDNode()
    }
    var result = LLVMNullNamedMDNode()
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        result = unsafe { LLVMGetOrInsertNamedMetadata(module.raw, nameCString.value, UIntNative(name.size)) }
    }
    return result
}

public func LLVMGetNamedMetadataName(namedMDNode: LLVMNamedMDNodeRef): String {
    if (namedMDNode.isNull()) {
        return ""
    }
    var result = ""
    try (lenPtr = LibC.malloc<UIntNative>().asResource()) {
        unsafe { lenPtr.value.write(0) }
        let rawName = unsafe { LLVMGetNamedMetadataName(namedMDNode, lenPtr.value) }
        result = LLVMCStringToString(rawName, unsafe { lenPtr.value.read() }) ?? ""
    }
    return result
}

public func LLVMGetNamedMetadataNames(module: LLVMModuleHandle): ArrayList<String> {
    let names = ArrayList<String>()
    if (module.raw.isNull()) {
        return names
    }
    var namedMDNode = unsafe { LLVMGetFirstNamedMetadata(module.raw) }
    while (!namedMDNode.isNull()) {
        let name = LLVMGetNamedMetadataName(namedMDNode)
        if (!name.isEmpty()) {
            names.add(name)
        }
        namedMDNode = unsafe { LLVMGetNextNamedMetadata(namedMDNode) }
    }
    return names
}

public func LLVMGetNamedMetadataOperandValues(module: LLVMModuleHandle, name: String): ArrayList<LLVMValueRef> {
    let operands = ArrayList<LLVMValueRef>()
    if (module.raw.isNull() || name.isEmpty()) {
        return operands
    }
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        let count = unsafe { LLVMGetNamedMetadataNumOperands(module.raw, nameCString.value) }
        if (count == 0u32) {
            return operands
        }
        try (operandPtr = LibC.malloc<LLVMValueRef>(count: Int64(count)).asResource()) {
            unsafe { LLVMGetNamedMetadataOperands(module.raw, nameCString.value, operandPtr.value) }
            var idx: Int64 = 0
            while (idx < Int64(count)) {
                operands.add(unsafe { (operandPtr.value + idx).read() })
                idx++
            }
        }
    }
    return operands
}

public func LLVMAddNamedMetadataOperand(module: LLVMModuleHandle, name: String, metadata: LLVMMetadataRef): Unit {
    if (module.raw.isNull() || name.isEmpty() || metadata.isNull()) {
        return
    }
    if (let Some(context) <- LLVMGetModuleContextHandle(module)) {
        let metadataValue = LLVMMetadataToValue(context, metadata)
        if (metadataValue.isNull()) {
            return
        }
        try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
            unsafe { LLVMAddNamedMetadataOperand(module.raw, nameCString.value, metadataValue) }
        }
    }
}

public func LLVMAddNamedMetadataStringOperand(module: LLVMModuleHandle, name: String, value: String): Unit {
    if (let Some(context) <- LLVMGetModuleContextHandle(module)) {
        LLVMAddNamedMetadataOperand(module, name, LLVMCreateMDTupleFromString(context, value))
    }
}

public func LLVMSetInstructionMetadata(context: LLVMContextHandle, value: LLVMValueRef, name: String,
    metadata: LLVMMetadataRef): Unit {
    if (value.isNull() || metadata.isNull()) {
        return
    }
    if (context.raw.isNull() || name.isEmpty()) {
        return
    }
    try (nameCString = unsafe { LibC.mallocCString(name) }.asResource()) {
        unsafe { LLVMSelfhostInstructionSetMetadata(value, nameCString.value, UInt32(name.size), metadata) }
    }
}

public func LLVMEraseInstructionMetadata(context: LLVMContextHandle, value: LLVMValueRef, name: String): Unit {
    if (value.isNull()) {
        return
    }
    let kindID = LLVMGetMDKindID(context, name)
    if (kindID != 0u32) {
        unsafe { LLVMSetMetadata(value, kindID, LLVMNullValue()) }
    }
}

public func LLVMHasInstructionMetadata(value: LLVMValueRef): Bool {
    return !value.isNull() && unsafe { LLVMHasMetadata(value) } != 0
}

public func LLVMGetInstructionMetadata(context: LLVMContextHandle, value: LLVMValueRef,
    name: String): Option<LLVMValueRef> {
    if (value.isNull()) {
        return None
    }
    let kindID = LLVMGetMDKindID(context, name)
    if (kindID == 0u32) {
        return None
    }
    let metadataValue = unsafe { LLVMGetMetadata(value, kindID) }
    if (metadataValue.isNull()) {
        return None
    }
    return Some(metadataValue)
}

public func LLVMSetGlobalMetadata(context: LLVMContextHandle, global: LLVMValueRef, name: String,
    metadata: LLVMMetadataRef): Unit {
    if (global.isNull() || metadata.isNull()) {
        return
    }
    let kindID = LLVMGetMDKindID(context, name)
    if (kindID != 0u32) {
        unsafe { LLVMGlobalSetMetadata(global, kindID, metadata) }
    }
}

public func LLVMEraseGlobalMetadata(context: LLVMContextHandle, global: LLVMValueRef, name: String): Unit {
    if (global.isNull()) {
        return
    }
    let kindID = LLVMGetMDKindID(context, name)
    if (kindID != 0u32) {
        unsafe { LLVMGlobalEraseMetadata(global, kindID) }
    }
}

public func LLVMSetGlobalStringMetadata(context: LLVMContextHandle, global: LLVMValueRef, name: String,
    value: String): Unit {
    LLVMSetGlobalMetadata(context, global, name, LLVMCreateMDTupleFromString(context, value))
}
