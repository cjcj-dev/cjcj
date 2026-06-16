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

- Replaced the six local self-host TODO sentinels with compiling Cangjie helper surfaces backed by the real sibling `ast` and `basic` packages.
- Added shared source-range selection, legacy and refactored diagnostic emission paths, and AST enum aliasing to avoid local compatibility definitions.
- Added declaration checking helpers for enum-constructor registration, `main` entry validation, operator overload arity/classification, enum-element type propagation, initializer/type synchronization, type-alias generic-use collection, and nominal member collection.
- Added type checking helpers for reference-type legality, `Option<T>` validation, `VArray` reference containment checks, generic argument arity checks on reference/qualified types, tuple `@C` field rejection, and C function parameter/return legality.
- Added reference checking helpers for type-argument target filtering, enum-constructor target diagnostics, duplicate target removal, extend-constraint filtering, member/name access target filtering, static/member access diagnostics, and deprecated-use diagnostics.
- Added class-like checking helpers for annotation constructor/visibility rules, sealed and thread-context inheritance checks, class inherited-type classification, interface inherited-type validation, sub-declaration registration, and nominal annotation rule checks.
- Added extend checking helpers for generic-use checks, extended-type validity, inherited-interface validation, extend-map population, external attribute propagation, immutable-type/interface mutability restrictions, and extend declaration validation.
- Added annotation helpers for custom annotation place validation, annotation-declaration `target` argument validation, custom annotation call desugaring/recovery, annotation array construction, and per-declaration annotation checking.
- Fixed Option/cast handling so newly added inheritance and type traversal paths are reachable instead of warning-only inert branches.

## Build

`cjpm build` passes for the whole workspace. Remaining warnings are from pre-existing files outside this pass scope.

## Known Gaps

- The current `TypeCheckerImpl` self-host surface is still a coarse package-level pass, so these helpers are not yet wired into a full C++-faithful declaration/type/reference traversal pipeline.
- Full C++ parity still requires integrating overload resolution, complete target lookup, substitution/inference context, import recommendation, macro diagnostic mapping, access-control context, and all TypeChecker-owned state once those sibling surfaces are available in the allowed owner files.
- Diagnostics are mapped to the available self-hosted diagnostic tables; a few C++ diagnostic helpers are represented by the closest currently available refactored/legacy diagnostic kind.
- This pass removes all `TODO(selfhost:Sema)` markers in the six-file tc-decl scope but does not claim the wider Sema module is complete.
