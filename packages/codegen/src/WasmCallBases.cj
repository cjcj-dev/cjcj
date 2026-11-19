package cjcj::codegen

import std.collection.*

// Stable LLVM C API opcodes (llvm-c/Core.h).
private let WASM_ROOT_RET: Int32 = 1
private let WASM_ROOT_ALLOCA: Int32 = 26
private let WASM_ROOT_LOAD: Int32 = 27
private let WASM_ROOT_STORE: Int32 = 28
private let WASM_ROOT_BITCAST: Int32 = 41
internal let WASM_ROOT_CALL: Int32 = 45
internal let WASM_CONSTRUCTOR_RESULT_MD = "cj.wasm.constructor_receiver"
private let WASM_ROOT_INVOKE: Int32 = 5
private let WASM_ROOT_RESUME: Int32 = 58
private let WASM_ROOT_LANDINGPAD: Int32 = 59
private let WASM_ROOT_CLEANUPRET: Int32 = 61
private let WASM_ROOT_CATCHSWITCH: Int32 = 65

private func WasmValueName(value: LLVMValueRef): String {
    return LLVMCStringToString(unsafe { LLVMGetValueName(value) }) ?? ""
}

private func CalledWasmName(call: LLVMValueRef): Option<String> {
    let callee = unsafe { LLVMIsAFunction(LLVMGetCalledValue(call)) }
    if (callee.isNull()) { return None }
    return Some(WasmValueName(callee))
}

private func IsWasmAllocation(call: LLVMValueRef): Bool {
    let name = CalledWasmName(call) ?? return false
    return name == MALLOC_OBJECT_INTRINSIC_NAME || name == MALLOC_ARRAY_INTRINSIC_NAME ||
        name == MALLOC_ARRAY_GENERIC_INTRINSIC_NAME
}


private class WasmCallBases {
    private let constructorMetadata = HashMap<UIntNative, UInt32>()
    let arguments = HashSet<UIntNative>()
    let results = HashSet<UIntNative>()

    func AddContext(context: LLVMContextHandle): Unit {
        constructorMetadata[context.raw.toUIntNative()] = LLVMGetMDKindID(context, WASM_CONSTRUCTOR_RESULT_MD)
    }

    func IsConstructorReceiver(call: LLVMValueRef): Bool {
        let context = unsafe {
            let function = LLVMGetBasicBlockParent(LLVMGetInstructionParent(call))
            LLVMGetModuleContext(LLVMGetGlobalParent(function))
        }
        let kind = constructorMetadata.get(context.toUIntNative()) ?? return false
        return !unsafe { LLVMGetMetadata(call, kind) }.isNull()
    }
}

private class WasmLocalCalls {
    let references: ArrayList<LLVMValueRef>
    let arguments = ArrayList<(UInt32, LLVMValueRef)>()
    let returns = ArrayList<LLVMValueRef>()
    let callers: Option<ArrayList<LLVMValueRef>>

    init(function: LLVMValueRef, references: ArrayList<LLVMValueRef>) {
        this.references = references
        let count = unsafe { LLVMCountParams(function) }
        for (index in 0u32..count) {
            let argument = unsafe { LLVMGetParam(function, index) }
            if (IsWasmManagedPointer(unsafe { LLVMTypeOf(argument) })) {
                this.arguments.add((index, argument))
            }
        }
        this.callers = if (this.arguments.isEmpty()) { None } else { FindWasmDirectCallers(references, count) }
        if (AllWasmReferencesReturnManaged(references)) {
            var block = unsafe { LLVMGetFirstBasicBlock(function) }
            while (!block.isNull()) {
                let terminator = unsafe { LLVMGetBasicBlockTerminator(block) }
                if (!terminator.isNull() && unsafe { LLVMGetInstructionOpcode(terminator) } == WASM_ROOT_RET) {
                    this.returns.add(unsafe { LLVMGetOperand(terminator, 0u32) })
                }
                block = unsafe { LLVMGetNextBasicBlock(block) }
            }
        }
    }
}

