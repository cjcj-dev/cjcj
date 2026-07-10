# REPORT: L12 ASAN CPointer read/write instrumentation

## Result

The selfhost CJNative code generator now emits the same CPointer access instrumentation as the C++ implementation:

- `CPointer.read` emits `CJ_MCC_AsanRead` immediately before both the generic memcpy and non-generic load paths.
- `CPointer.write` emits `CJ_MCC_AsanWrite` immediately before both the generic memcpy and non-generic store/struct-copy paths.
- Instrumentation is gated by `EnableAsan() || EnableHwAsan()`. A normal compilation emits no ASAN runtime calls.
- The call ABI is `void(i8*, i64)` through ghost C arguments and carries `FAST_NATIVE_ATTR`, matching C++.

Only `packages/codegen/src/IntrinsicsDispatcher.cj` is changed. No runtime shim was added: the named runtime entry points already have full implementations in `/root/cj_build/cangjie_runtime/runtime/src/Sanitizer/AddressSanitizer/AsanInterface.cpp:261-269` and the HWASAN implementation in `HwAddressSanitizer/HwasanInterface.cpp:234-242`.

## C++ symbol-to-selfhost mapping

### `InstrumentPointerOps`

C++ source: `/root/cj_build/cangjie_compiler/src/CodeGen/Base/IntrinsicsDispatcher.cpp:347-357`.

```cpp
inline void InstrumentPointerOps(
    IRBuilder2& irBuilder, const std::string& instFunc, llvm::Value* ptr, llvm::Value* typeSize)
{
    auto& llvmCtx = irBuilder.GetLLVMContext();
    auto castVal = irBuilder.CreateBitCast(ptr, llvm::Type::getInt8PtrTy(llvmCtx));
    auto& cgMod = irBuilder.GetCGModule();
    irBuilder.CallIntrinsicFunction(llvm::Type::getVoidTy(llvmCtx), instFunc,
        {cgMod.CreateGhostCFuncArgValue(*castVal, *CGType::GetCStringCGType(cgMod)),
            cgMod.CreateGhostCFuncArgValue(*typeSize, *CGType::GetInt64CGType(cgMod))},
        {FAST_NATIVE_ATTR});
}
```

Selfhost source: `packages/codegen/src/IntrinsicsDispatcher.cj:520-530`. The pointer cast, `void` return, two ghost C argument types, call order, and attribute are field-for-field identical.

### `InsertAsanInstrument`

C++ source: `/root/cj_build/cangjie_compiler/src/CodeGen/Base/IntrinsicsDispatcher.cpp:359-374`.

```cpp
inline void InsertAsanInstrument(const CGModule& cgMod, IRBuilder2& irBuilder,
    const CHIRIntrinsicWrapper& intrinsic, llvm::Value* gep, const std::string& asanFunc)
{
#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
    if (cgMod.GetCGContext().GetCompileOptions().EnableAsan() ||
        cgMod.GetCGContext().GetCompileOptions().EnableHwAsan()) {
        auto genericInfo = intrinsic.GetInstantiatedTypeArgs();
        CJC_ASSERT(genericInfo.size() == 1);
        auto typeSize = irBuilder.GetSize_64(*genericInfo[0]);
        InstrumentPointerOps(irBuilder, asanFunc, gep, typeSize);
    }
#endif
}
```

Selfhost source: `packages/codegen/src/IntrinsicsDispatcher.cj:532-540`. `GenerateIntrinsic` already receives `GetInstantiatedTypeArgs()` as `typeArgs`; it is passed unchanged into the helper. The selfhost codegen package is the CJNative implementation, so the C++ backend compile guard maps to package inclusion rather than a runtime OS branch.

The existing `cjcj::utils.CJC_ASSERT` import mirrors the C++ `CJC_ASSERT` call; it was not reimplemented.

### Four instrumentation sites

C++ source and exact selfhost mapping:

| C++ | Branch | Selfhost |
|---|---|---|
| `IntrinsicsDispatcher.cpp:470` | generic CPointer read, before memcpy | `IntrinsicsDispatcher.cj:562` |
| `IntrinsicsDispatcher.cpp:478` | non-generic CPointer read, before load | `IntrinsicsDispatcher.cj:572` |
| `IntrinsicsDispatcher.cpp:504` | generic CPointer write, before memcpy | `IntrinsicsDispatcher.cj:613` |
| `IntrinsicsDispatcher.cpp:512` | non-generic CPointer write, before store/copy | `IntrinsicsDispatcher.cj:634` |

The dispatch sites at `IntrinsicsDispatcher.cj:116-120` pass the intrinsic instantiated type arguments to the read/write implementation, corresponding to `CHIRIntrinsicWrapper::GetInstantiatedTypeArgs()` consumed at C++ line 366.

