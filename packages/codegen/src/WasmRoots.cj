package cjcj::codegen

import std.collection.*

private let LLVM_STRUCT_KIND: Int32 = 10
private let LLVM_ARRAY_KIND: Int32 = 11
private let LLVM_POINTER_KIND: Int32 = 12

// CjwRootFrame and cjw_static_root_table_register belong to the wasm32 C6 ABI.
// This file emits roots only. It must not declare precise collection: neither a
// single LLVM partition nor the presence of these symbols proves that other
// partitions, std.core, libraries and the stack lowering cover all roots.
internal func EmitWasmRoots(cgMod: CGModule): Unit {
    let module = cgMod.GetLLVMModule().getOrThrow()
    try (builder = IRBuilder2(cgMod)) {
        EmitWasmShadowRoots(cgMod, module, builder)
        EmitWasmStaticRoots(cgMod, module, builder)
    }
}

internal func IsWasmManagedPointer(ty: LLVMTypeRef): Bool {
    return unsafe { LLVMGetTypeKind(ty) == LLVM_POINTER_KIND && LLVMGetPointerAddressSpace(ty) == 1u32 }
}

internal func WasmStructType(context: LLVMContextRef, fields: Array<LLVMTypeRef>): LLVMTypeRef {
    var result = LLVMNullType()
    try (types = LibC.malloc<LLVMTypeRef>(count: fields.size).asResource()) {
        for (i in 0..fields.size) {
            unsafe { (types.value + i).write(fields[i]) }
        }
        result = unsafe { LLVMStructTypeInContext(context, types.value, UInt32(fields.size), 0) }
    }
    return result
}

private func AddWasmRootGlobal(module: LLVMModuleHandle, name: String, initValue: LLVMValueRef,
    linkage: LLVMLinkage): LLVMValueRef {
    var global = LLVMNullValue()
    try (cname = unsafe { LibC.mallocCString(name) }.asResource()) {
        unsafe {
            global = LLVMAddGlobal(module.raw, LLVMTypeOf(initValue), cname.value)
            LLVMSetInitializer(global, initValue)
            LLVMSetLinkage(global, LLVMLinkageValue(linkage))
        }
    }
    return global
}

// Enumerate storage, not values seen in static write barriers. A slot can also
// be written from a different partition, through an aggregate, or in an
// initializer. LLVM owns the offsets of the struct/array layout.
private func CollectWasmStaticSlots(builder: IRBuilder2, ty: LLVMTypeRef, address: LLVMValueRef,
    slotType: LLVMTypeRef, slots: ArrayList<LLVMValueRef>): Unit {
    if (IsWasmManagedPointer(ty)) {
        slots.add(unsafe { LLVMConstBitCast(address, slotType) })
        return
    }
    let kind = unsafe { LLVMGetTypeKind(ty) }
    if (kind != LLVM_STRUCT_KIND && kind != LLVM_ARRAY_KIND) { return }
    let isStruct = kind == LLVM_STRUCT_KIND
    let count = unsafe { if (isStruct) { LLVMCountStructElementTypes(ty) } else { LLVMGetArrayLength(ty) } }
    if (!isStruct && !builder.IsTypeContainsRef(unsafe { LLVMGetElementType(ty) })) { return }
    try (indices = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
        unsafe { indices.value.write(builder.GetInt32(0)) }
        for (i in 0u32..count) {
            let child = unsafe { if (isStruct) { LLVMStructGetTypeAtIndex(ty, i) } else { LLVMGetElementType(ty) } }
            if (!builder.IsTypeContainsRef(child)) { continue }
            let childAddress = unsafe {
                (indices.value + 1).write(builder.GetInt32(Int64(i)))
                LLVMConstInBoundsGEP2(ty, address, indices.value, 2u32)
            }
            CollectWasmStaticSlots(builder, child, childAddress, slotType, slots)
        }
    }
}

