# BLOCKED-REPORT: complete ImplicitImportedFuncMgr wiring

## Status

Correctly blocked on missing named C++ dependencies required by the explicitly requested five function-creation branches. No compiler source change is retained.

The manager, 17-entry registration table, and collection walk can be mapped onto existing selfhost AST and walker APIs. However, the requested complete wiring cannot be ported without first restoring the incremental/CJMP function-creation facilities which are absent from `packages/chir/src/FaithfulAST2CHIR.cj`.

## First missing dependency

The five required C++ insertion sites are:

1. deserialized result in `AST2CHIR::CreateFuncSignatureAndSetGlobalCache` — `src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp:676-684`;
2. newly created result in the same function — `src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp:718-744`;
3. `AST2CHIR::CreatePseudoImportedFuncSignatureAndSetGlobalCache` — `src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp:756-789`;
4. deserialized result in `AST2CHIR::CreateImportedFuncSignatureAndSetGlobalCache` — `src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp:808-816`;
5. newly created result in the same function — `src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp:821-838`.

Selfhost currently has only two unconditional fresh-creation functions:

- `FaithfulAST2CHIR.CreateFuncSignatureAndSetGlobalCache` — `packages/chir/src/FaithfulAST2CHIR.cj:3949-3985`;
- `FaithfulAST2CHIR.CreateImportedFuncSignatureAndSetGlobalCache` — `packages/chir/src/FaithfulAST2CHIR.cj:3987-4000`.

It has no `CreatePseudoImportedFuncSignatureAndSetGlobalCache` and no function-creation `TryGetDeserialized` branch. The only `deserializedVals` declaration is an empty non-incremental placeholder at `FaithfulAST2CHIR.cj:1017-1019`; the file explicitly states that binary CHIR deserialization has not populated it.

The first required missing API is the complete `AST2CHIR::TryGetDeserialized<T>(const AST::Decl&)` facility at `include/cangjie/CHIR/AST2CHIR/AST2CHIR.h:336-369`. It depends on these missing named facilities/state:

- `AST2CHIR::MaybeDeserialized` — `AST2CHIR.h:338-339`;
- `AST2CHIR::deserializedDefs` and the populated `deserializedVals` table;
- `AST2CHIR::noNeedToTranslateDecls` and its pointer-identity membership update at `AST2CHIR.h:362-367`;
- `AST2CHIR::BuildDeserializedTable` — `ASTPackage2CHIR.cpp:1673-1682`;
- `AST2CHIR::ResetSpecificFunc` — `ASTPackage2CHIR.cpp:1684` onward;
- the `IncreKind`/CJMP selection which calls `CreatePseudoImportedFuncSignatureAndSetGlobalCache` at `ASTPackage2CHIR.cpp:670-673`.

This dependency set exceeds the proportional exception: although the `TryGetDeserialized` template body itself is 28 lines, its prerequisites are not present and the required named implementation spans multiple functions, state tables, pointer-identity state, and incremental pipeline wiring. Pointer identity is also an explicitly listed system root in `AGENTS.md`; replacing it with name/string identity is forbidden.

## Why a partial patch is invalid

Adding `implicitDecls.Contains(funcDecl)` only after the two existing selfhost fresh creations would cover C++ sites 2 and 5 while silently omitting sites 1, 3, and 4. Adding three synthetic inserts elsewhere would not correspond to the C++ branch structure. Both would violate the task's “五处函数创建分支接线” requirement and the no-silent-omission rule.

Likewise, retaining a manager/registration/collection-only diff would be an incomplete facility and would leave the exact requested downstream map semantics dependent on the existing broad `PopulateRealCodegenImplicitFuncs` scan (`packages/frontend/src/CodeGenBridge.cj:484-490`), which has no matching C++ named entity. That would not be faithful completion.

## Required restoration API

A dedicated dependency lane must first restore the complete selfhost equivalents of:

1. `MaybeDeserialized(const AST::Decl&)`;
2. `TryGetDeserialized<T>(const AST::Decl&)`, including exact foreign-key selection and pointer-identity `noNeedToTranslateDecls` insertion;
3. population of `deserializedDefs`/`deserializedVals` through `BuildDeserializedTable`;
4. `ResetSpecificFunc` in full;
5. the `IncreKind::INCR && !funcDecl.toBeCompiled && !IsSrcCodeImportedGlobalDecl(...)` branch and `CreatePseudoImportedFuncSignatureAndSetGlobalCache`.

After those APIs are merged, resume this lane. It can then port all five implicit-map insertion sites, rather than only the two currently representable sites, together with the manager, all 17 registrations, collection ordering, and exact codegen-map propagation.

## Mechanical audit

Platform grep command:

```text
rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" include/cangjie/CHIR/AST2CHIR/ImplicitImportedFuncMgr.h src/CHIR/AST2CHIR/ImplicitImportedFuncMgr.cpp src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp src/CHIR/AST2CHIR/AST2CHIR.cpp
```

Relevant raw output for the requested facility is empty; it has no platform-specific branches.

Gate and `01_return -Os` KEEP_TYPES measurements were not rerun because no compiler source fix exists. The baseline evidence remains `self ALLOCA_COUNT=11` versus `ref ALLOCA_COUNT=15` from `BLOCKED-REPORT-oskeeptypes.md`.

- 无任何 grep 不到 C++ 出处的新编译器符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的缺失 named C++ 设施与 pointer-identity 系统根已 BLOCKED 上报、未自行替代。
