# BLOCKED-REPORT: Os/Oz type-anchor alloca

## Status

Correctly blocked on a missing named C++ facility. No compiler source change is retained.

The first missing facility is the complete implicit-imported-function collection mechanism:

- `ImplicitImportedFunc` and `ImplicitImportedFuncMgr` — `include/cangjie/CHIR/AST2CHIR/ImplicitImportedFuncMgr.h:16-69`
- `ImplicitImportedFuncMgr::{Instance, RegImplicitImportedFunc, GetImplicitImportedFuncs}` — `src/CHIR/AST2CHIR/ImplicitImportedFuncMgr.cpp:12-44`
- the complete registration table — `src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp:27-44`
- `AST2CHIR::{AddToImplicitFuncs, CollectImplicitFuncs}` — `src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp:99-159`
- the required call before imported-declaration collection — `src/CHIR/AST2CHIR/AST2CHIR.cpp:301-316`
- `AST2CHIR::implicitDecls` and its function-creation integration — `include/cangjie/CHIR/AST2CHIR/AST2CHIR.h:413-414` and `src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp:682-684,742-744,785-787,814-816,836-838`

`rg` finds none of `ImplicitImportedFuncMgr`, `CollectImplicitFuncs`, `AddToImplicitFuncs`, or `implicitDecls` in `packages/chir/src`. Selfhost has a downstream codegen implicit-function map, but not the named AST2CHIR collection facility that populates it with the C++ rules.

This dependency is larger than the <=40-line proportional exception: it spans a manager type and two three-way APIs, 17 registrations, the two collection functions, ordered pipeline wiring, a persistent declaration set, and five function-creation branches. Implementing a local list of four types or a special case in `KeepSomeTypesManually` would be a forbidden downstream compensation.

## Reproduction evidence

Exact command shape from `OPT_SIZE_SWEEP.md` was used for both compilers:

```text
<compiler> scripts/difftest_corpus/01_return.cj -Os --experimental --output-type=obj --compile-target exe --save-temps <dir> -o out.o
```

Raw result:

```text
REPRO level=Os sample=01_return REF_COMPILE_RC=0 SELFHOST_COMPILE_RC=0 REF_VERIFY_RC=0 SELFHOST_VERIFY_RC=0
KEEP_TYPES side=ref ALLOCA_COUNT=15
KEEP_TYPES side=self ALLOCA_COUNT=11
```

The four reference-only allocas are:

```llvm
%0 = alloca %ArrayLayout.Rune, align 8
%5 = alloca %"ObjLayout.std.core:ArrayIterator<T>", align 8
%8 = alloca %"ObjLayout.std.core:IndexOutOfBoundsException", align 8
%12 = alloca %"enum.std.core:Option<Rune>", align 8
```

Both functions end in `ret void`. Both pre-opt modules pass LLVM 15 verification.

The checked-in before matrix remains:

```text
BC_MATRIX level=Os TOTAL=114 PASS=0 COMPILE_OK_BOTH=114 VERIFY_OK_BOTH=114 SHARED_FUNCTIONS=2248 IDENTICAL_FUNCTIONS=2023 ONE_SIDE_FUNCTIONS=223
BC_MATRIX level=Oz TOTAL=114 PASS=0 COMPILE_OK_BOTH=114 VERIFY_OK_BOTH=114 SHARED_FUNCTIONS=2248 IDENTICAL_FUNCTIONS=2023 ONE_SIDE_FUNCTIONS=223
```

## Upstream trace

`KeepSomeTypesManually` itself already mirrors the C++ loop:

- C++ `void KeepSomeTypesManually(CGModule&)` at `src/CodeGen/EmitPackageIR.cpp:175-206`; its only emission branch is `structType && structType->isSized()` at lines 199-203.
- selfhost `KeepSomeTypesManually(CGModule)` at `packages/codegen/src/EmitPackageIR.cj:968-998`; it iterates `GetGeneratedStructType()` and uses the same non-null/sized condition at lines 984-989.

Therefore adding four names there would not mirror any C++ branch.

The reference CHIR dump contains the optimized imported instantiation
`_CINat13ArrayIteratorIG_E4nextHv$c` (`ArrayIterator<Rune>.next`), while the selfhost CHIR dump contains no such function. Its body mechanically accounts for the four missing layout families: `ArrayIterator<Rune>`, `Option<Rune>`, `RawArray<Rune>`, and the `IndexOutOfBoundsException` allocation/raise branch.

The next C++ layer responsible for retaining functions used implicitly only by codegen is explicitly documented at `AST2CHIR.cpp:304-310` and is absent from selfhost. In particular, the registration table contains `IndexOutOfBoundsException.init` at `ASTPackage2CHIR.cpp:29`, and `CollectImplicitFuncs` scans imported generic instantiations before ordinary imported-declaration collection at `ASTPackage2CHIR.cpp:136-153`. Faithful tracing cannot continue past this point until that named facility exists.

## Required restoration API

A dedicated dependency lane must port the complete facility, not a task-specific subset:

1. `ImplicitImportedFunc` with `parentKind`, `identifier`, and `parentName`.
2. `ImplicitImportedFuncMgr.FuncKind` with `GENERIC` and `NONE_GENERIC`.
3. `Instance`, `RegImplicitImportedFunc`, and `GetImplicitImportedFuncs`, including deterministic `parentName + identifier` sorting and all invalid-kind branches.
4. All registrations at `ASTPackage2CHIR.cpp:27-44`.
5. `AST2CHIR.AddToImplicitFuncs` including sancov handling and exact parent-name/parent-kind matching.
6. `AST2CHIR.CollectImplicitFuncs`, scanning every imported package's `genericInstantiatedDecls` and all std.core top-level declarations.
7. The ordered `CollectImplicitFuncs()` call before `CollectImportedDecls()`.
8. The `implicitDecls` membership branches in every C++ function-creation path listed above, and propagation through the already-existing selfhost implicit-function/codegen data path.

After that dependency is merged, resume this lane and repeat the 01_return trace. Only then can it be determined mechanically whether the complete facility resolves all four allocas or exposes the next missing named dependency for the `ArrayIterator<Rune>.next` instance.

## Delivery audit

- Platform grep command:

  ```text
  rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" src/CHIR/AST2CHIR/ImplicitImportedFuncMgr.cpp src/CHIR/AST2CHIR/ASTPackage2CHIR.cpp include/cangjie/CHIR/AST2CHIR/ImplicitImportedFuncMgr.h
  ```

  Raw output: empty; the missing facility has no platform branches.
- Full-branch coverage: N/A because the named dependency was not ported. Its complete three-way manager branches and all collection branches are explicitly required above; none was silently omitted into a partial implementation.
- Os/Oz matrix after numbers and `/tmp/audit/verify.sh`: intentionally not run after the blocker was proven, because no compiler fix exists to validate.
- No temporary instrumentation remains in the source tree.
- 无任何 grep 不到 C++ 出处的新编译器符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的缺失 named C++ 设施已 BLOCKED 上报、未自行替代。

