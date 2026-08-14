# CJO handwritten-reader true-denominator differential (2026-08-14)

## Verdict

**Read from the final kkk2 evidence:** `FORMAL_SUMMARY=SUMMARY N=383 A=0 B=0
C=0 D=383 UNKNOWN=0 FIELD_GROUPS=167 CHECKS=17876673`
(`test/cjoffi_probe/cjodiff3_evidence.txt:8`).

**Inferred from that read result:** no official/manual difference was observed in
the 167 reader-consumed field groups exercised by this corpus. This is not a
claim about the nine reader-consumed groups that the corpus did not instantiate.

The true static denominator is 176 fields, not 217. The final dynamic coverage
is `167/176 = 94.9%` (`test/cjoffi_probe/cjodiff3_evidence.txt:3,9`).

## How the denominator was obtained

**Read:** the repository defines the migration inventory as 524 source-level
calls after `CjoFlatBuffer`, excluding the primitive reader definitions and the
new probe (`docs/TODO-CJO-OFFICIAL-FFI.md:9-23`: “There are **524 handwritten
reader access sites** ...”; “it excludes the reader's own method definitions and
the new comparison/probe entry”).

**Read:** representative live reads show why source-field mapping, rather than
call-counting, is required:

- `FrontendModel.cj:3625-3628` reads four members of `Position`: “`U32At(posTable)`”,
  “`U32At(posTable + 4)`”, “`I32At(posTable + 8)`”, and “`I32At(posTable + 12)`”.
- `FrontendModel.cj:3745-3765` reads `Constraint.type`, `uppers`, and
  `isImplicitlyIntroduced`: “`U32Field(constraintTable, 8, 0u32)`”,
  “`VectorField(constraintTable, 10)`”, and “`U8Field(constraintTable, 12, 0u8)`”.
- `FrontendModel.cj:4065-4069` reads `VarInfo.isVar`, `isConst`, `isMemberParam`,
  and `initializer`, ending at “`U32Field(infoTable, 10, 0u32)`”.
- `FrontendModel.cj:5340-5341` reads the two enum booleans: “`U8Field(infoTable,
  10, 0u8)`” and “`U8Field(infoTable, 12, 0u8)`”.

**Inferred:** exhaustively mapping those 524 calls to the authoritative schema
produces 176 unique read fields and 41 fields with no consumer. The reproducible
inventory records one row for each of the 217 schema fields
(`test/cjoffi_probe/schema_read_inventory.tsv:1-218`), and the generator asserts
both the `72/217` schema shape and the `41`-field exclusion audit
(`test/cjoffi_probe/generate_read_surface.py:117-118,377-381`).

## The 176 fields actually read

The following is the exact inferred read set; the row-level source-schema line
and status are retained in `schema_read_inventory.tsv`.

