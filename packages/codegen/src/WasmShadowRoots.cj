package cjcj::codegen

import std.collection.*
import std.process.Process

// Stable LLVM C API opcodes (llvm-c/Core.h).
private let WASM_ROOT_RET: Int32 = 1
private let WASM_ROOT_ALLOCA: Int32 = 26
private let WASM_ROOT_LOAD: Int32 = 27
private let WASM_ROOT_STORE: Int32 = 28
private let WASM_ROOT_BITCAST: Int32 = 41
private let WASM_ROOT_ICMP: Int32 = 42
internal let WASM_ROOT_CALL: Int32 = 45
internal let WASM_CONSTRUCTOR_RESULT_MD = "cj.wasm.constructor_receiver"
private let WASM_ROOT_INVOKE: Int32 = 5
private let WASM_ROOT_RESUME: Int32 = 58
private let WASM_ROOT_LANDINGPAD: Int32 = 59
private let WASM_ROOT_CLEANUPRET: Int32 = 61
private let WASM_ROOT_CATCHSWITCH: Int32 = 65

private class WasmRootSpill {
    let base: LLVMValueRef
    let initializeBefore: LLVMValueRef
    var address = LLVMNullValue()
    var needed = false

    init(base: LLVMValueRef, initializeBefore: LLVMValueRef) {
        this.base = base
        this.initializeBefore = initializeBefore
    }
}

private class WasmLocalRoot {
    let base: LLVMValueRef
    let defIndex: Int64
    let lastUse: Int64
    let spill: Option<WasmRootSpill>
    var current: LLVMValueRef

    init(base: LLVMValueRef, defIndex: Int64, lastUse: Int64, spill: Option<WasmRootSpill>) {
        this.base = base
        this.defIndex = defIndex
        this.lastUse = lastUse
        this.spill = spill
        this.current = base
    }
}

private class WasmCallRoots {
    let callIndex: Int64
    let roots: ArrayList<WasmLocalRoot>

    init(callIndex: Int64, roots: ArrayList<WasmLocalRoot>) {
        this.callIndex = callIndex
        this.roots = roots
    }
}

private class WasmBlockRoots {
    let block: LLVMBasicBlockRef
    let instructions: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()
    let predecessors = ArrayList<Int64>()
    let candidates = ArrayList<WasmLocalRoot>()
    let sites: ArrayList<WasmCallRoots> = ArrayList<WasmCallRoots>()
    let owners: HashMap<UIntNative, WasmLocalRoot> = HashMap<UIntNative, WasmLocalRoot>()

    init(block: LLVMBasicBlockRef) {
        this.block = block
    }
}

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


