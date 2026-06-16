# Sema tc-decl Deepening Status

Date: 2026-06-17

## Scope

Declaration, type, reference, class-like, extend, and annotation checking under:

- `packages/sema/src/TypeCheckDecl.cj`
- `packages/sema/src/TypeCheckType.cj`
- `packages/sema/src/TypeCheckReference.cj`
- `packages/sema/src/TypeCheckClassLike.cj`
- `packages/sema/src/TypeCheckExtend.cj`
- `packages/sema/src/TypeCheckAnnotation.cj`

Reference sources inspected from `/root/cj_build/cangjie_compiler/src/Sema`:

- `TypeCheckDecl.cpp`
- `TypeCheckType.cpp`
- `TypeCheckReference.cpp`
- `TypeCheckClassLike.cpp`
- `TypeCheckExtend.cpp`
- `TypeCheckAnnotation.cpp`

## Implemented In This Pass

- Deepened declaration checking toward the C++ `TypeCheckDecl.cpp` behavior:
  operator overload validation now reports built-in operator overload attempts,
  index assignment operators now use the C++ refactored diagnostics for invalid
  named parameter, arity, and return type cases, enum function constructors
  synthesize compiler-added return types, and optional diagnostics cover invalid
  enum constructors, `@C` enum constructor payloads, and C vararg function values.
- Continued declaration parity in `TypeCheckDecl.cj`: type aliases now have a
  C++-style access-level check over referenced `RefType` nodes, unused generic
  parameter detection, and reference-type legality delegation; enum and struct
  inherited interface checks now reject non-interfaces, register `subDecls`, and
  reuse sealed-inheritance validation; `@C` structs now reject generics and
  implemented interfaces with the C++ diagnostics.
- Enum declaration support now includes the C++ mutable-property rejection for
  enum properties and enum constructor function synthesis now skips parameters
  without explicit type nodes, matching the C++ `SetEnumEleTyHandleFuncDecl`
  behavior.
- Deepened type checking toward `TypeCheckType.cpp`: reference and qualified
  types now run available generic instantiation checks after arity validation,
  `CFunc<...>` reference types validate their function parameter and return
  types, and C function type parameters now use the C++ legacy CFunc parameter
  diagnostics instead of the previous generic VArray diagnostic.
- Continued type-checking parity in `TypeCheckType.cj`: `RefType` and
  `QualifiedType` legality now runs the real sema access-control predicate and
  emits `sema_invalid_access_control` like the C++ path, invalidating illegal
  `RefType` targets; `RefType` also mirrors the C++ Java generic type-argument
  short-circuit before normal generic-instantiation checks.
- Deepened reference filtering toward `TypeCheckReference.cpp`: name references
  now filter macro-function targets, collapse shadowed all-function candidates,
  report ambiguous imported non-function sets, detect generic base type
  references without type arguments during member inference, and report
  recursive quest-return function references when no target type is available.
- Continued reference legality parity in `TypeCheckReference.cj`: reference and
  member-access helpers now emit access-control failures through the real
  `TypeCheckAccess` issue model, reject unsafe function references used as
  values, diagnose type declarations used as rvalues, check package-member
  visibility with the real module package-relation utility, reject abstract
  interface calls through type access, reject enum constructor type arguments on
  member access, and reject direct `super` access to abstract members.
- Deepened extend checking toward `TypeCheckExtend.cpp`: extend-map construction
  now checks duplicate direct interface implementations, duplicate inherited
  interface implementations, and non-extendable `std.core.Any`/`std.core.CType`
  interfaces, and immutable type extensions now reject assignment index
  operators as well as mutable properties.
- Deepened annotation checking toward `TypeCheckAnnotation.cpp` by preserving
  the C++ `NO_REFLECT_INFO` marker on custom annotation call expressions that
  are not compile-time visible.
- The scoped files continue to use the real sibling `ast`, `basic`, and root
  `sema` types. An attempted direct import of `sema.FFI.CheckCFuncParamType`
  exposed a package cycle (`sema.FFI -> sema -> sema.FFI`), so the root type
  checker keeps the equivalent CFunc type diagnostic logic locally until the
  package graph is split.

## Build

`cjpm build` passes for the whole workspace after this pass. Remaining warnings
are from pre-existing files outside this pass scope.

## Known Gaps

- The current `TypeCheckerImpl` self-host surface is still a coarse package-level
  pass, so these helpers are not yet wired into a full C++-faithful
  declaration/type/reference traversal pipeline.
- Full C++ parity still requires complete overload resolution, lookup/import
  recommendation, exact access-control context, alias substitution, promotion-based
  extend constraint filtering, exact generic specialization duplicate checks,
  orphan-rule diagnostics, pipeline wiring for type-alias and class-like
  declaration checks, reference-legality walker wiring, and all
  TypeChecker-owned state once those sibling surfaces are available in the
  allowed owner files.
- Diagnostics are mapped to the available self-hosted diagnostic tables; a few
  C++ diagnostic helpers are represented by the closest currently available
  refactored/legacy diagnostic kind.
- The six-file tc-decl scope has zero remaining `TODO(selfhost:Sema)` markers,
  but the wider Sema module is not complete.