- `Position`: `file`, `pkgId`, `line`, `column`.
- `FullId`: `pkgId`, `decl`, `index`.
- `Constraint`: `type`, `uppers`, `isImplicitlyIntroduced`.
- `Generic`: `typeParameters`, `constraints`.
- `FuncParamList`: `params`, `desugars`.
- `FuncBody`: `paramLists`, `retType`, `body`, `always`, `captureKind`.
- `DeclHash`: `instVar`, `virt`, `sig`, `srcUse`, `bodyHash`.
- `ClassInfo`: `inheritedTypes`, `body`, `annoTargets`, `runtimeVisible`, `annoTargets2`.
- `InterfaceInfo`: `inheritedTypes`, `body`.
- `StructInfo`: `inheritedTypes`, `body`.
- `EnumInfo`: `inheritedTypes`, `body`, `hasArguments`, `nonExhaustive`.
- `ExtendInfo`: `inheritedTypes`, `body`.
- `VarInfo`: `isVar`, `isConst`, `isMemberParam`, `initializer`.
- `VarWithPatternInfo`: `isVar`, `isConst`, `irrefutablePattern`, `initializer`.
- `FuncInfo`: `funcBody`, `overflowPolicy`, `op`, `isConst`, `isInline`, `isFastNative`.
- `ParamInfo`: `isNamedParam`, `isMemberParam`, `defaultVal`.
- `PropInfo`: `isConst`, `isMutable`, `setters`, `getters`.
- `BuiltInInfo`: `builtInType`.
- `AliasInfo`: `aliasedTy`.
- `Decl`: `kind`, `isTopLevel`, `fullPkgName`, `genericDecl`, `generic`, `begin`, `end`, `identifier`, `identifierPos`, `attributes`, `annotations`, `type`, `mangledName`, `exportId`, `mangledBeforeSema`, `hash`, `info`, `dependencies`.
- `Anno`: `kind`, `identifier`, `args`, `target`.
- `AnnoArg`: `name`, `expr`.
- `CallInfo`: `hasSideEffect`, `callKind`.
- `UnaryInfo`: `op`.
- `BinaryInfo`: `op`.
- `IncOrDecInfo`: `op`.
- `LitConstInfo`: `strValue`, `constKind`, `strKind`.
- `ReferenceInfo`: `reference`, `target`, `instTys`, `matchedParentTy`.
- `LambdaInfo`: `funcBody`, `supportMock`.
- `AssignInfo`: `isCompound`, `op`.
- `ArrayInfo`: `initFunc`, `isValueArray`.
- `JumpInfo`: `isBreak`.
- `FuncArgInfo`: `withInout`, `isDefaultVal`.
- `SubscriptInfo`: `isTupleAccess`.
- `MatchInfo`: `matchMode`.
- `BlockInfo`: `isExpr`.
- `TryInfo`: `resources`, `patterns`.
- `LetPatternDestructorInfo`: `patterns`.
- `ForInInfo`: `pattern`, `forInKind`.
- `MatchCaseInfo`: `patterns`.
- `SpawnInfo`: `future`.
- `Expr`: `kind`, `begin`, `end`, `mapExpr`, `operands`, `type`, `overflowPolicy`, `info`.
- `Pattern`: `kind`, `begin`, `end`, `patterns`, `types`, `exprs`, `matchBeforeRuntime`, `needRuntimeTypeCheck`.
- `FuncTyInfo`: `retType`, `isC`, `hasVariableLenArg`.
- `CompositeTyInfo`: `declPtr`, `isThisTy`.
- `GenericTyInfo`: `declPtr`, `upperBounds`.
- `ArrayTyInfo`: `dimsOrSize`.
- `SemaTy`: `kind`, `typeArgs`, `info`.
- `ImportSpec`: `begin`, `end`, `prefixPaths`, `identifier`, `asIdentifier`, `reExport`, `isDecl`, `hasDoubleColon`, `withImplicitExport`.
- `Imports`: `importSpecs`.
- `FeatureId`: `identifiers`.
- `FeaturesSet`: `features`.
- `FeaturesDirective`: `featuresSet`.
- `FileInfo`: `fileID`, `begin`, `end`, `feature`.
- `CompilationOptions`: `optimization_level`, `debug`.
- `Package`: `fullPkgName`, `pkgDepInfo`, `imports`, `allFiles`, `allFileImports`, `allTypes`, `allDecls`, `allExprs`, `kind`, `access`, `allFileInfo`, `allDependentStdPkgs`, `options`.

## The 41 fields not read, and why they are not compared

These are **inferred NOT_READ**, not passed fields. They have no mapped consumer
in the scoped 524-call inventory, so comparing them would enlarge the denominator
with behavior the product does not use.

- `Position`: `ignore`.
- `Constraint`: `begin`, `end`.
- `Int8Value`: `val`.
- `UInt8Value`: `val`.
- `Int16Value`: `val`.
- `UInt16Value`: `val`.
- `Int32Value`: `val`.
- `UInt32Value`: `val`.
- `Int64Value`: `val`.
- `UInt64Value`: `val`.
- `Float32Value`: `val`.
- `Float64Value`: `val`.
- `ArrayValue`: `val`.
- `CompositeValueIndex`: `idx`.
- `MemberValue`: `field`, `type`, `value`.
- `CompositeValue`: `type`, `fields`.
- `AutoDiffInfo`: `isDiff`, `isAdj`, `primal`, `excepts`, `includes`, `stage`.
- `ClassInfo`: `adInfo`, `isAnno`.
- `StructInfo`: `adInfo`.
- `EnumInfo`: `adInfo`, `ellipsisPos`.
- `VarInfo`: `value`.
- `FuncInfo`: `adInfo`.
- `Pattern`: `values`.
- `CjoVersion`: `major_num`, `minor_num`, `patch_num`.
- `Package`: `version`, `cjoVersion`, `allValues`, `moduleName`.

