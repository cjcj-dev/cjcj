# Sema Generics Deepening Status

Scope: `packages/sema/src` generics files covering generic instantiation, multi-type substitution, local type argument synthesis, promotion, generic checks, and recursive value-type elimination.

## Completed in this pass

- 2026-06-17: Deepened partial instantiation to use the real option state, C++-style `RequireInstantiation`
  decisions for CHIR/common-specific/nominal/virtual/const/frozen cases, and manager-side option wiring.
- 2026-06-17: Changed clone-based partial instantiation so the supplied visitor runs across every cloned
  source/target node pair through the real AST cloner, not just the root node.
- 2026-06-17: Added post-clone instantiated-member filtering for class, struct, and interface bodies, plus
  reachable-only generic-to-instantiated registration to avoid retaining pruned member declarations.
- 2026-06-17: Aligned generic constraint checking for the `CType` self-bound case and made
  `GetDeclTypeParams` prefer an extend declaration's canonical type args before falling back to the extended type.
- 2026-06-17: Continued generic-instantiation manager fidelity: instantiated clones now receive package
  ownership attributes, `GENERIC_INSTANTIATED`/`NO_REFLECT_INFO` markings, instantiated function linkage updates,
  package `genericInstantiatedDecls` insertion, and cache records reconstructed from generic-to-instantiated type
  mappings instead of identity-only records.
- 2026-06-17: Deepened instantiated-extend recording so extension member accesses are promoted against the base
  type where possible and written through the real `TypeManager.RecordUsedGenericExtend` path, while preserving
  the existing local used-extend query surface.
- 2026-06-17: Added a conservative package-file instantiation walker to the generic-instantiation manager. It now
  skips generic declarations like the C++ walker, follows desugared expressions, instantiates concrete generic
  targets from `RefExpr`, `MemberAccess`, type nodes, array expressions/literals, memory-layout type traversal,
  and type-manager recorded generic extends, and recursively walks newly generated instantiated declarations.
- 2026-06-17: Tightened manager cache lookup for package-owned instantiations so `GetInstantiatedDeclWithGenericInfo`
  prefers an instantiated declaration from the current package instead of any matching record.
- 2026-06-17: Added a conservative reference-pointer rearrangement pass for package files, generated instantiated
  declarations, and source-imported non-generic declarations. It rewrites cached instantiated targets in `RefExpr`,
  `MemberAccess`, `RefType`/`QualifiedType`, call `resolvedFunction`, array initializer functions, and `FuncBody`
  parent declarations, and clears type arguments once a target is no longer generic.
- 2026-06-17: Aligned the generic-instantiation and reference-rearrangement walkers with the C++ owner-context
  flow. The manager now keeps a nominal/generic-member context stack via the real `NeedSwitchContext` helper,
  explicitly walks reference type arguments and member bases before skipping reference/type children, uses the
  context base type for unqualified member references inside instantiated owners, and applies that context when
  rearranging `FuncBody` parent owner pointers.
- 2026-06-17: Ported the C++ rearrange-time type-pattern runtime-match refresh. The manager now updates nested
  `TypePattern.matchBeforeRuntime` and `needRuntimeTypeCheck` for tuple patterns, enum-constructor patterns, and
  patterns with context expressions after generic substitution, reusing the real after-type-check
  `IsNeedRuntimeCheck` helper instead of a local compatibility rule.
- 2026-06-17: Tightened local type argument synthesis against the C++ solver rules by copying instantiated
  generic upper bounds from `TypeManager` before solving, treating substitutions that still contain their own
  type variable as unsolved, and updating ideal-int/ideal-float bounds to the concrete primitive type seen during
  primitive unification.
- 2026-06-17: Aligned two generic-instantiation rearrangement edges with C++ behavior: `ArrayExpr` initializer
  instantiation now ignores non-`TYPE_ARRAY` array expressions, and rearranged dynamic `This`-typed member calls
  keep the receiver type as the call result.
- 2026-06-17: Continued C++ parity on bounded generics edges: `RequireInstantiation` now restricts the frozen
  CPointer extension-member exception to `std.core`, generic instantiation validation now rejects empty or
  mismatched type-argument lists before delegating to `TypeManager`, local type argument synthesis preserves
  C++'s explicit `Nothing`/`Any` solution allowance only when those bounds are observed, and reference
  rearrangement no longer overwrites expression types from Java-attributed targets.
- 2026-06-17: Aligned instantiated-extend recorder traversal with the C++ package/desugar behavior. Recording a
  package now visits source files and source-imported non-generic declarations, and desugared expressions are
  recorded through their lowered expression tree while skipping the original children.
- 2026-06-17: Matched the C++ rearranger's desugared-call cleanup edge: after rearranging a concrete desugared
  call expression, the original base name reference now drops stale instantiated type arguments.
