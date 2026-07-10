# sc_bcgate differing-function cluster inventory

## Outcome

Archived baseline (`74d4fe37`):

```text
TOTAL: shared=14506 byte-identical=10965 (75.6%) differing=3541
```

Reproduction on the same commit and this worktree:

```text
TOTAL: shared=14516 byte-identical=10953 (75.5%) differing=3563
```

The run is close but not bit-for-bit stable: it has 10 more shared functions and
22 more differing functions.  The only package-level count changes are:

| package | archived shared/differing | reproduced shared/differing | delta differing |
|---|---:|---:|---:|
| `frontend_tool` | 291 / 31 | 292 / 32 | +1 |
| `driver` | 711 / 186 | 711 / 182 | -4 |
| `codegen` | 2666 / 841 | 2675 / 866 | +25 |

Therefore this inventory contains all **3,563 functions actually observed** in
the required 15-package reproduction, rather than silently dropping 22 rows to
force the archived total of 3,541.  All other package totals reproduce exactly.

Of the 3,563 rows, **1,866 (52.4%) are functional-first** and **1,697 (47.6%)
are cosmetic**.  “Cosmetic” is intentionally narrow: the complete normalized
function must become identical after replacing only numeric named-metadata IDs.
Everything else is conservatively functional.

## Method and artifacts

Build and gate commands:

```sh
bash runtime_shim/build_shim.sh
cjpm build
python3 scripts/sc_bcgate.py option conditional_compilation mangle frontend_tool \
  incremental_compilation modules driver meta_transformation lex ast frontend \
  cjc basic codegen macro \
  --self /root/cj_build/wt/fix_scdiffinv/target/release/bin/cjcj::cjc --timeout 600
```

`scripts/sc_diff_clusters.py` disassembles every non-optimized `.bc` with
`llvm-dis`, applies exactly `bcgate.norm_ir`, matches functions by mangled name,
and writes [SC_DIFF_FUNCTIONS.tsv](SC_DIFF_FUNCTIONS.tsv).  The TSV retains both:

- the literal first `SequenceMatcher` edit (`raw_first_*`); and
- the first semantic edit after canonicalizing only named-metadata numbers
  (`semantic_first_*`).

This distinction matters.  For example, `!ReflectionFunc !48` versus
`!ReflectionFunc !67` is cosmetic if it is the function's only difference,
whereas presence versus absence of `!untrusted_ref` remains functional.
SSA names, basic-block names, and generated hash suffixes were already
canonicalized by `bcgate`; consequently the block clusters below are not mere
label spelling changes.

## Functional-first attack order

The score is `function count × functional`, with functional represented as 1
and cosmetic as 0.  Ties are sorted by function count.

