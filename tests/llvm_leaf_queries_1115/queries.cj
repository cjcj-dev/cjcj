package cjcj::codegen

import std.runtime.*
import std.sync.*

// Compile together with packages/codegen/src/LLVM.cj. Do not redeclare its APIs.
foreign {
    func leaf_control_reset(): Unit
    func leaf_control_wait_started(): Int32
    func leaf_control_complete(): Unit
    func leaf_control_wait_gc(): Int32
}

class LiveRoot {
    let payload: Array<Int64> = Array<Int64>(4096, {i => i * 7 + 11})
    func check(): Bool { return payload[0] == 11 && payload[4095] == 28676 }
}

func requireLeaf(condition: Bool, label: String): Unit {
    if (!condition) { throw Exception("LEAF_ASSERT " + label) }
}

func querySemantics(context: LLVMContextRef): Unit {
    for (width in [1u32, 8u32, 32u32, 64u32]) {
        let ty = unsafe { LLVMIntTypeInContext(context, width) }
        let value = unsafe { LLVMConstInt(ty, 1, 0) }
        requireLeaf(unsafe { LLVMTypeOf(value) } == ty, "type-of")
        requireLeaf(unsafe { LLVMGetTypeKind(ty) } == 8, "integer-kind")
        requireLeaf(unsafe { LLVMGetIntTypeWidth(ty) } == width, "integer-width")
        requireLeaf(unsafe { LLVMGetTypeContext(ty) } == context, "context")
        for (space in [0u32, 1u32, 7u32]) {
            let ptr = unsafe { LLVMPointerType(ty, space) }
            requireLeaf(unsafe { LLVMGetTypeKind(ptr) } == 12, "pointer-kind")
            requireLeaf(unsafe { LLVMGetPointerAddressSpace(ptr) } == space, "address-space")
        }
    }
    let fp = unsafe { LLVMDoubleTypeInContext(context) }
    let real = unsafe { LLVMConstReal(fp, 1.25) }
    requireLeaf(unsafe { LLVMTypeOf(real) } == fp, "real-type")
    requireLeaf(unsafe { LLVMGetTypeKind(fp) } == 3, "double-kind")
    let structure = unsafe { LLVMStructTypeInContext(context, CPointer<LLVMTypeRef>(), 0, 0) }
    requireLeaf(unsafe { LLVMGetTypeKind(structure) } == 10, "structure-kind")
    requireLeaf(unsafe { LLVMGetTypeContext(structure) } == context, "structure-context")
}

func queryProgress(context: LLVMContextRef, suppressCompletion: Bool): Unit {
    let ty = unsafe { LLVMInt64TypeInContext(context) }
    let value = unsafe { LLVMConstInt(ty, 17, 0) }
    let ptr = unsafe { LLVMPointerType(ty, 7) }
    let started = AtomicInt64(0)
    let collections = AtomicInt64(0)
    let completed = AtomicInt64(0)
    let root = LiveRoot()
    let worker = spawn { =>
        while (started.load() == 0) { }
        for (i in 0..8) {
            gc(heavy: true)
            collections.store(Int64(i + 1))
        }
        if (!suppressCompletion) { completed.store(1) }
    }
    var iterations = 0i64
    var checksum = 0u64
    started.store(1)
    // No ordinary native call or allocation in the successful loop body.
    // Its generated managed poll is checked alongside the five direct calls.
    while (completed.load() == 0 && iterations < 50000000) {
        let actual = unsafe { LLVMTypeOf(value) }
        let kind = unsafe { LLVMGetTypeKind(actual) }
        let width = unsafe { LLVMGetIntTypeWidth(actual) }
        let owner = unsafe { LLVMGetTypeContext(actual) }
        let space = unsafe { LLVMGetPointerAddressSpace(ptr) }
        if (actual != ty || kind != 8 || width != 64 || owner != context || space != 7) {
            throw Exception("LEAF_ASSERT query-loop-values")
        }
        checksum += UInt64(width + space)
        iterations++
    }
    worker.get()
    requireLeaf(completed.load() == 1 && collections.load() == 8 && iterations > 0,
        "query-gc-progress")
    requireLeaf(checksum == UInt64(iterations) * 71, "query-checksum")
    requireLeaf(root.check(), "managed-root-after-gc")
    println("QUERY_GC_PROGRESS collections=8")
}

func ordinaryNativeProgress(): Unit {
    unsafe { leaf_control_reset() }
    let worker = spawn { =>
        requireLeaf(unsafe { leaf_control_wait_started() } == 1, "ordinary-started")
        gc(heavy: true)
        unsafe { leaf_control_complete() }
    }
    // Intentionally ordinary C2N: waiting native code must not pin managed GC.
    let progressed = unsafe { leaf_control_wait_gc() }
    worker.get()
    requireLeaf(progressed == 1, "ordinary-native-gc-progress")
    println("ORDINARY_NATIVE_GC_PROGRESS")
}

main(args: Array<String>): Int64 {
    let context = unsafe { LLVMContextCreate() }
    try {
        querySemantics(context)
        ordinaryNativeProgress()
        queryProgress(context, args.size > 1 && args[1] == "suppress-completion")
        println("LLVM_LEAF_QUERIES_OK")
        return 0
    } finally { unsafe { LLVMContextDispose(context) } }
}