internal class WasmCallBases {
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
        let functionType = unsafe { LLVMGlobalGetValueType(function) }
        if (IsWasmManagedPointer(unsafe { LLVMGetReturnType(functionType) })) {
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
internal func InferWasmCallBases(modules: ArrayList<CGModule>, localizedNames: HashSet<String>): WasmCallBases {
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

private func IsWasmRootCall(call: LLVMValueRef): Bool {
    if (unsafe { LLVMIsTailCall(call) } != 0) { return false }
    let name = CalledWasmName(call) ?? return true
    // Native LLVM intrinsics such as llvm.dbg.* and llvm.lifetime.* do not
    // allocate managed objects. CJ intrinsics can lower to runtime calls.
    return !name.startsWith("llvm.") || name.startsWith("llvm.cj.")
}

// Only follow aliases that still name the start of the object. A GEP, phi,
// memory escape or other unmodelled use stops the proof for the whole value.
private func CollectWasmRootUses(aliases: ArrayList<LLVMValueRef>, uses: HashMap<Int64, Int64>,
    positions: HashMap<UIntNative, (Int64, Int64)>): Bool {
    let seen = HashSet<UIntNative>()
    seen.add(aliases[0].toUIntNative())
    var i: Int64 = 0
    while (i < aliases.size) {
        let alias = aliases[i]
        var useRef = unsafe { LLVMGetFirstUse(alias) }
        while (!useRef.isNull()) {
            let user = unsafe { LLVMGetUser(useRef) }
            let (block, index) = positions.get(user.toUIntNative()) ?? return false
            let opcode = unsafe { LLVMGetInstructionOpcode(user) }
            if (opcode == WASM_ROOT_BITCAST && IsWasmManagedPointer(unsafe { LLVMTypeOf(user) })) {
                if (!seen.contains(user.toUIntNative())) {
                    seen.add(user.toUIntNative())
                    aliases.add(user)
                }
            } else if (opcode != WASM_ROOT_CALL && opcode != WASM_ROOT_ICMP && opcode != WASM_ROOT_LOAD &&
                opcode != WASM_ROOT_RET &&
                !(opcode == WASM_ROOT_STORE &&
                    unsafe { LLVMGetOperand(user, 0u32).toUIntNative() } != alias.toUIntNative())) {
                return false
            }
            if (index > (uses.get(block) ?? -1)) { uses[block] = index }
            useRef = unsafe { LLVMGetNextUse(useRef) }
        }
        i++
    }
    return !uses.isEmpty()
}

private func CollectWasmRootBlocks(entry: LLVMBasicBlockRef, plans: ArrayList<WasmBlockRoots>,
    positions: HashMap<UIntNative, (Int64, Int64)>): Unit {
    let blocks = HashMap<UIntNative, Int64>()
    blocks[entry.toUIntNative()] = 0
    plans.add(WasmBlockRoots(entry))
    var i: Int64 = 0
    while (i < plans.size) {
        let plan = plans[i]
        var inst = unsafe { LLVMGetFirstInstruction(plan.block) }
        while (!inst.isNull()) {
            positions[inst.toUIntNative()] = (i, plan.instructions.size)
            plan.instructions.add(inst)
            inst = unsafe { LLVMGetNextInstruction(inst) }
        }
        let term = unsafe { LLVMGetBasicBlockTerminator(plan.block) }
        let count = unsafe { LLVMGetNumSuccessors(term) }
        for (j in 0u32..count) {
            let successor = unsafe { LLVMGetSuccessor(term, j) }
            let key = successor.toUIntNative()
            let next = if (let Some(existing) <- blocks.get(key)) {
                existing
            } else {
                let index = plans.size
                blocks[key] = index
                plans.add(WasmBlockRoots(successor))
                index
            }
            plans[next].predecessors.add(i)
        }
        i++
    }
}

private func PlanWasmValue(base: LLVMValueRef, defBlock: Int64, defIndex: Int64,
    plans: ArrayList<WasmBlockRoots>, positions: HashMap<UIntNative, (Int64, Int64)>,
    spills: ArrayList<WasmRootSpill>): Unit {
    let aliases = ArrayList<LLVMValueRef>([base])
    let uses = HashMap<Int64, Int64>()
    if (!CollectWasmRootUses(aliases, uses, positions)) { return }

    var spill: Option<WasmRootSpill> = None
    if (uses.size > 1 || uses.get(defBlock).isNone()) {
        // SSA dominance holds for all accepted uses (no PHIs). Walk backwards
        // from those uses; a path through the definition kills the old value.
        // The entry-reachable graph excludes dead predecessors.
        let work = ArrayList<Int64>()
        for ((block, _) in uses) { work.add(block) }
        let liveIn = HashSet<Int64>()
        var i: Int64 = 0
        while (i < work.size) {
            let block = work[i]
            if (block != defBlock && !liveIn.contains(block)) {
                liveIn.add(block)
                for (pred in plans[block].predecessors) {
                    uses[pred] = plans[pred].instructions.size
                    work.add(pred)
                }
            }
            i++
        }
        let storage = WasmRootSpill(base, plans[defBlock].instructions[defIndex + 1])
        spills.add(storage)
        spill = Some(storage)
    }
    for ((block, lastUse) in uses) {
        let plan = plans[block]
        let start = if (block == defBlock) { defIndex } else { -1 }
        let root = WasmLocalRoot(base, start, lastUse, spill)
        plan.candidates.add(root)
        for (alias in aliases) { plan.owners[alias.toUIntNative()] = root }
    }
}

private func PlanWasmBlockSites(plan: WasmBlockRoots, trace: Bool): Unit {
    if (trace) {
        let name = LLVMCStringToString(unsafe { LLVMGetBasicBlockName(plan.block) }) ?? ""
        eprintln("CJCJ_WASM_ROOTS block=${name} instructions=${plan.instructions.size} candidates=${plan.candidates.size}")
    }
    for (i in 0..plan.instructions.size) {
        let call = plan.instructions[i]
        if (unsafe { LLVMGetInstructionOpcode(call) } != WASM_ROOT_CALL || !IsWasmRootCall(call)) { continue }
        let live = ArrayList<WasmLocalRoot>()
        for (root in plan.candidates) {
            // A call's result is unavailable until it returns. An argument
            // used at the call is live during it, even with no later use.
            if (root.defIndex < i && root.lastUse >= i) {
                live.add(root)
                if (let Some(spill) <- root.spill) { spill.needed = true }
            }
        }
        if (!live.isEmpty()) { plan.sites.add(WasmCallRoots(i, live)) }
        if (trace) {
            let name = CalledWasmName(call) ?? "indirect"
            eprintln("CJCJ_WASM_ROOTS call=${name} i=${i} roots=${live.size}")
        }
    }
}

// A personality is attached even to ordinary CJ functions. Reject actual
// unwinding edges until lowering can restore the shadow top on those edges.
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

internal func EmitWasmShadowRoots(cgMod: CGModule, module: LLVMModuleHandle, builder: IRBuilder2,
    bases: WasmCallBases): Unit {
    let filter = Process.current.getEnv("CJCJ_WASM_ROOTS_TRACE") ?? ""
    var function = unsafe { LLVMGetFirstFunction(module.raw) }
    while (!function.isNull()) {
        let next = unsafe { LLVMGetNextFunction(function) }
        if (unsafe { LLVMIsDeclaration(function) == 0 }) {
            let unwind = HasWasmUnwind(function)
            let trace = !filter.isEmpty() && WasmValueName(function).contains(filter)
            if (trace) { eprintln("CJCJ_WASM_ROOTS function=${WasmValueName(function)} unwind=${unwind}") }
            if (!unwind) { LowerWasmFunctionRoots(cgMod, builder, function, bases, trace) }
        }
        function = next
    }
}

private func LowerWasmFunctionRoots(cgMod: CGModule, builder: IRBuilder2, function: LLVMValueRef,
    bases: WasmCallBases, trace: Bool): Unit {
    let plans = ArrayList<WasmBlockRoots>()
    let positions = HashMap<UIntNative, (Int64, Int64)>()
    let spills = ArrayList<WasmRootSpill>()
    var capacity: Int64 = 0
    let entry = unsafe { LLVMGetEntryBasicBlock(function) }
    CollectWasmRootBlocks(entry, plans, positions)
    let count = unsafe { LLVMCountParams(function) }
    for (index in 0u32..count) {
        let argument = unsafe { LLVMGetParam(function, index) }
        if (bases.arguments.contains(argument.toUIntNative())) {
            PlanWasmValue(argument, 0, -1, plans, positions, spills)
        }
    }
    for (block in 0..plans.size) {
        let plan = plans[block]
        for (i in 0..plan.instructions.size) {
            let call = plan.instructions[i]
            if (unsafe { LLVMGetInstructionOpcode(call) } == WASM_ROOT_CALL && IsWasmKnownBase(call, bases)) {
                PlanWasmValue(call, block, i, plans, positions, spills)
            }
        }
    }
    for (plan in plans) {
        PlanWasmBlockSites(plan, trace)
        for (site in plan.sites) {
            if (site.roots.size > capacity) { capacity = site.roots.size }
        }
    }
    if (capacity == 0) { return }

    let context = cgMod.GetLLVMContext().raw
    let bytePtr = unsafe { LLVMPointerType(LLVMInt8TypeInContext(context), 0u32) }
    let slotsType = unsafe { LLVMArrayType(bytePtr, UInt32(capacity)) }
    // Match CjwRootFrame {prev@0, funcDesc@4, nslots@8, slots@12}. The ABI
    // record is C memory. Access each payload slot through its managed
    // pointer type to avoid casting the reference itself out of AS1.
    let frameType = WasmStructType(context, [bytePtr, bytePtr, unsafe { LLVMInt32TypeInContext(context) },
        slotsType])
    let hookType = CGType.GetCodeGenFunctionType(cgMod.GetLLVMContext(), unsafe { LLVMVoidTypeInContext(context) },
        ArrayList<LLVMTypeRef>([bytePtr]))
    let push = cgMod.GetOrInsertFunction("cjw_root_frame_push", hookType)
    let pop = cgMod.GetOrInsertFunction("cjw_root_frame_pop", hookType)
    let first = plans[0].instructions[0]
    builder.SetInsertPointBefore(first)
    let frame = builder.CreateAllocaAtCurrentPoint(frameType, "wasm.root.frame")
    // A cross-block spill carries the latest post-call reload across incoming
    // edges. Only the frame slots, never these spills, are published to C6.
    for (spill in spills) {
        if (!spill.needed) { continue }
        builder.SetInsertPointBefore(first)
        spill.address = builder.CreateAllocaAtCurrentPoint(unsafe { LLVMTypeOf(spill.base) }, "wasm.root.spill")
        builder.SetInsertPointBefore(spill.initializeBefore)
        builder.CreateStore(spill.base, spill.address)
    }
    for (plan in plans) {
        if (!plan.owners.isEmpty()) {
            LowerWasmBlockRoots(builder, plan, frame, frameType, slotsType, bytePtr, hookType, push, pop)
        }
    }
}

private func CurrentWasmRoot(builder: IRBuilder2, root: WasmLocalRoot): LLVMValueRef {
    if (let Some(spill) <- root.spill) {
        if (!spill.address.isNull()) {
            return builder.CreateLoad(unsafe { LLVMTypeOf(root.base) }, spill.address, name: "wasm.root.current")
        }
    }
    return root.current
}

private func LowerWasmBlockRoots(builder: IRBuilder2, plan: WasmBlockRoots, frame: LLVMValueRef,
    frameType: LLVMTypeRef, slotsType: LLVMTypeRef, bytePtr: LLVMTypeRef, hookType: LLVMTypeRef,
    push: LLVMValueRef, pop: LLVMValueRef): Unit {
    var siteIndex: Int64 = 0
    var i: Int64 = 0
    while (i < plan.instructions.size) {
        let inst = plan.instructions[i]
        builder.SetInsertPointBefore(inst)
        let count = Int64(unsafe { LLVMGetNumOperands(inst) })
        for (op in 0..count) {
            let value = unsafe { LLVMGetOperand(inst, UInt32(op)) }
            if (let Some(root) <- plan.owners.get(value.toUIntNative())) {
                let current = CurrentWasmRoot(builder, root)
                if (current.toUIntNative() != root.base.toUIntNative()) {
                    let fresh = builder.CreateBitCast(current, unsafe { LLVMTypeOf(value) })
                    unsafe { LLVMSetOperand(inst, UInt32(op), fresh) }
                }
            }
        }
        if (siteIndex < plan.sites.size && plan.sites[siteIndex].callIndex == i) {
            let site = plan.sites[siteIndex]
            let args = ArrayList<LLVMValueRef>([builder.CreateBitCast(frame, bytePtr)])
            builder.CreateStore(unsafe { LLVMConstNull(bytePtr) }, builder.CreateStructGEP(frameType, frame, 1u32))
            builder.CreateStore(builder.GetInt32(site.roots.size), builder.CreateStructGEP(frameType, frame, 2u32))
            let slots = builder.CreateStructGEP(frameType, frame, 3u32)
            let addresses = ArrayList<LLVMValueRef>()
            for (idx in 0..site.roots.size) {
                let root = site.roots[idx]
                let address = builder.CreateInBoundsGEP(slotsType, slots,
                    ArrayList<LLVMValueRef>([builder.GetInt32(0), builder.GetInt32(idx)]))
                let typedAddress = builder.CreateBitCast(address, unsafe { LLVMPointerType(LLVMTypeOf(root.base), 0u32) })
                addresses.add(typedAddress)
                builder.CreateStore(CurrentWasmRoot(builder, root), typedAddress, isVolatile: true)
            }
            builder.CreateCall(push, hookType, args)
            builder.SetInsertPointBefore(plan.instructions[i + 1])
            for (idx in 0..site.roots.size) {
                let root = site.roots[idx]
                if (root.lastUse > i) {
                    let reload = builder.CreateLoad(unsafe { LLVMTypeOf(root.base) }, addresses[idx],
                        name: "wasm.root.reload")
                    unsafe { LLVMSetVolatile(reload, 1) }
                    if (let Some(spill) <- root.spill) {
                        builder.CreateStore(reload, spill.address)
                    } else {
                        root.current = reload
                    }
                }
            }
            builder.CreateCall(pop, hookType, args)
            siteIndex++
        }
        i++
    }
}