private func EmitWasmStaticRoots(cgMod: CGModule, module: LLVMModuleHandle, builder: IRBuilder2): Unit {
    let context = cgMod.GetLLVMContext().raw
    let bytePtr = unsafe { LLVMPointerType(LLVMInt8TypeInContext(context), 0u32) }
    let slotPtr = unsafe { LLVMPointerType(bytePtr, 0u32) }
    let tablePtr = unsafe { LLVMPointerType(slotPtr, 0u32) }
    let slots = ArrayList<LLVMValueRef>()
    var global = unsafe { LLVMGetFirstGlobal(module.raw) }
    while (!global.isNull()) {
        // Immutable data cannot acquire a heap reference. Only storage owned
        // by this object goes into its table; extern declarations belong to
        // the object that defines them. TLS has no single static address.
        if (unsafe {
            LLVMIsDeclaration(global) == 0 && LLVMIsGlobalConstant(global) == 0 &&
            LLVMGetLinkage(global) != LLVMLinkageValue(LLVMLinkage.AvailableExternally) &&
            LLVMGetThreadLocalMode(global) == 0 &&
            LLVMGetPointerAddressSpace(LLVMTypeOf(global)) == 0u32
        }) {
            CollectWasmStaticSlots(builder, unsafe { LLVMGlobalGetValueType(global) }, global, slotPtr, slots)
        }
        global = unsafe { LLVMGetNextGlobal(global) }
    }
    if (slots.isEmpty()) { return }

    let table = AddWasmRootGlobal(module, ".cj.wasm.static_roots", ConstLLVMArray(slotPtr, slots),
        LLVMLinkage.Private)
    unsafe { LLVMSetGlobalConstant(table, 1) }
    let voidType = unsafe { LLVMVoidTypeInContext(context) }
    let ctorType = CGType.GetCodeGenFunctionType(cgMod.GetLLVMContext(), voidType)
    let registerType = CGType.GetCodeGenFunctionType(cgMod.GetLLVMContext(), voidType,
        ArrayList<LLVMTypeRef>([tablePtr, unsafe { LLVMInt32TypeInContext(context) }]))
    let register = cgMod.GetOrInsertFunction("cjw_static_root_table_register", registerType)
    let ctor = cgMod.GetOrInsertFunction(".cj.wasm.register_static_roots", ctorType)
    unsafe { LLVMSetLinkage(ctor, LLVMLinkageValue(LLVMLinkage.Internal)) }
    builder.SetInsertPoint(builder.CreateBasicBlockAtEnd(ctor, "entry"))
    builder.CreateCall(register, registerType,
        ArrayList<LLVMValueRef>([unsafe { LLVMConstBitCast(table, tablePtr) }, builder.GetInt32(slots.size)]))
    builder.CreateRetVoid()

    // wasm-ld keeps init functions across the driver's relocatable merge.
    // wasi-libc's crt1-command _start calls __wasm_call_ctors before main.
    // A constructor per partition also handles cache globals with local
    // linkage; no cross-partition references to private symbols are needed.
    AppendWasmRootCtor(module, context, builder, ctor, bytePtr)
}

private func AppendWasmRootCtor(module: LLVMModuleHandle, context: LLVMContextRef, builder: IRBuilder2,
    ctor: LLVMValueRef, bytePtr: LLVMTypeRef): Unit {
    let name = "llvm.global_ctors"
    let entryType = WasmStructType(context, [unsafe { LLVMInt32TypeInContext(context) },
        unsafe { LLVMTypeOf(ctor) }, bytePtr])
    let entries = ArrayList<LLVMValueRef>()
    try (cname = unsafe { LibC.mallocCString(name) }.asResource(),
        fields = LibC.malloc<LLVMValueRef>(count: 3).asResource()) {
        let previous = unsafe { LLVMGetNamedGlobal(module.raw, cname.value) }
        if (!previous.isNull()) {
            let initializer = unsafe { LLVMGetInitializer(previous) }
            let count = Int64(unsafe { LLVMGetNumOperands(initializer) })
            for (i in 0..count) {
                entries.add(unsafe { LLVMGetOperand(initializer, UInt32(i)) })
            }
            unsafe { LLVMDeleteGlobal(previous) }
        }
        unsafe {
            fields.value.write(builder.GetInt32(0))
            (fields.value + 1).write(ctor)
            (fields.value + 2).write(LLVMConstNull(bytePtr))
            entries.add(LLVMConstNamedStruct(entryType, fields.value, 3u32))
        }
    }
    AddWasmRootGlobal(module, name, ConstLLVMArray(entryType, entries), LLVMLinkage.Appending)
}