- 2026-06-17: Ported the C++ clone-time default-parameter generic remap. Instantiating a generic function now
  maps generic type variables from cloned default-argument desugar declarations back through the owning function's
  generic parameters before applying the concrete substitution, and clears stale `GENERIC` on those helper decls.
- 2026-06-17: Aligned source-imported generic-use traversal with the C++ demand-walk path. Package instantiation
  no longer walks every source-imported non-generic decl up front; imported default-parameter helpers and
  source-imported targets are tracked and walked when referenced, and rearrangement is limited to used or const
  source-imported decls.
- 2026-06-18: Added scoped `TypeCheckerImpl` generic helpers in `TypeCheckGeneric.cj` using the real `basic`
  diagnostic engine and existing type-legality/type-alias utilities. The port now exposes C++-style generic
  constraint checking, call arity validation, generic-expression type refresh, and diagnostic upper-bound
  instantiation checks without local diagnostic compatibility copies.
- 2026-06-18: Deepened local type argument synthesis by propagating newly added placeholder lower/upper bounds
  through existing opposite bounds, guarded against recursive bound re-entry, and matched the C++ built-in
  extension path by using promotion when a built-in argument is checked against a generic interface parameter.
- 2026-06-18: Wired local type argument solving through the existing `TyVarConstraintGraph`, so dependent
  placeholder constraints are solved in topological batches and each solved substitution is applied to later
  constraint batches before choosing their solutions, matching the C++ solver's dependency-order flow more
  closely while keeping the current single-candidate constraint representation.
- 2026-06-18: Ported the C++ generic instantiation completeness check for static requirements in upper bounds.
  `TypeCheckerImpl` now collects static function/property requirements from upper-bound interfaces/classes,
  checks interface/abstract-class arguments through real `FieldLookup` and `TypeManager.PairIsOverrideOrImpl`,
  rejects `Nothing` for static-member constraints, and reports `sema_cannot_instantiated_by_incomplete_type`
  through the real `basic` diagnostic engine.
- Replaced status-only placeholders in the scoped generics files with compiling Cangjie implementations.
- Ported the `MultiTypeSubstUtils` utility surface against the real `ast.Ty`, `GenericsTy`, `TypeSubst`, `MultiTypeSubst`, `SubstPack`, and `TypeManager` types.
- Added the `Promotion` class with C++-matching promote/downgrade mapping operations and kept the previous top-level `Promote` helper.
- Implemented recursive struct/enum value-type graph construction, Tarjan SCC discovery, enum-to-ref-enum field rewriting, and package-level elimination entry points.
- Added a real local type argument synthesis path that collects bounds for placeholder `GenericsTy`, recursively unifies function/tuple/builtin/nominal type shapes, and solves through `TypeManager`.
- Deepened local type argument synthesis with C++-style argument ordering, union/intersection unification, invariant nominal and builtin type-argument checks, joined lower bounds, met upper bounds, recursive upper-bound substitution, and ideal-type normalization in inferred substitutions.
- Added generic constraint and instantiation helper functions that use the real AST generic nodes and `TypeManager`.
- Added generic-instantiation support components for context frames, clone-based partial instantiation, instantiated-decl caching, and extend-use recording.

## Fidelity Notes

This is a substantial deepening over the previous compatibility/status layer, but it is not a complete C++-behavior port of Sema generics. The most faithful areas in this pass are multi-type substitution, promotion shape, recursive type elimination, generic constraint utility checks, post-sema generic instantiation completeness checks, and the core local type-argument synthesis shape. Partial instantiation now uses real compiler options, whole-tree clone visiting, C++-style member filtering, reachable declaration registration, and the default-parameter desugar generic-to-generic remap needed before concrete substitution, but it still relies on the generic AST cloner instead of the C++ file's hand-written node constructors and full target-address rearrangement tables. The manager now creates package-owned instantiated declarations, walks package bodies and demand-walked source-imported non-generic declarations for concrete generic uses, keeps the C++-style generic-owner context needed by member instantiation/rearrangement, rewrites the common cached reference targets after instantiation, refreshes type-pattern runtime-match decisions after substitution, records desugared expression extend uses, clears stale source call type arguments after concrete desugar rearrangement, and participates in type-manager extend-use state, but it still lacks the C++ package import-manager rebuild path, backend-conditioned cleanup, full abstract function implementation maps, full desugar recovery for built-in operator calls, and actual source-imported inline-function pruning/removal. Local type argument synthesis now mirrors more of the C++ lattice behavior, including opposite-bound propagation, built-in extension promotion, and dependency-ordered solving through the real ty-var constraint graph, but still lacks the C++ multi-candidate constraint set, full deterministic/diagnostic branch retention, complete blame tracking, import-manager/backend interactions, complete abstract member maps, and full AST pointer-rewrite semantics.

Build verification: `cjpm build` passes for the workspace after the 2026-06-18 pass.