| rank | named cluster | functions | impact | score | first C++ facility to audit |
|---:|---|---:|---|---:|---|
| 1 | `CG-METADATA-ATTACHMENT` | 728 | functional | 728 | `IRBuilder2::CreateLoad`, `CodeGen/IRBuilder.cpp:167` |
| 2 | `CG-CALLSITE-ATTRIBUTE` | 281 | functional | 281 | `IRBuilder2::CreateCallOrInvoke`, `CodeGen/IRBuilder.cpp:53` |
| 3 | `CG-MISSING-CALL` | 215 | functional | 215 | expression dispatch, `CodeGen/EmitExpressionIR.cpp:67` |
| 4 | `CG-MANGLED-GLOBAL-REFERENCE` | 199 | functional | 199 | `BaseMangler::Mangle`, `Mangle/BaseMangler.cpp:491` |
| 5 | `CG-BLOCK-LAYOUT` | 118 | functional | 118 | `IRBuilder2::CreateAndInsertBasicBlocks`, `CodeGen/IRBuilder.cpp:199` |
| 6 | `CG-BRANCH-OPERAND` | 104 | functional | 104 | `EmitBasicBlockIR`, `CodeGen/EmitFunctionIR.cpp:210` |
| 7 | `CG-ICMP-PREDICATE` | 75 | functional | 75 | logical signedness maps, `CodeGen/Base/LogicalOpImpl.cpp:34` |
| 8 | `CG-OPERAND-OR-TYPE` | 51 | functional | 51 | typed GEP/load builders, `CodeGen/IRBuilder.h:106` |
| 9 | `CG-INSTRUCTION-SELECTION` | 48 | functional | 48 | expression-major-kind dispatch, `CodeGen/EmitExpressionIR.cpp:68` |
| 10 | `CG-EXTRA-CALL` | 16 | functional | 16 | `GenerateFuncPtrForNonAutoEnv`, `CodeGen/Base/InvokeImpl.cpp:49` |
| 11 | `CG-CALL-TARGET` | 12 | functional | 12 | `IRBuilder2::CreateCallOrInvoke`, `CodeGen/IRBuilder.cpp:36` |
| 12 | `CG-MISSING-INSTRUCTION` | 10 | functional | 10 | `KeepSomeTypesManually`, `CodeGen/EmitPackageIR.cpp:175` |
| 13 | `CG-EXTRA-INSTRUCTION` | 8 | functional | 8 | `KeepSomeTypesManually`, `CodeGen/EmitPackageIR.cpp:175` |
| 14 | `CG-CALL-ORDER` | 1 | functional | 1 | expression iteration order, `CodeGen/EmitExpressionIR.cpp:57` |
| 15 | `CG-METADATA-NUMBERING` | 1697 | cosmetic | 0 | `GenerateFunctionsMetadata`, `CodeGen/CJNative/CJNativeGenMetadata.cpp:690` |

These are root **hypotheses for the next attack stage**, not claims that every
member has already been proven to share one upstream defect.  Each hypothesis
is anchored to the first named C++ facility that directly owns the observed IR
shape; the TSV is the drill-down list for minimization and instrumentation.

## Cluster evidence

### `CG-METADATA-ATTACHMENT` — 728, functional

Representatives:

1. `conditional_compilation::_CN28cjcj:conditional_compilation26ConditionalCompilationImpl13EvalParenExprHCN8cjcj:ast9ParenExprE`
2. `conditional_compilation::_CN28cjcj:conditional_compilation26ConditionalCompilationImpl14CheckParenExprHCN8cjcj:ast9ParenExprE`
3. `conditional_compilation::_CN28cjcj:conditional_compilation26ConditionalCompilationImpl15CheckBinaryExprHCN8cjcj:ast10BinaryExprE`

```diff
- %v13 = call i8 addrspace(1)* @llvm.cj.gcread.ref(...), !untrusted_ref !N
+ %v13 = call i8 addrspace(1)* @llvm.cj.gcread.ref(...)
```

Root hypothesis: faithfully audit `IRBuilder2::CreateLoad`, which attaches
`untrusted_ref` when the original element type is enum
(`CodeGen/IRBuilder.cpp:167-170`).  Attachment presence can affect GC and later
passes, so this is functional rather than numbering noise.

### `CG-CALLSITE-ATTRIBUTE` — 281, functional

Representatives:

1. `option::_CN11cjcj:option13GlobalOptions17GetLtoVisiblePkgsHv`
2. `option::_CN11cjcj:option7ArgList9GetInputsHv`
3. `frontend_tool::_CN18cjcj:frontend_tool15ExecuteFrontendHRNat6StringECNac9ArrayListIY2_ECNac7HashMapIY2_Y2_E`

```diff
- call void @_CNac9ArrayListIG_E7toArrayHv(%v1* noalias sret(%v1) %v6, ...)
+ call void @_CNac9ArrayListIG_E7toArrayHv(%v1* noalias sret(i8) %v6, ...)
```

Root hypothesis: `IRBuilder2::CreateCallOrInvoke` copies the callee's typed
struct-return attribute at `CodeGen/IRBuilder.cpp:67-72`; the attribute creator
is `AddSRetAttribute` at `CodeGen/IRAttribute.h:46-54`.