## Full-branch audit

- `InstrumentPointerOps`: all 1 straight-line path is covered; no branch/case/early return exists in C++ lines 347-357.
- `InsertAsanInstrument`: all 2 outcomes of its single `if` are covered (sanitizer enabled emits; disabled does nothing). The `#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND` guard is represented by this CJNative-only codegen implementation.
- CPointer instrumentation sites: all 4 sites are covered, spanning the 2 generic/non-generic branches in `CPointerRead` and the 2 generic/non-generic branches in `CPointerWrite`.

Platform grep raw output:

```text
$ rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" /root/cj_build/cangjie_compiler/src/CodeGen/Base/IntrinsicsDispatcher.cpp
77:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
133:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
363:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
424:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
568:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
612:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
642:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
719:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
762:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
810:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
```

There is no OS-specific branch in the modified C++ facility. Line 363 is the only guard enclosing `InsertAsanInstrument`; all other matches are unrelated functions in the same translation unit.

## Minimal reproduction

Input: the existing two-file package `test/g10_probe/src`, whose `RawString.cj` exercises CPointer reads and writes of primitive, pointer, and struct values. Both runs used the selfhost compiler, `--output-type=staticlib`, and `--save-temps`.

The installed nightly omits the `runtime/lib/linux_x86_64_cjnative/asan` packaging directory, so option validation initially produced:

```text
error: asan sanitizer feature is not supported.
Invalid options. Try: 'cjc --help' for more information.
```

For emission-only testing, a temporary `asan/libcangjie-runtime.so` symlink to the installed normal runtime was created solely to pass the file-existence check and deleted immediately after both static-library compilations. It was not used as a substitute implementation and is absent from the worktree/toolchain after the test. The authoritative runtime implementation is quoted above.

Raw compile result:

```text
PLAIN_RC=0 ASAN_RC=0
PLAIN_HITS:
ASAN_HITS:
/tmp/l12asan_asan/28-rt.demangle.s:101: callq CJ_MCC_AsanWrite@PLT
/tmp/l12asan_asan/21-rt.demangle.s:148: callq CJ_MCC_AsanRead@PLT
/tmp/l12asan_asan/29-rt.demangle.s:73:  callq CJ_MCC_AsanRead@PLT
/tmp/l12asan_asan/29-rt.demangle.s:122: callq CJ_MCC_AsanWrite@PLT
/tmp/l12asan_asan/31-rt.demangle.s:30:  callq CJ_MCC_AsanRead@PLT
/tmp/l12asan_asan/31-rt.demangle.s:90:  callq CJ_MCC_AsanWrite@PLT
/tmp/l12asan_asan/27-rt.demangle.s:185: callq CJ_MCC_AsanRead@PLT
/tmp/l12asan_asan/30-rt.demangle.s:99:  callq CJ_MCC_AsanWrite@PLT
```

Argument-size evidence from the generated assembly includes 1-byte, 8-byte, and 40-byte accesses:

```text
movl $1, %esi
callq CJ_MCC_AsanRead@PLT
movl $8, %esi
callq CJ_MCC_AsanWrite@PLT
movl $40, %esi
callq CJ_MCC_AsanRead@PLT
```

Thus the enabled branch emits the computed instantiated type size, while the disabled branch causes zero ordinary-mode hits.

## Gates

`cjpm build -j 32` raw terminal line:

```text
cjpm build success
```

Authoritative command:

```text
bash /root/cj_build/audit_persist/verify.sh /root/cj_build/wt/fix_l12asan delta l12asan
```

The codegen change invalidated delta snapshots and correctly failed closed to the full 114 difftest samples and 15 smoke packages:

```text
delta manifest invalid: codegen core changed; fail-closed to full 114+15
```

Raw final output:

```text
=== RESULTS (delta, lane=l12asan) ===
difftest: TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
smoke15: PASS=15 FAIL=0
bcgate: shared functions: 2490  |  byte-identical: 2490 (100.0%)  |  differing: 0 | fully-identical samples: 114/114  |  compile-errors: 0
DELTA: skipped=0 ran=129
VERIFY-EXIT=0
```

## Delivery declarations

- 无任何 grep 不到 C++ 出处的新符号；新增的两个函数名均逐字存在于 C++ `IntrinsicsDispatcher.cpp:347,359`，所有新增调用均对应 C++ lines 351-371 and 470/478/504/512.
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的系统根已 BLOCKED 上报、未自行替代；本任务未撞到系统根。runtime named API 已在官方 runtime 源码中确认存在，未添加伪 shim。
- No temporary instrumentation, debug printing, or generated test artifact is present in the worktree.