private func AllWasmReferencesReturnManaged(references: ArrayList<LLVMValueRef>): Bool {
    for (reference in references) {
        if (!IsWasmManagedPointer(unsafe { LLVMGetReturnType(LLVMGlobalGetValueType(reference)) })) {
            return false
        }
    }
    return true
}

// Reject aliases, function pointers, invoke, varargs and operand bundles. Every
// declaration of a localized symbol participates in the call census.
// CallBase puts ordinary arguments first and the callee last.
private func FindWasmDirectCallers(references: ArrayList<LLVMValueRef>, count: UInt32): Option<ArrayList<LLVMValueRef>> {
    let calls = ArrayList<LLVMValueRef>()
    for (function in references) {
        if (unsafe {
            LLVMCountParams(function) != count || LLVMIsFunctionVarArg(LLVMGlobalGetValueType(function)) != 0
        }) { return None }
        let key = function.toUIntNative()
        var useRef = unsafe { LLVMGetFirstUse(function) }
        while (!useRef.isNull()) {
            let user = unsafe { LLVMGetUser(useRef) }
            if (unsafe { LLVMIsAInstruction(user) }.isNull() ||
                unsafe { LLVMGetInstructionOpcode(user) } != WASM_ROOT_CALL ||
                unsafe { LLVMGetCalledValue(user) }.toUIntNative() != key ||
                Int64(unsafe { LLVMGetNumOperands(user) }) != Int64(count) + 1) { return None }
            for (index in 0u32..count) {
                if (unsafe { LLVMGetOperand(user, index) }.toUIntNative() == key) { return None }
            }
            calls.add(user)
            useRef = unsafe { LLVMGetNextUse(useRef) }
        }
    }
    return if (calls.isEmpty()) { None } else { Some(calls) }
}

private func IsWasmKnownBase(value: LLVMValueRef, bases: WasmCallBases): Bool {
    var current = value
    while (!current.isNull() && IsWasmManagedPointer(unsafe { LLVMTypeOf(current) })) {
        if (bases.arguments.contains(current.toUIntNative()) ||
            !unsafe { LLVMIsAConstantPointerNull(current) }.isNull()) { return true }
        if (unsafe { LLVMIsAInstruction(current) }.isNull()) { return false }
        let opcode = unsafe { LLVMGetInstructionOpcode(current) }
        if (opcode == WASM_ROOT_CALL) {
            if (IsWasmAllocation(current) ||
                bases.results.contains(unsafe { LLVMGetCalledValue(current) }.toUIntNative())) { return true }
            if (!bases.IsConstructorReceiver(current)) { return false }
            // This constructor forwards a managed receiver, which is a base
            // only if the producer can prove that its incoming object is one.
        } else if (opcode != WASM_ROOT_BITCAST) {
            return false
        }
        current = unsafe { LLVMGetOperand(current, 0u32) }
    }
    return false
}

