# Sema tc-decl Deepening Status

Date: 2026-06-18

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
- This pass deepened `TypeCheckType.cj` further: `VArray` reference-type
  detection now instantiates generic struct member types through the real
  `Promotion`/`TypeManager` path before recursing, and `RefType` generic
  constraint checking now resolves type aliases to the substituted real target
  type arguments instead of checking only the alias declaration surface.
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
- This pass deepened `TypeCheckReference.cj` further: extend member candidate
  filtering now mirrors the C++ promotion path, including inherited-interface
  extend lookup and promoted extended-type generic constraint checks, and
  deprecated usage diagnostics now extract `message`, `since`, and `strict`
  from the real `@Deprecated` annotation payload to choose warning vs error and
  preserve diagnostic suffix text.
- This pass tightened deprecated-reference parity further: direct diagnostics
  now honor the C++ same-package deprecated/strict-deprecated context
  suppression, enum constructor member-access patterns are skipped like the C++
  `GetDiagnoseKindOfFuncDecl` path, and a target-level helper now reports
  constructor/type-alias mediated deprecations through real AST parent and alias
  links.
- This pass added a real `TypeCheckReferenceCheckUsageOfDeprecated` walker
  mirroring the C++ `CheckUsageOfDeprecated` flow: it tracks deprecated and
  strict-deprecated declaration contexts, skips common-part declarations and
  enum-pattern subtrees, diagnoses deprecated parameters and property setters,
  checks constructor/type-alias mediated targets, and reports deprecated
  override/redefinition and inheritor strictness issues through existing
  `TypeManager`, property-accessor, and AST walker APIs.
- This pass tightened reference parity further: deprecated parameter diagnostics
  now match arguments back to function parameters using the shared `GetArgName`
  rules and default/source argument lists instead of positional-only matching,
  and `TypeCheckReferenceCheckThisOrSuperInInitializer` now mirrors the C++
  initializer restriction diagnostics for `this`/`super` in static and
  non-static member initializers.
- This pass added the C++-style reference-legality traversal entry point in
  `TypeCheckReference.cj`: it reconstructs current enclosing symbols from the
  real `ASTContext` scope-gate index, skips the same primary-constructor,
  annotation, common-part, and desugared-default-argument subtrees as C++,
  walks desugared expressions with the same walker id, preserves the
  `currentCheckingNodes` var-initializer stack, checks `this`/`super` usage
  diagnostics (static context, interface/extend/non-class `super`, illegal
  standalone `super`, struct constructor capture, inheritable constructor/finalizer
  `this`, and CFunc lambda capture), reuses the real struct-mutation checker for
  assignment/inc-dec/inout arguments, and performs member-access legality in
  post-order after child reference checks.
- Continued class-like parity in `TypeCheckClassLike.cj`: sealed inheritance
  from `specific` declarations now mirrors the C++ package scan for a matching
  common declaration before reporting the specific-sealed diagnostic, and
  superclass validation now rejects `OPEN_TO_MOCK` classes like the C++
  `TestManager::IsDeclOpenToMock` path.
- This pass tightened class-like parity further: the `ThreadContext` inheritance
  whitelist now checks the declaration's owning file package like the C++ path,
  with `fullPackageName` retained only as a fallback for partially constructed
  AST nodes.
- Deepened extend checking toward `TypeCheckExtend.cpp`: extend-map construction
  now checks duplicate direct interface implementations, duplicate inherited
  interface implementations, and non-extendable `std.core.Any`/`std.core.CType`
  interfaces, and immutable type extensions now reject assignment index
  operators as well as mutable properties.
- This pass deepened `TypeCheckExtend.cj` further: extend declaration checking
  now mirrors the C++ orphan-rule validation for imported/primitive extended
  types, collecting related extends from inherited class chains and inherited
  interface supers before reporting external-interface violations; immutable
  extension diagnostics now point at the function identifier or `mut` modifier
  like the C++ diagnostics.
- Continued extend parity in `TypeCheckExtend.cj`: the C++ duplicate default
  implementation check for multiple `extend` declarations implementing the same
  generic interface with different type arguments is now wired into extend
  declaration checking, reporting default interface members that do not depend
  on the interface's outside generic parameters.
- This pass deepened extend specialization checks further: generic class-like
  extended targets now run the C++ instantiated-interface duplicate check,
  substituting the original declaration's generic parameters into inherited
  interfaces and other generic extends while preserving the C++ conflict rule
  for incompatible repeated generic mappings.
- Continued extend specialization parity: builtin `CPointer` extend-map entries
  now mirror the C++ primitive precheck by finding the `std.core` generic
  pointer extend and checking user pointer extends against that core
  declaration for instantiated duplicate interface implementations.
- Continued duplicate-interface parity: extend interface prechecking now groups
  builtin and declaration extend-map entries by the actual extended type,
  instantiates implemented interfaces through the real `Promotion` type mapping,
  and diagnoses the last source implementation when a promoted interface
  duplicates a base inherited interface or another extend implementation.
- Deepened annotation checking toward `TypeCheckAnnotation.cpp` by preserving
  the C++ `NO_REFLECT_INFO` marker on custom annotation call expressions that
  are not compile-time visible.
- Continued annotation parity in `TypeCheckAnnotation.cj`: custom annotation
  recovery now runs the shared `RecoverToCallExpr` desugar rollback before
  moving the call payload back, and successful custom annotation checks clone
  the resolved base expression and function arguments back into the original
  annotation so cjo serialization retains the C++ payload shape while
  `annotationsArray` keeps the checked call expression.
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
  recommendation, exact access-control context, custom annotation expression
  synthesis/type checking, annotation target-array type checking, pipeline
  wiring from the coarse `TypeCheckerImpl` package pass into the declaration,
  type, reference-legality, and deprecated-usage helpers, exact C++ constructor
  parameter/member-access checks, instantiated-type completeness checks, and all
  remaining TypeChecker-owned state once those sibling surfaces are available in
  the allowed owner files.
- Diagnostics are mapped to the available self-hosted diagnostic tables; a few
  C++ diagnostic helpers are represented by the closest currently available
  refactored/legacy diagnostic kind.
- The six-file tc-decl scope has zero remaining `TODO(selfhost:Sema)` markers,
  but the wider Sema module is not complete.
