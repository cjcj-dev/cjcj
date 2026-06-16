# Sema Generics Deepening Status

Scope: `packages/sema/src` generics files covering generic instantiation, multi-type substitution, local type argument synthesis, promotion, generic checks, and recursive value-type elimination.

## Completed in this pass

- Replaced status-only placeholders in the scoped generics files with compiling Cangjie implementations.
- Ported the `MultiTypeSubstUtils` utility surface against the real `ast.Ty`, `GenericsTy`, `TypeSubst`, `MultiTypeSubst`, `SubstPack`, and `TypeManager` types.
- Added the `Promotion` class with C++-matching promote/downgrade mapping operations and kept the previous top-level `Promote` helper.
- Implemented recursive struct/enum value-type graph construction, Tarjan SCC discovery, enum-to-ref-enum field rewriting, and package-level elimination entry points.
- Added a real local type argument synthesis path that collects bounds for placeholder `GenericsTy`, recursively unifies function/tuple/builtin/nominal type shapes, and solves through `TypeManager`.
- Added generic constraint and instantiation helper functions that use the real AST generic nodes and `TypeManager`.
- Added generic-instantiation support components for context frames, clone-based partial instantiation, instantiated-decl caching, and extend-use recording.

## Fidelity Notes

This is a substantial deepening over the previous compatibility/status layer, but it is not a complete C++-behavior port of Sema generics. The most faithful areas in this pass are multi-type substitution, promotion shape, and recursive type elimination. Local type argument synthesis and generic instantiation now perform real work, but still omit many C++ diagnostic refinements, import-manager/backend interactions, rearrangement passes, abstract member maps, deterministic diagnostic ordering, and full AST pointer-rewrite semantics.

Build verification: `cjpm build` passes for the workspace after this pass.