// Unoptimized CJ can return a managed value through a local result slot.
// An entry store must dominate the reads and every store must write a known
// base or null. Reject non-scalar slots, aliases and escapes.
private func IsWasmBaseFromReturnSlot(load: LLVMValueRef, bases: WasmCallBases): Bool {
    if (!IsWasmManagedPointer(unsafe { LLVMTypeOf(load) }) || unsafe { LLVMIsAInstruction(load) }.isNull() ||
        unsafe { LLVMGetInstructionOpcode(load) } != WASM_ROOT_LOAD) { return false }
    let slot = unsafe { LLVMGetOperand(load, 0u32) }
    if (unsafe { LLVMIsAInstruction(slot) }.isNull() ||
        unsafe { LLVMGetInstructionOpcode(slot) } != WASM_ROOT_ALLOCA ||
        !IsWasmManagedPointer(unsafe { LLVMGetAllocatedType(slot) })) { return false }
    let entry = unsafe { LLVMGetInstructionParent(slot) }
    if (entry.toUIntNative() != unsafe { LLVMGetEntryBasicBlock(LLVMGetBasicBlockParent(entry)) }.toUIntNative()) {
        return false
    }
    let key = slot.toUIntNative()
    var initialized = false
    var inst = unsafe { LLVMGetNextInstruction(slot) }
    while (!inst.isNull()) {
        let opcode = unsafe { LLVMGetInstructionOpcode(inst) }
        if (opcode == WASM_ROOT_STORE && unsafe { LLVMGetOperand(inst, 1u32) }.toUIntNative() == key) {
            initialized = true
            break
        }
        if (opcode == WASM_ROOT_LOAD && unsafe { LLVMGetOperand(inst, 0u32) }.toUIntNative() == key) { return false }
        inst = unsafe { LLVMGetNextInstruction(inst) }
    }
    if (!initialized) { return false }
    var useRef = unsafe { LLVMGetFirstUse(slot) }
    while (!useRef.isNull()) {
        let user = unsafe { LLVMGetUser(useRef) }
        if (unsafe { LLVMIsAInstruction(user) }.isNull()) { return false }
        let opcode = unsafe { LLVMGetInstructionOpcode(user) }
        if (opcode == WASM_ROOT_STORE) {
            if (unsafe { LLVMGetOperand(user, 1u32) }.toUIntNative() != key ||
                !IsWasmKnownBase(unsafe { LLVMGetOperand(user, 0u32) }, bases)) { return false }
        } else if (opcode != WASM_ROOT_LOAD || unsafe { LLVMGetOperand(user, 0u32) }.toUIntNative() != key) {
            return false
        }
        useRef = unsafe { LLVMGetNextUse(useRef) }
    }
    return true
}

private func AllWasmReturnsAreBases(values: ArrayList<LLVMValueRef>, bases: WasmCallBases): Bool {
    if (values.isEmpty()) { return false }
    for (value in values) {
        if (!IsWasmKnownBase(value, bases) && !IsWasmBaseFromReturnSlot(value, bases)) { return false }
    }
    return true
}

private func AllWasmInputsAreBases(calls: ArrayList<LLVMValueRef>, index: UInt32, bases: WasmCallBases): Bool {
    for (call in calls) {
        if (!IsWasmKnownBase(unsafe { LLVMGetOperand(call, index) }, bases)) { return false }
    }
    return true
}

private class WasmLocalizedFunction {
    let references = ArrayList<LLVMValueRef>()
    var definition = LLVMNullValue()
    var ambiguous = false

    func Add(function: LLVMValueRef, linkage: Int32, declaration: Bool): Unit {
        references.add(function)
        // A weak, linkonce or duplicate definition can resolve differently.
        if (linkage != LLVMLinkageValue(LLVMLinkage.External) || (!declaration && !definition.isNull())) {
            ambiguous = true
        }
        if (!declaration) { definition = function }
    }
}

private func AddWasmSummary(definitions: ArrayList<WasmLocalCalls>, function: LLVMValueRef,
    references: ArrayList<LLVMValueRef>): Unit {
    if (HasWasmUnwind(function)) { return }
    let summary = WasmLocalCalls(function, references)
    if (!summary.returns.isEmpty() || summary.callers.isSome()) { definitions.add(summary) }
}