### `CG-MISSING-CALL` — 215, functional

Representatives:

1. `option::_CN11cjcj:option22GetHardwareConcurrencyHv`
2. `option::_CN11cjcj:optionUOptionAction$14parseJobsValueHRNat6StringEY4_`
3. `option::_CN11cjcj:optionUOptionAction$15parseErrorLimitHCNY0_13GlobalOptionsECNY0_17OptionArgInstanceE`

```diff
- %v13 = zext i32 %v4 to i64
+ br label %v13
```

The cluster has fewer call/invoke targets on selfhost, even where an earlier
non-call instruction is the literal first edit.  Root hypothesis: start at the
complete expression-major-kind dispatch in `EmitExpressionIR`
(`CodeGen/EmitExpressionIR.cpp:67-92`) and follow the missing CHIR expression to
`IRBuilder2::CreateCallOrInvoke` (`CodeGen/IRBuilder.cpp:36-74`).

### `CG-MANGLED-GLOBAL-REFERENCE` — 199, functional

Representatives:

1. `option::_CN11cjcj:option13GlobalOptions36PassedWhenKeyValueToSerializedStringHv`
2. `option::_CNat5ArrayICN11cjcj:optionUOption$7CfgPairEE6<init>Hv`
3. `mangle::_CN11cjcj:mangle10ASTMangler24MangleGenericConstraintsHCNY_13MangleGenericE`

```diff
- @"std.collection:ArrayList<cjcj/option:_CN11cjcj:optionUOption$7CfgPairE>.ti"
+ @"std.collection:ArrayList<cjcj/option:CfgPair>.ti"
```

Root hypothesis: `BaseMangler::Mangle` selects the declaration-specific path at
`Mangle/BaseMangler.cpp:491-508`, while `BaseMangler::MangleDecl` constructs the
prefix/identifier/generic suffix at `Mangle/BaseMangler.cpp:572-641`.

### `CG-BLOCK-LAYOUT` — 118, functional

Representatives:

1. `option::_CN11cjcj:option13GlobalOptions13ParseFromArgsHCNY_7ArgListE`
2. `option::_CN11cjcj:option13GlobalOptions23GenerateFrontendOptionsHv`
3. `option::_CN11cjcj:option13GlobalOptions24CollectOrderedInputFilesHCNY_12ArgListEntryEm`

```diff
- L3: ; preds = %v36, %v37, %v38, %v39
+ L3: ; preds = %v36, %v37, %v38
```

Root hypothesis: block creation/insertion order is owned by
`IRBuilder2::CreateAndInsertBasicBlocks` (`CodeGen/IRBuilder.cpp:199-210`).
Because label spelling was canonicalized and the predecessor set differs, this
is functional CFG shape, not cosmetic block naming.

### `CG-BRANCH-OPERAND` — 104, functional

Representatives:

1. `option::_CN11cjcj:option11ParseActionHCNY_13GlobalOptionsECNY_17OptionArgInstanceE`
2. `option::_CN11cjcj:option13GlobalOptions13ProcessInputsHRNat5ArrayIRNat6StringEE`
3. `conditional_compilation::_CN28cjcj:conditional_compilation26ConditionalCompilationImpl23EvalCachedConditionExprHCN8cjcj:ast4ExprE`

```diff
- br i1 %v1335, label %v1295, label %v1336
+ br i1 %v1335, label %v1336, label %v1337
```

Root hypothesis: audit CHIR block mapping at the `EmitBasicBlockIR` entry in
`CodeGen/EmitFunctionIR.cpp:210-211`, then the terminator handler selected by
`CodeGen/EmitExpressionIR.cpp:68-71`.

### `CG-ICMP-PREDICATE` — 75, functional

Representatives:

