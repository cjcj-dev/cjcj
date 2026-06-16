# Sema tc-core Port Status

Scope deepened in this pass:

- `TypeCheckerImpl.cj`, `Search.cj`, `LookUpImpl.cj`, `PreCheck.cj`, `ExtraScopes.cj`, and `Assumption.cj`.
- Shared core support in `TypeManager.cj` and `CommonTypeAlias.cj` for explicit type-variable/instantiation scopes and substitution-pack clone/merge.
- Follow-up pass added `TypeCheck.cj` for the C++ `PreCheck.cpp` type-resolution core and extended `TypeCheckerImpl.cj` with facade methods for that pipeline.

Implemented behavior:

- Replaced the `TypeCheckerImpl`, `LookUpImpl`, and `ExtraScopes` status-only shims with compiling core APIs over the real self-hosted `ast`, `basic`, and `sema` type model.
- Added C++-shaped search wrappers for top-level declarations, all declarations, generic candidates, nominal/extend candidates, AST-kind queries, and deterministic source-position ordering over `ASTContext.searcher`.
- Added local/package lookup through `ASTContext.declMap`, including parent-scope walking, private-file visibility filtering, reference-type filtering, definition-order checks, variable/function shadowing behavior, property getter/setter availability checks, and nominal-body fallback lookup.
- Added field lookup for class/interface/enum/struct/package declarations, including ignored constructor/main entries, simple override/shadow replacement through `TypeManager.PairIsOverrideOrImpl`, inherited class/interface traversal, and extend-member lookup through `TypeManager.GetAllExtendsByTy`.
- Added precheck collection of declaration-name maps, member-signature maps, and enum-constructor buckets from the real AST declaration tree.
- Added generic upper-bound assumption propagation that records instantiated generic constraints and recursively follows generic reference/qualified upper bounds.
- Added explicit begin/end helpers for type-variable and instantiation-context scopes; `TypeManager.AllocTyVar` now registers allocated variables with the active type-variable scope.
- Added C++-shaped AST type synthesis for primitive, reference, qualified, VArray, tuple, parenthesized, function, option, invalid, builtin array/pointer/CString/CFunc/VArray, generic parameter, nominal, and type-alias declarations.
- Added declaration pretype initialization for generic parameters and nominal declarations, inherited-type resolution with direct subtype registration, var-with-pattern outer mapping, type-alias target resolution, alias substitution, and alias metadata on type references.
- `PreCheckPackage` now performs declaration-map collection followed by core pre-set declaration typing, so packages that call this helper receive initialized semantic `Ty` nodes instead of only lookup maps.

Known remaining gaps:

- Import-manager dependent lookup remains incomplete: imported declaration lookup, package member access rules, std.core/std.ast shortcut lookup, and extend accessibility filtering need the real self-hosted modules/import-manager surfaces.
- Diagnostics remain intentionally thin in this pass: undeclared/not-a-type/ambiguous type-name branches return invalid types but do not yet reproduce the exact C++ diagnostic emission paths.
- Field lookup does not yet perform full generic promotion/type-mapping for inherited interface members or all C++ override-cache side effects.
- `TypeCheckerImpl` still exposes only the shared core/search/lookup/reference/type-precheck helpers in this pass, not the full synthesis/check/cache/typecheck pipeline from `TypeCheckerImpl.h`.
- `ExtraScopes` uses explicit `Close`/end helpers rather than C++ RAII destructors; call sites must close scopes deliberately.

Verification:

- `cjpm build` passes after this pass, with only pre-existing unused-symbol warnings plus no new errors.
- `grep -rn "TODO(selfhost:Sema)" packages/sema/src` reports 65 remaining Sema markers, all outside the tc-core files touched in this pass.
- Remaining `TODO(selfhost:Sema)` markers in this tc-core touched scope: 0.

## 2026-06-17 Deepening Pass

Files deepened:

- `packages/sema/src/LookUpImpl.cj`
- `packages/sema/src/TypeCheck.cj`

Implemented behavior:

- Ported the C++ `CFunc` precheck behavior more faithfully. `CFunc<(A, B) -> R>` now resolves to a C function type with parameters `A, B` and return `R`, instead of incorrectly treating the whole function type argument as both the single parameter and return type.
- Updated builtin `CFunc` ty construction to require a `FuncTy` argument, matching the C++ `GetBuiltinCFuncType` contract rather than accepting arbitrary type arguments.
- Improved field lookup through extends by instantiating inherited interface types with the extend-to-base type mapping before recursing into interface member lookup.
- Matched the C++ static-member lookup adjustment that uses the generic form of an instantiated base type when looking up static non-classlike members.
- Improved inherited interface traversal by using `Promotion(typeManager).Promote` so generic interface inheritance follows promoted/instantiated parent interface types where available.

De-isolation finding:

- Attempted to wire `cangjie_compiler::modules.ImportManager` into lookup, but the current self-hosted `modules` package still owns local compatibility `File`, `Package`, and `Decl` definitions. Those are type-incompatible with the real `cangjie_compiler::ast` types used by Sema, so imported-declaration lookup and extend accessibility filtering cannot be made real from tc-core without editing `modules` outside this scope. The attempted calls were removed to keep the workspace green.

Verification:

- `cjpm build` passes after this pass.
- Remaining `TODO(selfhost:Sema)` markers in the tc-core-owned files listed by the task: 0.

## 2026-06-17 Continue Pass

Files deepened:

- `packages/sema/src/TypeCheck.cj`
- `packages/sema/src/TypeManager.cj`

Implemented behavior:

- Added a C++-shaped type-alias cycle check in the precheck type-alias phase. The pass walks resolved alias type syntax, tracks `InheritanceVisitStatus`, detects direct and indirect alias cycles, and marks participating aliases with `IN_REFERENCE_CYCLE` before alias substitution.
- Updated alias substitution in the shared `TypeManager` helper to preserve cyclic `TypeAliasTy` nodes instead of substituting through aliases marked `IN_REFERENCE_CYCLE`.
- Tightened builtin `VArray` type construction to require exactly one type argument, matching the C++ `GetBuiltInVArrayType` contract.

Remaining gaps:

- Alias-cycle diagnostics still only mark the AST; exact C++ diagnostic emission is not yet wired through the partial self-hosted diagnostic path.
- Import-manager dependent lookup remains blocked by modules-local compatibility AST types.

Verification:

- `cjpm build` passes after this pass.
- Remaining `TODO(selfhost:Sema)` markers in the tc-core-owned files listed by the task: 0.

## 2026-06-17 Continue Pass 2

Files deepened:

- `packages/sema/src/TypeManager.cj`

Implemented behavior:

- Matched the C++ `TypeManager::GetAllExtendsByTy` lookup order more closely. Nominal class/interface/struct/enum types now return declaration-owned extend declarations from `declToExtendMap` before falling back to builtin extend lookup.
- Added ideal numeric builtin extend expansion for `IdealInt` and `IdealFloat`, collecting extends registered on the concrete primitive integer and floating-point types instead of looking up only the ideal type key.

Remaining gaps:

- `GetTyForExtendMap` is still a thin identity helper; the C++ compatibility normalization for several builtin/instantiated cases remains to be ported.
- Full extend generic mapping and import-manager dependent lookup remain outside this pass.

Verification:

- `cjpm build` passes after this pass.
- Remaining `TODO(selfhost:Sema)` markers in the tc-core-owned files listed by the task: 0.
