package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Function

// Emit real runtime output for top-level `println("literal")` statements captured from a
// function body (carried on Function.printStrings by the frontend/CHIR bridge). Each string
// becomes a private constant C-string global plus a call to libc `puts` (which writes the
// string followed by a newline, matching println). The calls are inserted at the start of
// the function's entry block so they run before the rest of the body.
func EmitFunctionPrintDirectives(cgMod: CGModule, cgFunc: CGFunction, chirFunc: Function): Unit {
    if (chirFunc.printStrings.isEmpty()) {
        return
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let ctx = cgMod.GetLLVMContext().raw
        let rawFn = cgFunc.GetRawFunction()
        if (rawFn.isNull()) {
            return
        }
        let entryBlock = unsafe { LLVMGetEntryBasicBlock(rawFn) }
        let builder = unsafe { LLVMCreateBuilderInContext(ctx) }
        let firstInst = unsafe { LLVMGetFirstInstruction(entryBlock) }
        if (firstInst.isNull()) {
            unsafe { LLVMPositionBuilderAtEnd(builder, entryBlock) }
        } else {
            unsafe { LLVMPositionBuilderBefore(builder, firstInst) }
        }

        let i8Type = unsafe { LLVMInt8TypeInContext(ctx) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i32Type = unsafe { LLVMInt32TypeInContext(ctx) }
        let putsType = BuildPutsFunctionType(i32Type, i8PtrType)
        let putsFn = GetOrInsertRuntimePrintFunction(moduleHandle, "puts", putsType)

        var index = 0
        for (text in chirFunc.printStrings) {
            EmitOnePutsCall(moduleHandle, builder, ctx, text, i32Type, putsType, putsFn,
                chirFunc.GetIdentifier() + ".cjsh.str." + index.toString())
            index++
        }
        unsafe { LLVMDisposeBuilder(builder) }
    }
}

private func BuildPutsFunctionType(i32Type: LLVMTypeRef, i8PtrType: LLVMTypeRef): LLVMTypeRef {
    var result = LLVMNullType()
    try (paramPtr = LibC.malloc<LLVMTypeRef>(count: 1).asResource()) {
        unsafe {
            (paramPtr.value + 0).write(i8PtrType)
            result = LLVMFunctionType(i32Type, paramPtr.value, 1u32, 0)
        }
    }
    return result
}

private func GetOrInsertRuntimePrintFunction(moduleHandle: LLVMModuleHandle, name: String,
    functionType: LLVMTypeRef): LLVMValueRef {
    var fn = LLVMNullValue()
    try (nameC = unsafe { LibC.mallocCString(name) }.asResource()) {
        fn = unsafe { LLVMGetNamedFunction(moduleHandle.raw, nameC.value) }
        if (fn.isNull()) {
            fn = unsafe { LLVMAddFunction(moduleHandle.raw, nameC.value, functionType) }
        }
    }
    return fn
}

private func EmitOnePutsCall(moduleHandle: LLVMModuleHandle, builder: LLVMBuilderRef, ctx: LLVMContextRef,
    text: String, i32Type: LLVMTypeRef, putsType: LLVMTypeRef, putsFn: LLVMValueRef, globalName: String): Unit {
    try (textC = unsafe { LibC.mallocCString(text) }.asResource(),
        nameC = unsafe { LibC.mallocCString(globalName) }.asResource(),
        emptyName = unsafe { LibC.mallocCString("") }.asResource()) {
        let initializer = unsafe { LLVMConstStringInContext(ctx, textC.value, UInt32(text.size), 0) }
        let globalType = unsafe { LLVMTypeOf(initializer) }
        let global = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, nameC.value) }
        unsafe {
            LLVMSetInitializer(global, initializer)
            LLVMSetLinkage(global, LLVMLinkageValue(LLVMLinkage.Private))
            LLVMSetGlobalConstant(global, 1)
        }
        let zero = unsafe { LLVMConstInt(i32Type, 0u64, 0) }
        var gepPtr = LLVMNullValue()
        try (indices = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
            unsafe {
                (indices.value + 0).write(zero)
                (indices.value + 1).write(zero)
                gepPtr = LLVMBuildInBoundsGEP2(builder, globalType, global, indices.value, 2u32, emptyName.value)
            }
        }
        try (argPtr = LibC.malloc<LLVMValueRef>(count: 1).asResource()) {
            unsafe {
                (argPtr.value + 0).write(gepPtr)
                let _ = LLVMBuildCall2(builder, putsType, putsFn, argPtr.value, 1u32, emptyName.value)
            }
        }
    }
}