1. `conditional_compilation::_CN28cjcj:conditional_compilation26MakeJudgeConditionCacheKeyHRNat6StringENN8cjcj:lex9TokenKindEY2_`
2. `incremental_compilation::_CN28cjcj:incremental_compilation15HashedASTLoader10fillCommonHCNac9ArrayListIRNat6StringEECNY_13DeclCacheBaseE`
3. `incremental_compilation::_CN28cjcj:incremental_compilation18ASTCacheCalculator11VisitMemberHCNY_8IncrDeclE`

```diff
- %v43 = icmp ule i64 %v38, 255
+ %v43 = icmp sle i64 %v38, 255
```

Root hypothesis: signed versus unsigned comparison selection is explicit in
the `mapForUnsigned` and `mapForOthers` tables in
`CodeGen/Base/LogicalOpImpl.cpp:34-48`.

### `CG-OPERAND-OR-TYPE` — 51, functional

Representatives:

1. `driver::_CNatXPPu4readHl`
2. `driver::_CNatXPPu5writeHlPu`
3. `driver::_CNatXPh4readHl`

```diff
- %v9 = getelementptr inbounds i8*, i8** %v8, i64 %v2
+ %v9 = getelementptr i8*, i8** %v8, i64 %v2
```

Root hypothesis: audit typed/inbounds GEP construction beginning with the
`IRBuilder2::CreateGEP` overloads declared at `CodeGen/IRBuilder.h:106-107`.
This residual cluster also contains same-opcode type/operand changes not covered
by the more specific roots above.

### `CG-INSTRUCTION-SELECTION` — 48, functional

Representatives:

1. `option::_CN11cjcj:option13GlobalOptions34SelectedCHIROptsToSerializedStringHv`
2. `incremental_compilation::_CN28cjcj:incremental_compilation11CombineHashHmm`
3. `incremental_compilation::_CN28cjcj:incremental_compilation14CombineHashI64Hll`

```diff
- br label %v62
+ %v62 = call i8 addrspace(1)* @"_CN10cjcj:utils5Out646appendHm"(...)
```

Root hypothesis: the named dispatch from CHIR expression major kind to
terminator/unary/binary/memory/other emitters is
`CodeGen/EmitExpressionIR.cpp:68-97`.

### `CG-EXTRA-CALL` — 16, functional

Representatives:

1. `option::_CN11cjcj:option13GlobalOptions17HandleBCExtensionHRNat6StringE`
2. `option::_CN11cjcj:option13GlobalOptions17HandleCJExtensionHRNat6StringE`
3. `option::_CN11cjcj:option13GlobalOptions18HandleCJDExtensionHRNat6StringE`

```diff
- %v13 = bitcast i8 addrspace(1)* %v1 to %v4* addrspace(1)*
+ %v13 = call i8* @llvm.cj.get.vtable.func(...)
```

Root hypothesis: direct versus virtual dispatch is decided by
`GenerateFuncPtrForNonAutoEnv`, including `GetVirtualMethodOffset` and
`CallIntrinsicGetVTableFunc`, at `CodeGen/Base/InvokeImpl.cpp:49-90`.

### `CG-CALL-TARGET` — 12, functional

Representatives:

1. `modules::_CN12cjcj:modules13ImportManager17CheckRedefinitionHCNY_7PackageE`
2. `driver::_CN11cjcj:driver14GCCPathScanner15StrToGCCVersionHRNat6StringE`
3. `ast::_CN8cjcj:astUNode$23FindPositionByUInt64KeyHCNac9ArrayListIT1_mRN10cjcj:basic8PositionEEEm`

First semantic edit for the representative precedes the later target-set split:

```diff
- %v22 = bitcast %v17* %v21 to i8*
+ %v22 = alloca %v19, align 8
```

Root hypothesis: trace callee selection into the two
`IRBuilder2::CreateCallOrInvoke` overloads at `CodeGen/IRBuilder.cpp:36-74`.
The TSV retains the true first edit; cluster membership additionally requires a
different call-target multiset.

### `CG-MISSING-INSTRUCTION` — 10, functional

