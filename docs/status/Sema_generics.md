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
- Replaced status-only placeholders in the scoped generics files with compiling Cangjie implementations.
- Ported the `MultiTypeSubstUtils` utility surface against the real `ast.Ty`, `GenericsTy`, `TypeSubst`, `MultiTypeSubst`, `SubstPack`, and `TypeManager` types.
- Added the `Promotion` class with C++-matching promote/downgrade mapping operations and kept the previous top-level `Promote` helper.
- Implemented recursive struct/enum value-type graph construction, Tarjan SCC discovery, enum-to-ref-enum field rewriting, and package-level elimination entry points.
- Added a real local type argument synthesis path that collects bounds for placeholder `GenericsTy`, recursively unifies function/tuple/builtin/nominal type shapes, and solves through `TypeManager`.
- Deepened local type argument synthesis with C++-style argument ordering, union/intersection unification, invariant nominal and builtin type-argument checks, joined lower bounds, met upper bounds, recursive upper-bound substitution, and ideal-type normalization in inferred substitutions.
- Added generic constraint and instantiation helper functions that use the real AST generic nodes and `TypeManager`.
- Added generic-instantiation support components for context frames, clone-based partial instantiation, instantiated-decl caching, and extend-use recording.

## Fidelity Notes

This is a substantial deepening over the previous compatibility/status layer, but it is not a complete C++-behavior port of Sema generics. The most faithful areas in this pass are multi-type substitution, promotion shape, recursive type elimination, and the core local type-argument synthesis shape. Partial instantiation now uses real compiler options, whole-tree clone visiting, C++-style member filtering, and reachable declaration registration, but it still relies on the generic AST cloner instead of the C++ file's hand-written node constructors and full target-address rearrangement tables. The manager now creates package-owned instantiated declarations and participates in type-manager extend-use state, but it still lacks the C++ package import-manager rebuild path, backend-conditioned cleanup, full instantiation/rearrangement walkers, abstract function implementation maps, and source-imported inline-function pruning. Local type argument synthesis now mirrors more of the C++ lattice behavior, but still lacks the C++ multi-candidate constraint set, full deterministic/diagnostic branch retention, complete blame tracking, import-manager/backend interactions, rearrangement passes, abstract member maps, and full AST pointer-rewrite semantics.

Build verification: `cjpm build` passes for the workspace after the 2026-06-17 pass.
