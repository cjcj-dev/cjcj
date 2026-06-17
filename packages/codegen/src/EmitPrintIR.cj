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
        let i64Type = unsafe { LLVMInt64TypeInContext(ctx) }
        // int puts(const char *)
        let putsType = BuildPutsFunctionType(i32Type, i8PtrType)
        let putsFn = GetOrInsertRuntimePrintFunction(moduleHandle, "puts", putsType)
        // int fputs(const char *, FILE *) -- FILE* modeled as opaque i8*
        let fputsType = BuildFputsFunctionType(i32Type, i8PtrType)
        let fputsFn = GetOrInsertRuntimePrintFunction(moduleHandle, "fputs", fputsType)
        // extern FILE *stdout -- modeled as a global i8* we load before each fputs call
        let stdoutGlobal = GetOrInsertStdoutGlobal(moduleHandle, i8PtrType)
        // int printf(const char *, ...) -- variadic, used for integer prints
        let printfType = BuildPrintfFunctionType(i32Type, i8PtrType)
        let printfFn = GetOrInsertRuntimePrintFunction(moduleHandle, "printf", printfType)

        var index = 0
        for (text in chirFunc.printStrings) {
            let newline = if (index < chirFunc.printNewlines.size) {
                chirFunc.printNewlines[index]
            } else {
                true
            }
            let isInt = if (index < chirFunc.printIsInt.size) {
                chirFunc.printIsInt[index]
            } else {
                false
            }
            let globalName = chirFunc.GetIdentifier() + ".cjsh.str." + index.toString()
            if (isInt) {
                // println(int) -> printf("%ld\n", v); print(int) -> printf("%ld", v)
                let fmt = if (newline) { "%ld\n" } else { "%ld" }
                let fmtName = chirFunc.GetIdentifier() + ".cjsh.fmt." + index.toString()
                EmitOnePrintfIntCall(moduleHandle, builder, ctx, fmt, ParseDecimalI64(text), i32Type,
                    i64Type, printfType, printfFn, fmtName)
            } else if (newline) {
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

// Emit a runtime-value integer print: printf("%ld"/"%ld\n", <value>) using the LLVM `builder` at its
// current insert point (so the call lands right where the value was computed in body flow). `value`
// is an already-materialized i64 LLVM value (a loop accumulator, a call result, etc.). Returns false
// if the module handle / builder is unusable. `fmtName` must be unique within the module.
public func EmitRuntimeIntPrint(cgMod: CGModule, builderRaw: LLVMBuilderRef, value: LLVMValueRef,
    newline: Bool, fmtName: String): Bool {
    if (value.isNull() || builderRaw.isNull()) {
        return false
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let ctx = cgMod.GetLLVMContext().raw
        let i8Type = unsafe { LLVMInt8TypeInContext(ctx) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i32Type = unsafe { LLVMInt32TypeInContext(ctx) }
        let i64Type = unsafe { LLVMInt64TypeInContext(ctx) }
        let printfType = BuildPrintfFunctionType(i32Type, i8PtrType)
        let printfFn = GetOrInsertRuntimePrintFunction(moduleHandle, "printf", printfType)
        let fmt = if (newline) { "%ld\n" } else { "%ld" }
        let fmtPtr = EmitStringGlobalPtr(moduleHandle, builderRaw, ctx, fmt, i32Type, fmtName)
        // The value may be a narrower integer (e.g. i1/i32); widen to i64 for the %ld format.
        var argValue = value
        let valueType = unsafe { LLVMTypeOf(value) }
        if (unsafe { LLVMGetTypeKind(valueType) } == 8) {
            let width = unsafe { LLVMGetIntTypeWidth(valueType) }
            if (width < 64u32) {
                try (extName = unsafe { LibC.mallocCString("") }.asResource()) {
                    argValue = unsafe { LLVMBuildSExt(builderRaw, value, i64Type, extName.value) }
                }
            }
        }
        try (emptyName = unsafe { LibC.mallocCString("") }.asResource(),
            argPtr = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
            unsafe {
                (argPtr.value + 0).write(fmtPtr)
                (argPtr.value + 1).write(argValue)
                let _ = LLVMBuildCall2(builderRaw, printfType, printfFn, argPtr.value, 2u32, emptyName.value)
            }
        }
        return true
    }
    return false
}

// Emit a runtime-value Float64 print: printf("%f"/"%f\n", <double>) using the LLVM `builder` at its
// current insert point. `value` is an already-materialized Float64 (double) LLVM value. The "%f"
// format matches the reference cjc's six-decimal float formatting (e.g. 5.500000). A narrower float
// (e.g. a 32-bit float) is widened to double for the variadic %f format. Returns false if the module
// handle / builder is unusable. `fmtName` must be unique within the module.
public func EmitRuntimeFloatPrint(cgMod: CGModule, builderRaw: LLVMBuilderRef, value: LLVMValueRef,
    newline: Bool, fmtName: String): Bool {
    if (value.isNull() || builderRaw.isNull()) {
        return false
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let ctx = cgMod.GetLLVMContext().raw
        let i8Type = unsafe { LLVMInt8TypeInContext(ctx) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i32Type = unsafe { LLVMInt32TypeInContext(ctx) }
        let doubleType = unsafe { LLVMDoubleTypeInContext(ctx) }
        let printfType = BuildPrintfFunctionType(i32Type, i8PtrType)
        let printfFn = GetOrInsertRuntimePrintFunction(moduleHandle, "printf", printfType)
        let fmt = if (newline) { "%f\n" } else { "%f" }
        let fmtPtr = EmitStringGlobalPtr(moduleHandle, builderRaw, ctx, fmt, i32Type, fmtName)
        // The variadic %f format expects a double; widen a narrower float operand to double.
        var argValue = value
        let valueType = unsafe { LLVMTypeOf(value) }
        // LLVMTypeKind: 2 = Float (32-bit), 3 = Double (64-bit). Only widen a 32-bit float.
        if (unsafe { LLVMGetTypeKind(valueType) } == 2) {
            try (extName = unsafe { LibC.mallocCString("") }.asResource()) {
                argValue = unsafe { LLVMBuildFPExt(builderRaw, value, doubleType, extName.value) }
            }
        }
        try (emptyName = unsafe { LibC.mallocCString("") }.asResource(),
            argPtr = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
            unsafe {
                (argPtr.value + 0).write(fmtPtr)
                (argPtr.value + 1).write(argValue)
                let _ = LLVMBuildCall2(builderRaw, printfType, printfFn, argPtr.value, 2u32, emptyName.value)
            }
        }
        return true
    }
    return false
}

// Emit a runtime-value Bool print: select between the literal C-strings "true" and "false" on the
// i1 `value`, then printf("%s"/"%s\n", selected). Lands at the LLVM `builder`'s current insert point
// (right where the i1 was computed in body flow). `globalName` must be unique within the module.
// Returns false if the module handle / builder is unusable.
public func EmitRuntimeBoolPrint(cgMod: CGModule, builderRaw: LLVMBuilderRef, value: LLVMValueRef,
    newline: Bool, globalName: String): Bool {
    if (value.isNull() || builderRaw.isNull()) {
        return false
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let ctx = cgMod.GetLLVMContext().raw
        let i8Type = unsafe { LLVMInt8TypeInContext(ctx) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i32Type = unsafe { LLVMInt32TypeInContext(ctx) }
        let printfType = BuildPrintfFunctionType(i32Type, i8PtrType)
        let printfFn = GetOrInsertRuntimePrintFunction(moduleHandle, "printf", printfType)
        let truePtr = EmitStringGlobalPtr(moduleHandle, builderRaw, ctx, "true", i32Type, globalName + ".t")
        let falsePtr = EmitStringGlobalPtr(moduleHandle, builderRaw, ctx, "false", i32Type, globalName + ".f")
        let fmt = if (newline) { "%s\n" } else { "%s" }
        let fmtPtr = EmitStringGlobalPtr(moduleHandle, builderRaw, ctx, fmt, i32Type, globalName + ".fmt")
        try (selName = unsafe { LibC.mallocCString("") }.asResource(),
            emptyName = unsafe { LibC.mallocCString("") }.asResource(),
            argPtr = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
            unsafe {
                let selected = LLVMBuildSelect(builderRaw, value, truePtr, falsePtr, selName.value)
                (argPtr.value + 0).write(fmtPtr)
                (argPtr.value + 1).write(selected)
                let _ = LLVMBuildCall2(builderRaw, printfType, printfFn, argPtr.value, 2u32, emptyName.value)
            }
        }
        return true
    }
    return false
}

// Emit a literal-string print at the LLVM `builder`'s current insert point (so it lands at the
// anchor in body flow). For println (newline == true) we call libc `puts` (writes the string + a
// newline); for print (newline == false) we call `fputs(str, stdout)` (no trailing newline). This
// is the real-body counterpart of the entry-block side-channel's string emission, used so a mixed
// body can interleave literal-string prints with runtime-value prints in source order. `globalName`
// must be unique within the module. Returns false if the module handle / builder is unusable.
public func EmitRuntimeStringPrint(cgMod: CGModule, builderRaw: LLVMBuilderRef, text: String,
    newline: Bool, globalName: String): Bool {
    if (builderRaw.isNull()) {
        return false
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let ctx = cgMod.GetLLVMContext().raw
        let i8Type = unsafe { LLVMInt8TypeInContext(ctx) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i32Type = unsafe { LLVMInt32TypeInContext(ctx) }
        if (newline) {
            let putsType = BuildPutsFunctionType(i32Type, i8PtrType)
            let putsFn = GetOrInsertRuntimePrintFunction(moduleHandle, "puts", putsType)
            EmitOnePutsCall(moduleHandle, builderRaw, ctx, text, i32Type, putsType, putsFn, globalName)
        } else {
            let fputsType = BuildFputsFunctionType(i32Type, i8PtrType)
            let fputsFn = GetOrInsertRuntimePrintFunction(moduleHandle, "fputs", fputsType)
            let stdoutGlobal = GetOrInsertStdoutGlobal(moduleHandle, i8PtrType)
            EmitOneFputsCall(moduleHandle, builderRaw, ctx, text, i32Type, i8PtrType, fputsType, fputsFn,
                stdoutGlobal, globalName)
        }
        return true
    }
    return false
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

// Reinterpret an Int64 as its raw 64-bit pattern as a UInt64 (avoids overflow on negatives, which
// would trap in a direct UInt64(value) conversion).
private func SignedInt64ToBits(value: Int64): UInt64 {
    if (value >= 0) {
        return UInt64(value)
    }
    return 0x8000000000000000u64 + UInt64(value - Int64.Min)
}

// int printf(const char *, ...) -- variadic format-string function.
private func BuildPrintfFunctionType(i32Type: LLVMTypeRef, i8PtrType: LLVMTypeRef): LLVMTypeRef {
    var result = LLVMNullType()
    try (paramPtr = LibC.malloc<LLVMTypeRef>(count: 1).asResource()) {
        unsafe {
            (paramPtr.value + 0).write(i8PtrType)
            // isVarArg = 1 so additional arguments (the i64 value) are accepted.
            result = LLVMFunctionType(i32Type, paramPtr.value, 1u32, 1)
        }
    }
    return result
}

// Parse a decimal integer literal (optionally a leading `-`, with optional `_` separators) into an
// Int64. Falls back to 0 on malformed input; the frontend only forwards real integer literals here.
private func ParseDecimalI64(text: String): Int64 {
    var result: Int64 = 0
    var negative = false
    var idx = 0
    let bytes = text
    if (bytes.size > 0 && bytes[0] == b'-') {
        negative = true
        idx = 1
    }
    while (idx < bytes.size) {
        let c = bytes[idx]
        if (c == b'_') {
            idx++
            continue
        }
        if (c < b'0' || c > b'9') {
            break
        }
        result = result * 10 + Int64(c - b'0')
        idx++
    }
    if (negative) {
        return -result
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

// Emit `printf(<fmt>, <i64 value>)` for an integer print. The format string ("%ld\n" / "%ld") is a
// private constant global; the value is an i64 LLVM constant.
private func EmitOnePrintfIntCall(moduleHandle: LLVMModuleHandle, builder: LLVMBuilderRef, ctx: LLVMContextRef,
    fmt: String, value: Int64, i32Type: LLVMTypeRef, i64Type: LLVMTypeRef, printfType: LLVMTypeRef,
    printfFn: LLVMValueRef, fmtName: String): Unit {
    let fmtPtr = EmitStringGlobalPtr(moduleHandle, builder, ctx, fmt, i32Type, fmtName)
    try (emptyName = unsafe { LibC.mallocCString("") }.asResource(),
        argPtr = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
        unsafe {
            // SignExtend = 1 so negative Int64 values reinterpret correctly as i64 constants.
            let intConst = LLVMConstInt(i64Type, SignedInt64ToBits(value), 1)
            (argPtr.value + 0).write(fmtPtr)
            (argPtr.value + 1).write(intConst)
            let _ = LLVMBuildCall2(builder, printfType, printfFn, argPtr.value, 2u32, emptyName.value)
        }
    }
}
