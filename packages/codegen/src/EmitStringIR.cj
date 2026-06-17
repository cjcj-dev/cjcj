package cangjie_compiler::codegen

// Real-body String support, modeled as CString (i8*) values.
//
// A String value on the real body-lowering path is a NUL-terminated C-string pointer (i8*). This
// file provides the three runtime primitives codegen needs:
//   - EmitCStringLiteralPointer: a String literal -> first-byte pointer of a private constant global.
//   - EmitCStringConcat: `a + b` over two i8* -> a freshly malloc'd i8* holding the concatenation
//     (libc strlen/malloc/strcpy/strcat).
//   - EmitRuntimeStringValuePrint: println/print of a runtime i8* String value via puts/fputs.
//
// These mirror the existing C-string print machinery (EmitPrintIR.cj) so the runtime representation
// stays consistent: codegen already maps CHIR CString -> LLVM i8*, and println of a literal already
// goes through puts/fputs.

// Build (or reuse) a private constant global C-string for `text` and return an i8* GEP to its first
// byte. Globals are deduplicated by a content-derived name so identical literals share storage.
public func EmitCStringLiteralPointer(cgMod: CGModule, builderRaw: LLVMBuilderRef, ctx: LLVMContextRef,
    text: String): LLVMValueRef {
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let i8Type = unsafe { LLVMInt8TypeInContext(ctx) }
        let i32Type = unsafe { LLVMInt32TypeInContext(ctx) }
        let globalName = "cjsh.cstr." + CStringLiteralKey(text)
        var global = LLVMNullValue()
        try (nameC = unsafe { LibC.mallocCString(globalName) }.asResource()) {
            global = unsafe { LLVMGetNamedGlobal(moduleHandle.raw, nameC.value) }
        }
        if (global.isNull()) {
            try (textC = unsafe { LibC.mallocCString(text) }.asResource(),
                nameC = unsafe { LibC.mallocCString(globalName) }.asResource()) {
                // dontNullTerminate = 0 so the initializer is [text.size + 1 x i8] (NUL included).
                let initializer = unsafe { LLVMConstStringInContext(ctx, textC.value, UInt32(text.size), 0) }
                let globalType = unsafe { LLVMTypeOf(initializer) }
                global = unsafe { LLVMAddGlobal(moduleHandle.raw, globalType, nameC.value) }
                unsafe {
                    LLVMSetInitializer(global, initializer)
                    LLVMSetLinkage(global, LLVMLinkageValue(LLVMLinkage.Private))
                    LLVMSetGlobalConstant(global, 1)
                }
            }
        }
        // GEP [0, 0] to obtain an i8* to the first byte.
        let globalType = unsafe {
            // The global's value type is the [N x i8] array; rebuild it from text length for the GEP.
            LLVMArrayType(i8Type, UInt32(text.size + 1))
        }
        let zero = unsafe { LLVMConstInt(i32Type, 0u64, 0) }
        var gepPtr = LLVMNullValue()
        try (emptyName = unsafe { LibC.mallocCString("") }.asResource(),
            indices = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
            unsafe {
                (indices.value + 0).write(zero)
                (indices.value + 1).write(zero)
                gepPtr = LLVMBuildInBoundsGEP2(builderRaw, globalType, global, indices.value, 2u32, emptyName.value)
            }
        }
        return gepPtr
    }
    return LLVMNullValue()
}

