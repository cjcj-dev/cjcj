# IncrementalCompilation Port Status

Date: 2026-06-18

Build: `cjpm build` passes.

Reference inspected:

- Public headers under `/root/cj_build/cangjie_compiler/include/cangjie/IncrementalCompilation`.
- Source/internal files under `/root/cj_build/cangjie_compiler/src/IncrementalCompilation`.
- Components covered: `ASTCacheCalculator`, `ASTDiff`, `CompilationCache`, `CachedMangleMap`,
  `IncrementalCompilationLogger`, `IncrementalScopeAnalysis`, cache/dependency serialization,
  `PollutionAnalyzer`, `PollutionMapGen`, and `Utils`.

Implemented:

- Replaced the single scaffold with C++-named multi-file Cangjie components under
  `packages/incremental_compilation/src`.
- Added the compilation-cache data model: raw mangle maps, AST/member/top-level caches, semantic usage
  graphs, type relations, CHIR optimization effect maps, file-order maps, cached mangle maps, and
  incremental result records.
- Added a package-local `IncrDecl`/`IncrPackage` adapter model so this package builds without manifest
  changes while retaining the C++ cache fields needed by the incremental algorithms.
- Ported AST cache calculation over the adapter model, including direct-extend coalescing, member cache
  recursion, global/static-var order ids, source-file order maps, duplicate mangle detection, virtual/member
  layout hashes, and source/body/signature hash separation.
- Ported AST diffing for current and imported caches: additions, deletions, type aliases, common decl changes,
  type/member changes, member add/delete/change sets, and order-change detection against cached file maps.
- Added pollution graph generation from semantic usages, source-imported dependency data, type relations,
  builtin relations, CHIR optimization effects, direct/API/body usages, qualified/unqualified/package-qualified
  usages, and boxed-type usages.
- Ported a working pollution analyzer for added/deleted/changed type and non-type declarations, signature/body/
  source-use changes, layout and vtable changes, constructor propagation, extend propagation, downstream type
  propagation, box-use propagation, generic-instantiation propagation, CHIR optimization effects, and rollback
  triggers for unsupported type-alias/removal cases.
- Added incremental scope analysis orchestration: cache load, argument/spec checks, imported package cache walk,
  AST diff, pollution analysis, closure-conversion rollback check, deleted CodeGen mangle lookup, cache update,
  CHIR optimization effect-map merge/delete helpers, and debug logging.
- Added deterministic text serialization/deserialization for the implemented cache schema, including AST cache
  entries, members, semantic usage/name-usage/relation data, dependency data, CHIR effects, virtual/var-init deps,
  closure-converted functions, counters, args, specs, and bitcode file names.
- Added a logger matching the C++ singleton behavior for debug printing, buffered output, and `.log` file output.
- Added C++-shaped utility helpers for virtual/typed/imported/enum-constructor/member/order-affected decl checks,
  sorting, trimmed paths, stable hashes, and fallback mangle generation.
- Extended the adapter declaration model with precomputed hash/body-hash inputs, resolved type/return type names,
  and imported-body target dependency records so callers can feed the exact ASTHasher/ASTMangler/Walker outputs
  produced by real front-end modules without changing this package manifest.
- Reworked imported package walking into mangle normalization, recursive imported-decl registration, source-imported
  dependency collection, and cache materialization passes. This mirrors the C++ `ImportPackageWalker` map shape:
  `used decl -> imported decls whose function bodies or variable initializers target it`.
- Added adapter fields and logic for getter/setter typedness, default-argument desugar functions, inherited type
  relations, and direct-vs-interface extend classification. These close C++ parity gaps in `IsTyped`,
  `IsOOEAffectedDecl`, imported body-hash skipping, imported inheritance relation collection, direct-extend cache
  coalescing, and box/extend pollution.
- Ported the C++ fallback for deleted imported extend decls: when the cached extend-to-type relation is missing,
  the analyzer truncates the extend mangle, recovers the candidate type identifier, pollutes matching nominal decls,
  and falls back to builtin box pollution when no decl exists.
- Added adapter support for main/macro desugared declarations. Cache writing now uses the desugared raw mangle for
  `main`, semantic-usage serialization can use main/macro desugared raw mangles, and CHIR optimization effect-map
  cleanup removes the desugared main entry when a main declaration is recompiled.
- Tightened cache serialization parity by writing static/global-variable members before other members and by keeping
  imported member cache entries out of the reconstructed source `CachedFileMap`, matching the C++ loader's `srcPkg`
  split.
- Matched the C++ incremental-analysis entry guard that rolls back when the serialized `.cjo` sidecar is absent,
  even if cached AST data is otherwise available.
- Added adapter-backed source import records and wired `PollutionMapGen::CollectAlias` parity: package aliases and
  single/aliased declaration imports now populate the same alias maps used by unqualified and package-qualified
  pollution propagation.
