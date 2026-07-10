# GC_KLASS_ATTR consumption-point audit

## Result

The requested wiring is already present in baseline `master` at `74d4fe37`; no
compiler-source change is required.  The C++ tree has five `GC_KLASS_ATTR`
emission statements, and the baseline self-host tree has all five corresponding
`addAttribute(..., GC_KLASS_ATTR)` calls.  The baseline also already contains the
prepared FFI declaration, its Cangjie wrapper, and the C++ shim implementation.

Changing a working emission point merely to manufacture a code diff would not be
a faithful port.  This task therefore produces only this audit report commit.

## C++ to self-host symbol map

1. `CGType::GetOrCreateTypeInfo()` —
   `/root/cj_build/cangjie_compiler/src/CodeGen/Base/CGTypes/CGType.cpp:229`;
   the relevant call is `typeInfo->addAttribute(GC_KLASS_ATTR)` at line 250.
   Existing mirror: `DeclareTypeInfoGlobal` calls
   `addAttribute(typeInfo, GC_KLASS_ATTR)` at
   `packages/codegen/src/CGTypeInfo.cj:85` for `STATIC_GI` and `CONCRETE`.
2. `CGModule::InitRawArrayUInt8Constants() const` —
   `/root/cj_build/cangjie_compiler/src/CodeGen/CGModule.cpp:572`;
   `gvUInt8Ti->addAttribute(GC_KLASS_ATTR)` is at line 590 and adjacent
   `NOT_MODIFIABLE_CLASS_ATTR` is at line 591.  Existing mirrors are
   `packages/codegen/src/EmitCjStringLiteralIR.cj:128-129`.
3. `GetReadOnlyArrayKlassInfo(const CGModule&)` —
   `/root/cj_build/cangjie_compiler/src/CodeGen/CJNative/EmitPackageIR.cpp:685`;
   `gv->addAttribute(GC_KLASS_ATTR)` is at line 701.  Existing mirror:
   `packages/codegen/src/EmitCjStringLiteralIR.cj:155`.
4. `PkgMetadataInfo::AddPrimitiveTypeInfoToCorePkgInfo() const` —
   `/root/cj_build/cangjie_compiler/src/CodeGen/CJNative/CJNativeGenMetadata.cpp:287`;
   `ti->addAttribute(GC_KLASS_ATTR)` is at line 296.  Existing mirror:
   `packages/codegen/src/CJNativeGenMetadata.cj:605`.
5. `EnumCtorTIOrTTGenerator::GenerateNonGenericEnumCtorTypeInfo(llvm::GlobalVariable&)`
   — `/root/cj_build/cangjie_compiler/src/CodeGen/CJNative/CGTypes/EnumCtorTIOrTTGenerator.cpp:176`;
   `ti.addAttribute(GC_KLASS_ATTR)` is at line 237.  Existing mirror:
   `packages/codegen/src/EnumCtorTIOrTTGenerator.cj:156`.

The shared consumer is also already wired field-for-field:

- C++ LLVM API: `GlobalVariable::addAttribute(StringRef Kind, StringRef Val)`;
  the project shim calls `unwrap<GlobalVariable>(GV)->addAttribute(StringRef(K,
  KLen), StringRef(V, VLen))` at `runtime_shim/cjselfhost_llvmshim.cpp:130-132`.
- Cangjie declaration: `LLVMGlobalObjectAddStringAttribute(gv, k, kLen, v,
  vLen)` at `packages/codegen/src/LLVM.cj:248-249`.
- Cangjie wrapper: `addAttribute(gv, name, value)` passes both explicit byte
  lengths at `packages/codegen/src/IRAttribute.cj:238-246`.

There are no newly added or modified functions/helpers in this task.

## Completeness and branches

Mechanical occurrence counts:

```text
C++ GC_KLASS_ATTR emission statements: 5
self-host GC_KLASS_ATTR emission statements: 5
missing mapped emission statements: 0
```

All five task-specific emission sites are covered, including their controlling
paths: existing-global guard for `UInt8.ti`, existing-global early return for
`RawArray<UInt8>.ti`, the primitive-TI loop, the static/concrete generic-kind
selection, and unconditional enum-constructor TI emission.  The two adjacent
attributes on the same emission surface (`NOT_MODIFIABLE_CLASS_ATTR` and
`HasExtPart`) are present where C++ emits them.

Platform grep over the five C++ source files returned:

```text
CodeGen/Base/CGTypes/CGType.cpp:395:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/Base/CGTypes/CGType.cpp:429:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CJNative/CGTypes/EnumCtorTIOrTTGenerator.cpp:11:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CGModule.cpp:17:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CGModule.cpp:60:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CGModule.cpp:85:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CGModule.cpp:94:#ifdef __APPLE__
CodeGen/CGModule.cpp:123:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CGModule.cpp:211:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CGModule.cpp:290:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CGModule.cpp:346:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CGModule.cpp:391:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CGModule.cpp:440:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
CodeGen/CGModule.cpp:545:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
```

None of those preprocessor branches encloses a task-specific attribute emission.
The platform-dependent linkage branches adjacent to the raw-array and enum-ctor
emissions are already mirrored with `target.os != OSType.WINDOWS` at
`EmitCjStringLiteralIR.cj:156` and `EnumCtorTIOrTTGenerator.cj:157`.

## Product evidence

`runtime_shim/build_shim.sh` exported the prepared entry point:

```text
built: /root/cj_build/wt/fix_gcklass/runtime_shim/cjselfhost_llvmshim.o
0000000000000000 T LLVMGlobalObjectAddStringAttribute
```

An explicit `cjpm build` ended with:

```text
cjpm build success
```

Two `--save-temps` probes were disassembled with the toolchain `llvm-dis`:

- `scripts/difftest_corpus/30_class_basic.cj`: both self-host and reference
  attach `attributes #0 = { "CFileKlass" "HasExtPart" }` to
  `@"default:C.ti"`.
- `scripts/difftest_corpus/21_enum_pl.cj`: both self-host and reference attach
  `attributes #1 = { "CFileKlass" }` to each of
  `@"default:C:0.ti"`, `@"default:C:1.ti"`, and `@"default:C:2.ti"`.

Full gate command:

```text
bash /tmp/audit/verify.sh /root/cj_build/wt/fix_gcklass full gcklass
```

Raw result lines:

```text
difftest: TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
smoke15: PASS=15 FAIL=0
bcgate: shared functions: 2490  |  byte-identical: 2490 (100.0%)  |  differing: 0 | fully-identical samples: 114/114  |  compile-errors: 0
VERIFY-EXIT=0
```

## Required declarations

1. 无任何 grep 不到 C++ 出处的新符号（本任务未新增源码符号）。
2. 未改业务源码绕过、未加 band-aid 吞 bug。
3. 未撞到缺失系统根；既有 global-variable `addAttribute` FFI 已验证导出并实际发射，未自行替代。

已覆盖本任务枚举出的全部 5 个 C++ `GC_KLASS_ATTR` 发射点；无静默遗漏。