// The driver combines this package's object partitions before localizing
// exactly these symbols. Only a unique strong definition in that set can
// supply facts across partitions; unrelated externals remain unknown.
private func InferWasmCallBases(modules: ArrayList<CGModule>, localizedNames: HashSet<String>): WasmCallBases {
    let bases = WasmCallBases()
    let definitions = ArrayList<WasmLocalCalls>()
    let localized = HashMap<String, WasmLocalizedFunction>()
    for (cgMod in modules) {
        let module = cgMod.GetLLVMModule().getOrThrow()
        bases.AddContext(cgMod.GetLLVMContext())
        var function = unsafe { LLVMGetFirstFunction(module.raw) }
        while (!function.isNull()) {
            let linkage = unsafe { LLVMGetLinkage(function) }
            let declaration = unsafe { LLVMIsDeclaration(function) } != 0
            if (linkage == LLVMLinkageValue(LLVMLinkage.Internal) ||
                linkage == LLVMLinkageValue(LLVMLinkage.Private)) {
                if (!declaration) { AddWasmSummary(definitions, function, ArrayList<LLVMValueRef>([function])) }
            } else {
                let name = WasmValueName(function)
                if (localizedNames.contains(name)) {
                    let local = localized.get(name) ?? WasmLocalizedFunction()
                    localized[name] = local
                    local.Add(function, linkage, declaration)
                }
            }
            function = unsafe { LLVMGetNextFunction(function) }
        }
    }
    for ((_, local) in localized) {
        if (!local.ambiguous && !local.definition.isNull()) {
            AddWasmSummary(definitions, local.definition, local.references)
        }
    }
    // Start with known allocations/null and grow only supported base facts.
    var changed = true
    while (changed) {
        changed = false
        for (summary in definitions) {
            let key = summary.references[0].toUIntNative()
            if (!bases.results.contains(key) && AllWasmReturnsAreBases(summary.returns, bases)) {
                for (reference in summary.references) { bases.results.add(reference.toUIntNative()) }
                changed = true
            }
            if (let Some(calls) <- summary.callers) {
                for ((index, argument) in summary.arguments) {
                    let argKey = argument.toUIntNative()
                    if (!bases.arguments.contains(argKey) && AllWasmInputsAreBases(calls, index, bases)) {
                        bases.arguments.add(argKey)
                        changed = true
                    }
                }
            }
        }
    }
    return bases
}

// A personality is attached even to ordinary CJ functions. Do not infer
// facts for functions with actual exceptional edges from the normal call census.
private func HasWasmUnwind(function: LLVMValueRef): Bool {
    if (unsafe { LLVMHasPersonalityFn(function) } == 0) { return false }
    var block = unsafe { LLVMGetFirstBasicBlock(function) }
    while (!block.isNull()) {
        var inst = unsafe { LLVMGetFirstInstruction(block) }
        while (!inst.isNull()) {
            let opcode = unsafe { LLVMGetInstructionOpcode(inst) }
            if (opcode == WASM_ROOT_INVOKE || opcode == WASM_ROOT_RESUME || opcode == WASM_ROOT_LANDINGPAD ||
                (opcode >= WASM_ROOT_CLEANUPRET && opcode <= WASM_ROOT_CATCHSWITCH)) { return true }
            inst = unsafe { LLVMGetNextInstruction(inst) }
        }
        block = unsafe { LLVMGetNextBasicBlock(block) }
    }
    return false
}

private let WASM_BASE_ATTRIBUTE = "cj.wasm.base"

internal func EmitWasmBaseAttributes(modules: ArrayList<CGModule>, localizedNames: HashSet<String>): Unit {
    let bases = InferWasmCallBases(modules, localizedNames)
    for (cgMod in modules) {
        let module = cgMod.GetLLVMModule().getOrThrow()
        var function = unsafe { LLVMGetFirstFunction(module.raw) }
        while (!function.isNull()) {
            if (bases.results.contains(function.toUIntNative())) {
                AddStringAttributeAtIndex(function, 0u32, WASM_BASE_ATTRIBUTE)
            }
            if (unsafe { LLVMIsDeclaration(function) } == 0) {
                let count = unsafe { LLVMCountParams(function) }
                for (index in 0u32..count) {
                    let param = unsafe { LLVMGetParam(function, index) }
                    if (bases.arguments.contains(param.toUIntNative())) {
                        AddStringAttributeAtIndex(function, index + 1u32, WASM_BASE_ATTRIBUTE)
                    }
                }
            }
            function = unsafe { LLVMGetNextFunction(function) }
        }
    }
}
