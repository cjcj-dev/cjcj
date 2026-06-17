package cangjie_compiler::codegen

import std.collection.*
import cangjie_compiler::chir.Function

// Emit real runtime output for top-level `println("literal")` / `print("literal")` statements
// captured from a function body (carried on Function.printStrings, with a parallel
// Function.printNewlines flag list, by the frontend/CHIR bridge). Each string becomes a private
// constant C-string global. For println (newline == true) we call libc `puts`, which writes the
// string followed by a newline. For print (newline == false) we call libc `fputs(str, stdout)`,
// which writes the string with no trailing newline. The calls are inserted at the start of the
// function's entry block, in captured source order, so they run before the rest of the body.
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
        // int puts(const char *)
        let putsType = BuildPutsFunctionType(i32Type, i8PtrType)
        let putsFn = GetOrInsertRuntimePrintFunction(moduleHandle, "puts", putsType)
        // int fputs(const char *, FILE *) -- FILE* modeled as opaque i8*
        let fputsType = BuildFputsFunctionType(i32Type, i8PtrType)
        let fputsFn = GetOrInsertRuntimePrintFunction(moduleHandle, "fputs", fputsType)
        // extern FILE *stdout -- modeled as a global i8* we load before each fputs call
        let stdoutGlobal = GetOrInsertStdoutGlobal(moduleHandle, i8PtrType)

        var index = 0
        for (text in chirFunc.printStrings) {
            let newline = if (index < chirFunc.printNewlines.size) {
                chirFunc.printNewlines[index]
            } else {
                true
            }
            let globalName = chirFunc.GetIdentifier() + ".cjsh.str." + index.toString()
            if (newline) {
                EmitOnePutsCall(moduleHandle, builder, ctx, text, i32Type, putsType, putsFn, globalName)
            } else {
                EmitOneFputsCall(moduleHandle, builder, ctx, text, i32Type, i8PtrType, fputsType, fputsFn,
                    stdoutGlobal, globalName)
            }
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

private func BuildFputsFunctionType(i32Type: LLVMTypeRef, i8PtrType: LLVMTypeRef): LLVMTypeRef {
    var result = LLVMNullType()
    try (paramPtr = LibC.malloc<LLVMTypeRef>(count: 2).asResource()) {
        unsafe {
            (paramPtr.value + 0).write(i8PtrType)
            (paramPtr.value + 1).write(i8PtrType)
            result = LLVMFunctionType(i32Type, paramPtr.value, 2u32, 0)
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

// Declare (or fetch) the external `stdout` FILE* global, modeled as an external i8* global.
private func GetOrInsertStdoutGlobal(moduleHandle: LLVMModuleHandle, i8PtrType: LLVMTypeRef): LLVMValueRef {
    var global = LLVMNullValue()
    try (nameC = unsafe { LibC.mallocCString("stdout") }.asResource()) {
        global = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameC.value) }
        if (global.isNull()) {
            global = unsafe { LLVMAddGlobal(moduleHandle.raw, i8PtrType, nameC.value) }
            unsafe { LLVMSetLinkage(global, LLVMLinkageValue(LLVMLinkage.External)) }
        }
    }
    return global
}

// Build a private constant C-string global for `text` and return a GEP pointer to its first byte.
private func EmitStringGlobalPtr(moduleHandle: LLVMModuleHandle, builder: LLVMBuilderRef, ctx: LLVMContextRef,
    text: String, i32Type: LLVMTypeRef, globalName: String): LLVMValueRef {
    var gepPtr = LLVMNullValue()
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
        try (indices = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
            unsafe {
                (indices.value + 0).write(zero)
                (indices.value + 1).write(zero)
                gepPtr = LLVMBuildInBoundsGEP2(builder, globalType, global, indices.value, 2u32, emptyName.value)
            }
        }
    }
    return gepPtr
}

private func EmitOnePutsCall(moduleHandle: LLVMModuleHandle, builder: LLVMBuilderRef, ctx: LLVMContextRef,
    text: String, i32Type: LLVMTypeRef, putsType: LLVMTypeRef, putsFn: LLVMValueRef, globalName: String): Unit {
    let gepPtr = EmitStringGlobalPtr(moduleHandle, builder, ctx, text, i32Type, globalName)
    try (emptyName = unsafe { LibC.mallocCString("") }.asResource(),
        argPtr = LibC.malloc<LLVMValueRef>(count: 1).asResource()) {
        unsafe {
            (argPtr.value + 0).write(gepPtr)
            let _ = LLVMBuildCall2(builder, putsType, putsFn, argPtr.value, 1u32, emptyName.value)
        }
    }
}

private func EmitOneFputsCall(moduleHandle: LLVMModuleHandle, builder: LLVMBuilderRef, ctx: LLVMContextRef,
    text: String, i32Type: LLVMTypeRef, i8PtrType: LLVMTypeRef, fputsType: LLVMTypeRef, fputsFn: LLVMValueRef,
    stdoutGlobal: LLVMValueRef, globalName: String): Unit {
    let gepPtr = EmitStringGlobalPtr(moduleHandle, builder, ctx, text, i32Type, globalName)
    try (emptyName = unsafe { LibC.mallocCString("") }.asResource(),
        loadName = unsafe { LibC.mallocCString("") }.asResource(),
        argPtr = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
        unsafe {
            let streamVal = LLVMBuildLoad2(builder, i8PtrType, stdoutGlobal, loadName.value)
            (argPtr.value + 0).write(gepPtr)
            (argPtr.value + 1).write(streamVal)
            let _ = LLVMBuildCall2(builder, fputsType, fputsFn, argPtr.value, 2u32, emptyName.value)
        }
    }
}
