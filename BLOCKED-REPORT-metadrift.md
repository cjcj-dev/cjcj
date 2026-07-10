# BLOCKED-REPORT: sc_bcgate named-metadata numbering drift

## Outcome

`GenerateAllFunctionsMetadata` is not the source of the observed 1,697-function
cluster.  The cluster is downstream of different `SubCHIRPackage` membership.
Changing metadata numbering, traversal, or attachment timing would therefore be
a post-processing compensation rather than a faithful C++ port.

No compiler source was changed.

## Direct IR evidence

For the inventory representative
`_CN11cjcj:option10GetAbsPathHRNat6StringE`, the archived 32-way sc_bcgate
artifacts place the definition in different modules:

```text
ref  /tmp/sc_bcgate_hler08k_/ref_option/28c688c7/24-option@cjcj.bc
define ... !dbg !61 !ReflectionFunc !48 {
self /tmp/sc_bcgate_hler08k_/self_option/2e9ef0a1/17-option@cjcj.bc
define ... !dbg !80 !ReflectionFunc !67 {
```

The reflection and debug slots both move by 19.  This is module-local metadata
slot allocation after the function moved from split 24 to split 17, not a
different append position inside one equal module.

A mechanical scan of `SC_DIFF_FUNCTIONS.tsv` against those same non-optimized
bitcode artifacts produced:

```text
STATS {'different_split': 1570, 'same_split': 125, 'missing': 2}
```

The 125 same-numbered splits do not imply equal module membership: other
functions have moved into and out of those modules, changing their local slot
tables.

## Minimal reproduction

The `option` package was compiled by the reference compiler and the archived
selfhost compiler with `--apc=1`, keeping all package functions in the same
module.  The exact comparison output was:

```text
APC1 option: shared=779 byte-identical=756 differing=23 metadata-number-only=0
REF define ... !ReflectionFunc !1363 {
SELF define ... !ReflectionFunc !1363 {
```

Thus the named-metadata-only cluster disappears without any change to
`GenerateAllFunctionsMetadata` when module membership is held equal.  The 23
remaining differences are functional and are not renumbering noise.

## C++ correspondence

The relevant C++ implementation is
`CodeGen/CJNative/CJNativeGenMetadata.cpp:669-705`:

```cpp
void GFMetadataInfo::GenerateAllFunctionsMetadata()
{
    if (reflectionMode != GenReflectMode::FULL_REFLECT) {
        return;
    }
    llvm::NamedMDNode* functionsMdNode =
        llvmMod->getOrInsertNamedMetadata(METADATA_FUNCTIONS);
    for (auto gf : subCHIRPkg.chirFuncs) {
        // two filtering early-continue branches
        ...
        if (auto func = llvmMod->getFunction(gf->GetIdentifierWithoutPrefix()); func) {
            auto funcMD = MetadataVector(llvmCtx)...CreateMDTuple();
            functionsMdNode->addOperand(funcMD);
            func->addMetadata("ReflectionFunc", *funcMD);
        }
    }
}
```

The selfhost implementation at
`packages/codegen/src/CJNativeGenMetadata.cj:778-814` has the same early return,
the same sorted `subCHIRPkg.chirFuncs` traversal, both filtering continues, the
same tuple construction order, then `LLVMAddNamedMetadataOperand` immediately
followed by `LLVMSetGlobalMetadata`.

The ordering container is also already mirrored:

- C++ `CHIRSplitter.h:45` uses
  `std::set<CHIR::Function*, ChirValueCmp>`.
- C++ `CHIRSplitter.cpp:48-51` orders it by
  `GetIdentifierWithoutPrefix()`.
- Selfhost `CHIRSplitter.cj:68,152-172` stores functions in an `ArrayList` but
  inserts them in that same identifier order.

The module assignment is owned earlier by C++
`SplitNormalFunc` (`CHIRSplitter.cpp:155-168`), which sorts by
`Function::GetExpressionsNum()` and repeatedly selects the lightest package.
Selfhost mirrors that algorithm at `CHIRSplitter.cj:393-420`.  Consequently,
functional CHIR differences that change expression counts or equal-weight input
order cascade into different split membership.  The named-metadata numbers
cannot converge before those upstream functional differences and construction
order differences converge.

## Exact blocker and resume API

Blocked while auditing C++
`GFMetadataInfo::GenerateAllFunctionsMetadata`
(`CJNativeGenMetadata.cpp:669-705`) on its already-present dependency
`SubCHIRPackage::chirFuncs`: the inputs supplied by
`CHIRSplitter::SplitCHIRFuncs` (`CHIRSplitter.cpp:191-220`) are observably
different because the selfhost CHIR/function construction is not yet at
functional parity.

Resume after the upstream functional sc_bcgate clusters that alter CHIR shape
and package function construction order have been fixed.  The required input
contract is unchanged: `SubCHIRPackage.chirFuncs` must contain the same function
identifiers in each `subCHIRPackageIdx` as C++ before calling
`GenerateReflectionMetadata`.  No new metadata API is required.

## Branch and platform audit

Platform scan command and raw output:

```text
$ rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" /root/cj_build/cangjie_compiler/src/CodeGen/CJNative/CJNativeGenMetadata.cpp
<no matches>
```

`GenerateAllFunctionsMetadata` has all 4 decision sites represented in
selfhost: one reflection-mode early return, two filtering `if`/`continue`
sites, and one function-exists `if`.  Source count:

```text
669:void GFMetadataInfo::GenerateAllFunctionsMetadata()
671:    if (reflectionMode != GenReflectMode::FULL_REFLECT) {
680:        if (gf->GetParentCustomTypeDef()) {
683:        if (gf->TestAttr(...)) {
689:        if (auto func = llvmMod->getFunction(...); func) {
```

No branch was added, removed, or changed.

## Gates

The archived required sc_bcgate baseline remains:

```text
TOTAL: shared=14516 byte-identical=10953 (75.5%) differing=3563
```

There is no “after” gate number: no faithful compiler diff exists to test.
`verify.sh`, O0 bcgate, and a rebuilt full sc_bcgate were intentionally not run;
running them on an unchanged compiler would not validate a fix.  The focused
single-split reproduction above is the mechanical test that disproves the
assigned root.

## Required declarations

1. 无任何 grep 不到 C++ 出处的新代码符号；本提交不新增代码符号。
2. 未改业务源码绕过、未加 band-aid 吞 bug。
3. 已将输入模块成员不一致这一上游 blocker 精确上报，未自行做 metadata
   编号重映射、重排或其他 downstream 替代。