// Emit a runtime concatenation of two i8* C-strings `left` and `right`, returning a fresh i8* that
// points to malloc'd storage holding `left` followed by `right` (NUL-terminated). Lowers to:
//   l = strlen(left); r = strlen(right); buf = malloc(l + r + 1); strcpy(buf, left); strcat(buf, right)
public func EmitCStringConcat(cgMod: CGModule, builderRaw: LLVMBuilderRef, ctx: LLVMContextRef,
    left: LLVMValueRef, right: LLVMValueRef): LLVMValueRef {
    if (left.isNull() || right.isNull() || builderRaw.isNull()) {
        return LLVMNullValue()
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let i8Type = unsafe { LLVMInt8TypeInContext(ctx) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i64Type = unsafe { LLVMInt64TypeInContext(ctx) }

        // size_t strlen(const char *)
        let strlenType = BuildFnType1(i64Type, i8PtrType)
        let strlenFn = GetOrInsertStringRuntimeFn(moduleHandle, "strlen", strlenType)
        // void *malloc(size_t)
        let mallocType = BuildFnType1(i8PtrType, i64Type)
        let mallocFn = GetOrInsertStringRuntimeFn(moduleHandle, "malloc", mallocType)
        // char *strcpy(char *dst, const char *src) / char *strcat(char *dst, const char *src)
        let strcpyType = BuildFnType2(i8PtrType, i8PtrType, i8PtrType)
        let strcpyFn = GetOrInsertStringRuntimeFn(moduleHandle, "strcpy", strcpyType)
        let strcatType = BuildFnType2(i8PtrType, i8PtrType, i8PtrType)
        let strcatFn = GetOrInsertStringRuntimeFn(moduleHandle, "strcat", strcatType)

        let lenLeft = CallFn1(builderRaw, strlenType, strlenFn, left)
        let lenRight = CallFn1(builderRaw, strlenType, strlenFn, right)
        var total = LLVMNullValue()
        let one = unsafe { LLVMConstInt(i64Type, 1u64, 0) }
        try (addName = unsafe { LibC.mallocCString("") }.asResource(),
            add2Name = unsafe { LibC.mallocCString("") }.asResource()) {
            unsafe {
                let sum = LLVMBuildAdd(builderRaw, lenLeft, lenRight, addName.value)
                total = LLVMBuildAdd(builderRaw, sum, one, add2Name.value)
            }
        }
        let buf = CallFn1(builderRaw, mallocType, mallocFn, total)
        let _ = CallFn2(builderRaw, strcpyType, strcpyFn, buf, left)
        let _ = CallFn2(builderRaw, strcatType, strcatFn, buf, right)
        return buf
    }
    return LLVMNullValue()
}

// Emit a runtime String-value print: print the i8* `value` via libc puts (newline) / fputs (no
// newline). `globalName` is unused for the puts path; the fputs path needs the extern stdout global.
public func EmitRuntimeStringValuePrint(cgMod: CGModule, builderRaw: LLVMBuilderRef, value: LLVMValueRef,
    newline: Bool): Bool {
    if (value.isNull() || builderRaw.isNull()) {
        return false
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let ctx = cgMod.GetLLVMContext().raw
        let i8Type = unsafe { LLVMInt8TypeInContext(ctx) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i32Type = unsafe { LLVMInt32TypeInContext(ctx) }
        if (newline) {
            // int puts(const char *) -- writes the string and a trailing newline.
            let putsType = BuildFnType1(i32Type, i8PtrType)
            let putsFn = GetOrInsertStringRuntimeFn(moduleHandle, "puts", putsType)
            let _ = CallFn1(builderRaw, putsType, putsFn, value)
        } else {
            // int fputs(const char *, FILE *) with FILE* modeled as opaque i8* loaded from stdout.
            let fputsType = BuildFnType2(i32Type, i8PtrType, i8PtrType)
            let fputsFn = GetOrInsertStringRuntimeFn(moduleHandle, "fputs", fputsType)
            let stdoutGlobal = GetOrInsertStdoutForString(moduleHandle, i8PtrType)
            try (loadName = unsafe { LibC.mallocCString("") }.asResource(),
                emptyName = unsafe { LibC.mallocCString("") }.asResource(),
                argPtr = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
                unsafe {
                    let streamVal = LLVMBuildLoad2(builderRaw, i8PtrType, stdoutGlobal, loadName.value)
                    (argPtr.value + 0).write(value)
                    (argPtr.value + 1).write(streamVal)
                    let _ = LLVMBuildCall2(builderRaw, fputsType, fputsFn, argPtr.value, 2u32, emptyName.value)
                }
            }
        }
        return true
    }
    return false
}

// Emit a runtime Int64 -> C-string conversion: malloc a 24-byte buffer and snprintf the i64 `value`
// into it as "%ld", returning the i8* buffer pointer. 24 bytes is enough for any 64-bit decimal
// (at most 20 digits plus a sign and NUL). Used by string interpolation to stringify an Int64
// interpolated expression before concatenation. The value is sign-extended to i64 if narrower.
public func EmitIntToCString(cgMod: CGModule, builderRaw: LLVMBuilderRef, ctx: LLVMContextRef,
    value: LLVMValueRef): LLVMValueRef {
    if (value.isNull() || builderRaw.isNull()) {
        return LLVMNullValue()
    }
    if (let Some(moduleHandle) <- cgMod.GetLLVMModule()) {
        let i8Type = unsafe { LLVMInt8TypeInContext(ctx) }
        let i8PtrType = unsafe { LLVMPointerType(i8Type, 0u32) }
        let i32Type = unsafe { LLVMInt32TypeInContext(ctx) }
        let i64Type = unsafe { LLVMInt64TypeInContext(ctx) }

        // void *malloc(size_t)
        let mallocType = BuildFnType1(i8PtrType, i64Type)
        let mallocFn = GetOrInsertStringRuntimeFn(moduleHandle, "malloc", mallocType)
        let bufSize = unsafe { LLVMConstInt(i64Type, 24u64, 0) }
        let buf = CallFn1(builderRaw, mallocType, mallocFn, bufSize)

        // int snprintf(char *buf, size_t n, const char *fmt, ...)
        let snprintfType = BuildSnprintfType(i32Type, i8PtrType, i64Type)
        let snprintfFn = GetOrInsertStringRuntimeFn(moduleHandle, "snprintf", snprintfType)
        let fmtPtr = EmitCStringLiteralPointer(cgMod, builderRaw, ctx, "%ld")

        // Widen a narrower integer operand to i64 for the %ld format.
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
            argPtr = LibC.malloc<LLVMValueRef>(count: 4).asResource()) {
            unsafe {
                (argPtr.value + 0).write(buf)
                (argPtr.value + 1).write(bufSize)
                (argPtr.value + 2).write(fmtPtr)
                (argPtr.value + 3).write(argValue)
                let _ = LLVMBuildCall2(builderRaw, snprintfType, snprintfFn, argPtr.value, 4u32, emptyName.value)
            }
        }
        return buf
    }
    return LLVMNullValue()
}

// Emit a runtime Bool -> C-string conversion: select between the constant C-strings "true" and
// "false" on the i1 `value`, returning the selected i8*. Used by string interpolation to stringify
// a Bool interpolated expression before concatenation.
public func EmitBoolToCString(cgMod: CGModule, builderRaw: LLVMBuilderRef, ctx: LLVMContextRef,
    value: LLVMValueRef): LLVMValueRef {
    if (value.isNull() || builderRaw.isNull()) {
        return LLVMNullValue()
    }
    let truePtr = EmitCStringLiteralPointer(cgMod, builderRaw, ctx, "true")
    let falsePtr = EmitCStringLiteralPointer(cgMod, builderRaw, ctx, "false")
    var selected = LLVMNullValue()
    try (selName = unsafe { LibC.mallocCString("") }.asResource()) {
        selected = unsafe { LLVMBuildSelect(builderRaw, value, truePtr, falsePtr, selName.value) }
    }
    return selected
}

// int snprintf(char *, size_t, const char *, ...) -- variadic.
private func BuildSnprintfType(i32Type: LLVMTypeRef, i8PtrType: LLVMTypeRef, i64Type: LLVMTypeRef): LLVMTypeRef {
    var result = LLVMNullType()
    try (paramPtr = LibC.malloc<LLVMTypeRef>(count: 3).asResource()) {
        unsafe {
            (paramPtr.value + 0).write(i8PtrType)
            (paramPtr.value + 1).write(i64Type)
            (paramPtr.value + 2).write(i8PtrType)
            // isVarArg = 1 so the trailing value argument is accepted.
            result = LLVMFunctionType(i32Type, paramPtr.value, 3u32, 1)
        }
    }
    return result
}

// A filesystem-safe, content-derived key for a string literal so identical literals share one global.
// Uses an FNV-1a hash of the bytes plus the length to keep names short and collision-resistant. The
// hash multiply/xor deliberately wrap (modular), so the function opts into overflow-wrapping.
@OverflowWrapping
private func CStringLiteralKey(text: String): String {
    var hash: UInt64 = 0xcbf29ce484222325
    var idx = 0
    while (idx < text.size) {
        hash = (hash ^ UInt64(text[idx])) * 0x100000001b3
        idx++
    }
    return text.size.toString() + "_" + hash.toString()
}

private func BuildFnType1(retType: LLVMTypeRef, p0: LLVMTypeRef): LLVMTypeRef {
    var result = LLVMNullType()
    try (paramPtr = LibC.malloc<LLVMTypeRef>(count: 1).asResource()) {
        unsafe {
            (paramPtr.value + 0).write(p0)
            result = LLVMFunctionType(retType, paramPtr.value, 1u32, 0)
        }
    }
    return result
}

private func BuildFnType2(retType: LLVMTypeRef, p0: LLVMTypeRef, p1: LLVMTypeRef): LLVMTypeRef {
    var result = LLVMNullType()
    try (paramPtr = LibC.malloc<LLVMTypeRef>(count: 2).asResource()) {
        unsafe {
            (paramPtr.value + 0).write(p0)
            (paramPtr.value + 1).write(p1)
            result = LLVMFunctionType(retType, paramPtr.value, 2u32, 0)
        }
    }
    return result
}

private func CallFn1(builderRaw: LLVMBuilderRef, fnType: LLVMTypeRef, fn: LLVMValueRef,
    a0: LLVMValueRef): LLVMValueRef {
    var result = LLVMNullValue()
    try (emptyName = unsafe { LibC.mallocCString("") }.asResource(),
        argPtr = LibC.malloc<LLVMValueRef>(count: 1).asResource()) {
        unsafe {
            (argPtr.value + 0).write(a0)
            result = LLVMBuildCall2(builderRaw, fnType, fn, argPtr.value, 1u32, emptyName.value)
        }
    }
    return result
}

private func CallFn2(builderRaw: LLVMBuilderRef, fnType: LLVMTypeRef, fn: LLVMValueRef,
    a0: LLVMValueRef, a1: LLVMValueRef): LLVMValueRef {
    var result = LLVMNullValue()
    try (emptyName = unsafe { LibC.mallocCString("") }.asResource(),
        argPtr = LibC.malloc<LLVMValueRef>(count: 2).asResource()) {
        unsafe {
            (argPtr.value + 0).write(a0)
            (argPtr.value + 1).write(a1)
            result = LLVMBuildCall2(builderRaw, fnType, fn, argPtr.value, 2u32, emptyName.value)
        }
    }
    return result
}

private func GetOrInsertStringRuntimeFn(moduleHandle: LLVMModuleHandle, name: String,
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

private func GetOrInsertStdoutForString(moduleHandle: LLVMModuleHandle, i8PtrType: LLVMTypeRef): LLVMValueRef {
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