Representatives:

1. `option::0_for_keeping_some_types`
2. `conditional_compilation::0_for_keeping_some_types`
3. `frontend_tool::0_for_keeping_some_types`

```diff
- %v63 = alloca %v64, align 8
+ <missing>
```

Root hypothesis: most members are the synthetic keep-types function generated
by `KeepSomeTypesManually` (`CodeGen/EmitPackageIR.cpp:175-198`, called at line
387).  Incremental merging also has a named owner,
`IncrementalGen::UpdateBodyOfKeepTypesFunction`
(`CodeGen/IncrementalGen/IncrementalGen.cpp:360-365`).

### `CG-EXTRA-INSTRUCTION` — 8, functional

Representatives:

1. `mangle::0_for_keeping_some_types`
2. `incremental_compilation::0_for_keeping_some_types`
3. `driver::0_for_keeping_some_types`

```diff
- <missing>
+ %v137 = alloca %v138, align 8
```

Root hypothesis: the same `KeepSomeTypesManually` and incremental merge
facilities as the missing-instruction cluster.  The direction is split because
the attack differs: selfhost either omitted or over-retained a type allocation.

### `CG-CALL-ORDER` — 1, functional

Representative (the cluster contains only one function):

1. `lex::_CN8cjcj:lex9LexerImpl12ReserveTokenHlbb`

```diff
- %v52 = bitcast %v14* %v19 to i8*
+ br i1 %v51, label %v52, label %v53
```

The call-target multiset is equal but its order differs.  Root hypothesis:
`EmitExpressionIR` emits the incoming CHIR expression vector in order at
`CodeGen/EmitExpressionIR.cpp:57-98`; determine whether the ordering split is
already present in CHIR before changing codegen.

### `CG-METADATA-NUMBERING` — 1,697, cosmetic

Representatives:

1. `option::_CN11cjcj:option10GetAbsPathHRNat6StringE`
2. `option::_CN11cjcj:option10GetDirPathHRNat6StringE`
3. `option::_CN11cjcj:option10GroupIndexHNNY_5GroupE`

```diff
- define ... !ReflectionFunc !48 {
+ define ... !ReflectionFunc !67 {
```

After replacing only named-metadata numeric IDs, every line in each of these
1,697 functions is identical.  The insertion owner is
`GenerateFunctionsMetadata`, which appends the function metadata operand and
attaches `ReflectionFunc` at
`CodeGen/CJNative/CJNativeGenMetadata.cpp:690-702`.  This is the largest raw
cluster but has functional-first score zero; fixing it first would not improve
runtime faithfulness.

## Next-stage attack list

1. Minimize one `CG-METADATA-ATTACHMENT` representative and compare the original
   CHIR type feeding `IRBuilder2::CreateLoad`; this is the largest functional
   root by a wide margin.
2. Audit typed `sret` propagation through `CreateCallOrInvoke`; 281 functions
   have a directly checkable callsite ABI mismatch.
3. Split `CG-MISSING-CALL` by missing target after minimization (overflow,
   virtual dispatch, runtime intrinsic, and ordinary calls) before editing.
4. Attack mangled typeinfo/global references through `BaseMangler`, keeping the
   shared function-name set separate from referenced-global spelling.
5. Only after the functional roots shrink, make metadata emission order stable
   if byte-identical percentage itself remains a desired metric.

## Scope and fidelity declarations

- No compiler package or runtime source was modified; the committed executable
  change is analysis-only under `scripts/`.
- No business source was changed to dodge a compiler defect, and no band-aid
  was added to swallow a failure.
- No missing C++ system-root facility was implemented or approximated in this
  chore; no system-root blocker was encountered.
- No new compiler symbol exists without a C++ source counterpart because this
  task adds no compiler symbols.
- Platform-branch completeness is not applicable: no C++ or compiler source was
  changed.  The analysis covers every observed differing shared function, with
  exactly one TSV row and one cluster assignment per function.
