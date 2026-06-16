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

## 2026-06-17 Continue Pass 4

Files deepened:

- `packages/sema/src/TypeManager.cj`

Implemented behavior:

- Added persistent top-level type-variable scope storage, matching the C++ `TypeManager` model that always has a top `TyVarScope` for placeholder variables.
- Added explicit placeholder type-variable scope-depth tracking. `AllocTyVar` now records each placeholder's scope depth, and placeholders derived from another type variable are registered in the parent variable's scope rather than always in the current scope.
- Replaced the stub `ScopeDepthOfTyVar` implementation with scope-depth lookup over the recorded depth table and active scopes.
- Replaced `GetInnermostUnsolvedTyVars` with active-scope filtering, so lambda/type-inference callers see only unsolved variables introduced in the innermost scope.
- Matched C++ unsolved-placeholder bookkeeping more closely by adding the `Any` sum-bound sentinel when marking a placeholder unsolved and checking that sentinel in `TyVarHasNoSum`.

Remaining gaps:

- Type-variable resource pooling from C++ is not modeled yet; released placeholders are removed from active tracking but not reused.
- The `SubstPack` contextual generic mapping overload still needs the C++ placeholder-aware traversal.

Verification:

- `cjpm build` passes after this pass.
- `grep -rn "TODO(selfhost:Sema)" packages/sema/src` reports 4 remaining package-level markers, all outside the tc-core-owned files.
- Remaining `TODO(selfhost:Sema)` markers in the tc-core-owned files listed by the task: 0.

## 2026-06-17 Continue Pass 3

Files deepened:

- `packages/sema/src/TypeManager.cj`

Implemented behavior:

- Ported the C++ `TypeManager::GetTyForExtendMap` normalization branches for extend lookup. Array types now map to the raw array key, pointer types map to `CPointer<Invalid>`, and instantiated nominal generics map to their generic declaration type before builtin extend lookup.
- Replaced the self-mapping placeholder in `GenerateGenericMappingFromGeneric` with the C++ behavior that maps parent generic parameters to the corresponding child generic parameter types when both generic parameter lists line up.
- Replaced the empty `GenerateStructDeclTypeMapping` stub with the C++ control flow for nominal and extend declarations, using the declaration type or extend target type as the mapping root.
- Lifted the `MultiTypeSubst` generic mapping traversal toward the C++ DFS: it now walks applicable extend declarations and classlike inherited types with a visited set and skips inheritance nodes marked `IN_REFERENCE_CYCLE`.

Remaining gaps:

- The `SubstPack` generic mapping overload still goes through the `MultiTypeSubst` bridge instead of the C++ placeholder-aware contextual traversal.
- Imported-declaration lookup and exact diagnostic paths remain blocked by dependencies outside this tc-core pass.

Verification:

- `cjpm build` passes after this pass.
- `grep -rn "TODO(selfhost:Sema)" packages/sema/src` reports 4 remaining package-level markers, all outside the tc-core-owned files.
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

## 2026-06-17 Continue Pass 4

Files deepened:

- `packages/sema/src/TypeManager.cj`

Implemented behavior:

- Ported the C++ `SubstPack` packing shape for `TypeSubst`, `MultiTypeSubst`, and single-type mappings. Universal generic variables now allocate an instantiation placeholder through `AllocTyVar`, and solutions are recorded under that placeholder; placeholder sources write directly to `inst` and drop self-solutions.
- Matched `ApplySubstPack` and `ApplySubstPackNonUniq` handling of `ignoreUnsolved` by filtering `u2i` to placeholders that already have solved `inst` entries before applying the two-stage substitution.
- Replaced the no-op `InstOf`, `RecoverUnivTyVar`, and `GetInstMapping` helpers with current `InstCtxScope` stack behavior. `RecoverUnivTyVar` now builds the inverse inst-to-universal substitution from the active mapping.
- Replaced the `SubstPack` generic-mapping bridge through `MultiTypeSubst` with the C++ contextual traversal over applicable extends and inherited classlike declarations. Non-contextual inherited visits now instantiate intermediate target type arguments through the current `u2i` mapping before generating direct substitutions.

Remaining gaps:

- The self-hosted instantiation-context helpers keep an empty-mapping fallback when no `InstCtxScope` is active instead of the C++ assertion-style precondition.
- Type-variable resource pooling from C++ is still not modeled; allocated placeholders are tracked and released but not reused.
- Exact diagnostic emission and import-manager dependent lookup remain blocked by surrounding partial ports outside this tc-core pass.

Verification:

- `cjpm build` passes after the code changes in this pass.
- `grep -rn "TODO(selfhost:Sema)" packages/sema/src` reports 4 remaining package-level markers, all outside the tc-core-owned files.
- Remaining `TODO(selfhost:Sema)` markers in the tc-core-owned files listed by the task: 0.