The constant-value subtree is unreachable because its three live-schema entry
fields (`VarInfo.value`, `Pattern.values`, `Package.allValues`) are not consumed.
The AutoDiff subtree is unreachable because all four `adInfo` links are not
consumed. `CjoVersion` is unreachable because `Package.cjoVersion` is not
consumed. These are graph consequences inferred from the exact NOT_READ rows
(`schema_read_inventory.tsv:6-11,29-55,63-84,166,190-215`).

## Dynamic coverage and unresolved fields

**Read:** the final run exercised 167 distinct groups and 17,876,673 owner-field
instances (`cjodiff3_evidence.txt:8`). **Inferred:** dynamic coverage is therefore
`167/176 = 94.9%`.

The nine read fields with zero dynamic instances are unresolved, not passed:

> `IncOrDecInfo.op`, `SpawnInfo.future`, `FeatureId.identifiers`,
> `FeaturesSet.features`, `FeaturesDirective.featuresSet`, `FileInfo.fileID`,
> `FileInfo.begin`, `FileInfo.end`, `FileInfo.feature`.

That exact list is the `UNHIT_READ_FIELDS` evidence
(`test/cjoffi_probe/cjodiff3_evidence.txt:10`).

## Controls and trust hardening

**Read positive control:** `RESULT D checks=78560 groups=113 ...parse@cjcj.cjo`
and `N=1 ... D=1` (`cjodiff3_evidence.txt:4-5`). Thus the new field walker and
both fingerprints are live before interpreting any zero difference count.

**Read negative control:** link-wrapping `CJOFPackageViewOpen` produced
`RESULT C checks=0 groups=0 ...parse@cjcj.cjo` and `C=1`
(`cjodiff3_evidence.txt:6-7`). Thus the four-way classifier can emit a non-D arm.

The official and manual arms maintain independent 64-bit FNV and mix
fingerprints per schema field (`runtime_shim/cjselfhost_llvmshim.cpp:141-174` and
`test/cjoffi_probe/surface_probe.cpp:225-253`). Input bytes are fingerprinted
before and after each comparison; any exact-zero or mutation emits the address
and monotonic timestamp (`surface_probe.cpp:492-532`). The final result was
`MEMORY_ALERTS=0 N=383` (`cjodiff3_evidence.txt:11`). No retry result was used.

During positive-control bring-up, an apparent `Decl.dependencies` B was rejected
as an apparatus defect: the official absent-vector encoding emitted presence=0
but omitted the zero length, while the manual arm emitted both. The generator now
emits both values (`generate_read_surface.py:228-230`). The positive control was
rerun only after that deterministic encoding defect was corrected.

## Recipe and provenance

**Read:** host/core/build are `kkk2`, `taskset -c 0-95`, and `make -j96`
(`cjodiff3_evidence.txt:1`). The authoritative run took `real 1.73`, `user 1.66`,
`sys 0.07`; concurrent build-process inventory was 0 before and 0 after
(`cjodiff3_evidence.txt:12-13`).

**Read:** corpus manifest SHA256 is
`16d102807cec2c58cea829b16c722ca38a19678bc561bd63ffe1c584666ebcb1`,
with `N=383` (`cjodiff3_evidence.txt:14`).

**Read artifacts:** shim
`aee2e647ba16e6b21b3679e38c0886371158eaf271cc09500dc23de8035106fc`,
positive probe
`7d48046e7197e335935057e6191974d2511c1b6b81c4298c202eb2c2abcb0dcc`,
negative probe
`08b3225836ca0b905b121dcd085808abc1e1c27a7e1c57a2856ff2b436530dc8`
(`cjodiff3_evidence.txt:15-17`).

**Read lineage:** cjcj base `064229205`, Cangjie compiler
`ec27dfa0f77b449042c47b4c21a670185664b449`, LLVM
`fc16fc667def36249f1f2f2018f8be752c739351`
(`cjodiff3_evidence.txt:18`). No SDK or nightly-toolchain file was modified.
