package cjcj::codegen

import std.collection.*

// Stable LLVM C API opcodes (llvm-c/Core.h).
private let WASM_ROOT_RET: Int32 = 1
private let WASM_ROOT_LOAD: Int32 = 27
private let WASM_ROOT_STORE: Int32 = 28
private let WASM_ROOT_BITCAST: Int32 = 41
private let WASM_ROOT_ICMP: Int32 = 42
private let WASM_ROOT_CALL: Int32 = 45

private class WasmLocalRoot {
    let base: LLVMValueRef
    let aliases: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()
    var lastUse: Int64
    var current: LLVMValueRef

    init(base: LLVMValueRef, index: Int64) {
        this.base = base
        this.lastUse = index
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
    let instructions: ArrayList<LLVMValueRef> = ArrayList<LLVMValueRef>()
    let sites: ArrayList<WasmCallRoots> = ArrayList<WasmCallRoots>()
    let owners: HashMap<UIntNative, WasmLocalRoot> = HashMap<UIntNative, WasmLocalRoot>()
}

private func CalledWasmName(call: LLVMValueRef): Option<String> {
    let callee = unsafe { LLVMIsAFunction(LLVMGetCalledValue(call)) }
    if (callee.isNull()) { return None }
    return Some(LLVMCStringToString(unsafe { LLVMGetValueName(callee) }) ?? "")
}

private func IsWasmAllocation(call: LLVMValueRef): Bool {
    let name = CalledWasmName(call) ?? return false
    return name == MALLOC_OBJECT_INTRINSIC_NAME || name == MALLOC_ARRAY_INTRINSIC_NAME ||
        name == MALLOC_ARRAY_GENERIC_INTRINSIC_NAME
}

private func IsWasmRootCall(call: LLVMValueRef): Bool {
    if (unsafe { LLVMIsTailCall(call) } != 0) { return false }
    let name = CalledWasmName(call) ?? return true
    // Native LLVM intrinsics such as llvm.dbg.* and llvm.lifetime.* do not
    // allocate managed objects. CJ intrinsics can lower to runtime calls.
    return !name.startsWith("llvm.") || name.startsWith("llvm.cj.")
}

// A first, local liveness case: a recognized heap allocation, with all uses
// in the defining block, including uses of address-preserving bitcasts.
// Following arbitrary AS1 values would also pick up derived pointers. A GEP,
// phi, memory escape, or other unmodelled use stops this proof for the value.
// Argument-only use of a base at a call counts: the callee may allocate before
// the caller gets control back, even if the caller will not read it again.
private func FindWasmLocalRoot(base: LLVMValueRef, defIndex: Int64,
    positions: HashMap<UIntNative, Int64>): Option<WasmLocalRoot> {
    let root = WasmLocalRoot(base, defIndex)
    let seen = HashSet<UIntNative>()
    root.aliases.add(base)
    seen.add(base.toUIntNative())
    var i: Int64 = 0
    while (i < root.aliases.size) {
        let alias = root.aliases[i]
        var useRef = unsafe { LLVMGetFirstUse(alias) }
        while (!useRef.isNull()) {
            let user = unsafe { LLVMGetUser(useRef) }
            let useIndex = positions.get(user.toUIntNative()) ?? return None
            let opcode = unsafe { LLVMGetInstructionOpcode(user) }
            if (opcode == WASM_ROOT_BITCAST && IsWasmManagedPointer(unsafe { LLVMTypeOf(user) })) {
                if (!seen.contains(user.toUIntNative())) {
                    seen.add(user.toUIntNative())
                    root.aliases.add(user)
                }
            } else if (opcode != WASM_ROOT_CALL && opcode != WASM_ROOT_ICMP && opcode != WASM_ROOT_LOAD &&
                opcode != WASM_ROOT_RET &&
                !(opcode == WASM_ROOT_STORE &&
                    unsafe { LLVMGetOperand(user, 0u32).toUIntNative() } != alias.toUIntNative())) {
                return None
            }
            if (useIndex > root.lastUse) { root.lastUse = useIndex }
            useRef = unsafe { LLVMGetNextUse(useRef) }
        }
        i++
    }
    return Some(root)
}

private func PlanWasmBlockRoots(block: LLVMBasicBlockRef): WasmBlockRoots {
    let plan = WasmBlockRoots()
    let positions = HashMap<UIntNative, Int64>()
    var inst = unsafe { LLVMGetFirstInstruction(block) }
    while (!inst.isNull()) {
        positions[inst.toUIntNative()] = plan.instructions.size
        plan.instructions.add(inst)
        inst = unsafe { LLVMGetNextInstruction(inst) }
    }
    let candidates = ArrayList<WasmLocalRoot>()
    for (i in 0..plan.instructions.size) {
        let call = plan.instructions[i]
        if (unsafe { LLVMGetInstructionOpcode(call) } != WASM_ROOT_CALL) { continue }
        if (IsWasmRootCall(call)) {
            let live = ArrayList<WasmLocalRoot>()
            for (root in candidates) {
                if (root.lastUse >= i) { live.add(root) }
            }
            if (!live.isEmpty()) { plan.sites.add(WasmCallRoots(i, live)) }
        }
        // The result of this call is not live during the call itself.
        if (IsWasmManagedPointer(unsafe { LLVMTypeOf(call) }) && IsWasmAllocation(call)) {
            if (let Some(root) <- FindWasmLocalRoot(call, i, positions)) {
                candidates.add(root)
                for (alias in root.aliases) { plan.owners[alias.toUIntNative()] = root }
            }
        }
    }
    return plan
}

internal func EmitWasmShadowRoots(cgMod: CGModule, module: LLVMModuleHandle, builder: IRBuilder2): Unit {
    var function = unsafe { LLVMGetFirstFunction(module.raw) }
    // The C6 target has no unwinding. Do not instrument functions with an EH
    // personality until the compiler can restore the shadow top on that edge.
    while (!function.isNull()) {
        let next = unsafe { LLVMGetNextFunction(function) }
        if (unsafe { LLVMIsDeclaration(function) == 0 && LLVMHasPersonalityFn(function) == 0 }) {
            LowerWasmFunctionRoots(cgMod, builder, function)
        }
        function = next
    }
}

private func LowerWasmFunctionRoots(cgMod: CGModule, builder: IRBuilder2, function: LLVMValueRef): Unit {
    let plans = ArrayList<WasmBlockRoots>()
    var capacity: Int64 = 0
    var block = unsafe { LLVMGetFirstBasicBlock(function) }
    while (!block.isNull()) {
        let plan = PlanWasmBlockRoots(block)
        if (!plan.sites.isEmpty()) {
            plans.add(plan)
            for (site in plan.sites) {
                if (site.roots.size > capacity) { capacity = site.roots.size }
            }
        }
        block = unsafe { LLVMGetNextBasicBlock(block) }
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
    builder.SetInsertPointBefore(unsafe { LLVMGetFirstInstruction(LLVMGetEntryBasicBlock(function)) })
    let frame = builder.CreateEntryAlloca(frameType, name: "wasm.root.frame")
    for (plan in plans) {
        LowerWasmBlockRoots(builder, plan, frame, frameType, slotsType, bytePtr, hookType, push, pop)
    }
}

private func LowerWasmBlockRoots(builder: IRBuilder2, plan: WasmBlockRoots, frame: LLVMValueRef,
    frameType: LLVMTypeRef, slotsType: LLVMTypeRef, bytePtr: LLVMTypeRef, hookType: LLVMTypeRef,
    push: LLVMValueRef, pop: LLVMValueRef): Unit {
    var siteIndex: Int64 = 0
    var i = plan.sites[0].callIndex
    while (i < plan.instructions.size) {
        let inst = plan.instructions[i]
        builder.SetInsertPointBefore(inst)
        let count = Int64(unsafe { LLVMGetNumOperands(inst) })
        for (op in 0..count) {
            let value = unsafe { LLVMGetOperand(inst, UInt32(op)) }
            if (let Some(root) <- plan.owners.get(value.toUIntNative())) {
                if (root.current.toUIntNative() != root.base.toUIntNative()) {
                    let fresh = builder.CreateBitCast(root.current, unsafe { LLVMTypeOf(value) })
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
                builder.CreateStore(root.current, typedAddress, isVolatile: true)
            }
            builder.CreateCall(push, hookType, args)
            builder.SetInsertPointBefore(plan.instructions[i + 1])
            for (idx in 0..site.roots.size) {
                let root = site.roots[idx]
                if (root.lastUse > i) {
                    let reload = builder.CreateLoad(unsafe { LLVMTypeOf(root.base) }, addresses[idx],
                        name: "wasm.root.reload")
                    unsafe { LLVMSetVolatile(reload, 1) }
                    root.current = reload
                }
            }
            builder.CreateCall(pop, hookType, args)
            siteIndex++
        }
        i++
    }
}