- Matched more of the C++ cache writer/loader ordering behavior: CHIR var/function dependencies, semantic usages,
  name usages, relations, and compiler-added usages are serialized by raw mangle/name order, and cached file-map
  reconstruction now applies the C++ top-level/member affected-declaration filters separately.
- Tightened order-change parity further by reconstructing cached file maps after top-level cache entries are fully
  loaded, preserving the C++ static-member/property-accessor collection order, and by treating
  `VAR_WITH_PATTERN_DECL` as global-like for file-move invalidation.
- Added explicit adapter support for var-with-pattern bound variables and routed cache calculation, member traversal,
  signature pollution, and CHIR optimization pollution through the same flattened pattern-variable view used by the
  C++ `FlattenVarWithPatternDecl` paths.
- Added the first real sibling-package dependency for this module: `cangjie_compiler::ast` is now imported by the
  incremental package so cache declaration-kind tags use real `ASTKindIndex` values and adapter attributes that
  correspond to AST attributes use real `AttributeIndex` values.
- Removed the adapter-only `IncrAttribute.CONST` pseudo-attribute. Constness now flows through
  `IncrDecl.isConstValue`/`IncrDecl.IsConst()`, and fallback source-use hashing reads that path, matching the C++
  `Decl::IsConst()` model and the self-host AST `isConst` fields instead of inventing an AST attribute.
- Bumped the deterministic cache wire version to `CJ-INCR-CACHE-3` so caches containing the previous fallback
  const-attribute hash semantics are rejected rather than mixed with the real constness path.
- Bumped the deterministic cache wire version to `CJ-INCR-CACHE-2` so caches written with the previous package-local
  kind/attribute ordinals are rejected instead of being decoded with the real AST ordinal layout.
- Removed the local `IncrGlobalOptions` compatibility class and changed `ASTDiffArgs`/`IncrementalScopeAnalysisArgs`
  to carry the real `cangjie_compiler::option.GlobalOptions`. Incremental analysis now uses the same cache path
  generation and full compile-option serialization as the C++ entry point, with an `Array<String>`/`ArrayList<String>`
  comparison helper only at the cache boundary.
- Removed the local stripped-down incremental position class. Adapter declarations now store
  `cangjie_compiler::basic.Position` through an `IncrPosition` alias, so file/line/column state and zero-position
  checks use the same Basic source-position type as the real AST nodes.
- Removed two remaining silent fallback paths from incremental scope analysis. Missing source package declarations
  and missing cached CodeGen mangles for deleted declarations now fail the same invariant class as the C++
  `CJC_NULLPTR_CHECK`/`CJC_ABORT` sites instead of synthesizing package declarations or reusing raw mangles.
- Added explicit bridge helpers between the package-local hashable adapter enums and the real
  `cangjie_compiler::ast.ASTKind`/`Attribute` enums. A direct alias was tested but Cangjie currently rejects
  adding `Hashable` to imported enum types, so the local wrappers remain only where this package needs hashed
  sets/maps while adapter callers can convert to and from real AST enum values.
- Tightened cache hash determinism by sorting adapter attributes by real `AttributeIndex` before combining them
  into signature hashes. This removes nondeterminism from `HashSet` iteration while keeping the same real AST
  ordinal semantics used by the C++ `ASTHasher`.
- Matched C++ enum-constructor handling more closely: enum declarations now have a separate adapter
  `enumConstructors` list and `GetMembers(EnumDecl)` excludes enum constructors, like C++ `GetMembers`. Enum
  layout hashing and layout-change pollution use the constructor list, with the old raw-mangle list retained only
  as a fallback for adapter inputs that cannot yet supply constructor decl nodes.
- Fixed fallback member mangling order so a member's raw mangle is established before recursively visiting nested
  members. This gives nested/accessor fallback mangles a stable parent prefix instead of depending on a parent
  raw mangle that may still be empty.
- Refined cached file-map reconstruction for loaded member children so child entries pass through the same
  OOEAffected/static-member filters as C++ loader member entries instead of unconditionally participating in
  order-change invalidation.

Known gaps:

- The package now depends on real `ast` for cache tag ordinals, real `basic.Position` for source locations, and real
  `option.GlobalOptions` for entry options, but most declaration/package/import entry points still use
  `IncrDecl`/`IncrPackage`/`IncrImportManager` adapters instead of the real AST/Sema/Modules/Mangle/Parse public
  types.
- The cache wire format is a deterministic self-host text format, not the C++ FlatBuffers `CachedASTFormat`.
- Hashing and fallback mangling are behavior-shaped but not byte-identical to C++ `ASTHasher`/`ASTMangler` until
  those packages can be wired directly.

Self-host TODOs remaining in package: 0.
