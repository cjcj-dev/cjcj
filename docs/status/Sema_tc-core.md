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

## 2026-06-17 Continue Pass 5

Files deepened:

- `packages/sema/src/TypeManager.cj`

Implemented behavior:

- Ported C++ array/pointer type canonicalization: nested raw arrays now fold dimensions during construction, invalid array/pointer element types canonicalize to `Invalid`, and multi-dimensional `Array` type arguments project as `Array<elem, dims - 1>` for extend/generic mapping.
- Replaced one-step generic substitution with C++-shaped chained substitution, including generic-to-generic mapping traversal and composite mapped type instantiation.
- Deepened block real-type calculation to follow desugared blocks, empty/declaration-ending blocks, and desugared final expressions before falling back to the block type.
- Replaced thin supertype traversal with instantiated nominal inheritance traversal, transitive generic upper-bound collection, substitution mapping generation from nominal type arguments, and BFS interface inheritance with per-edge mappings.
- Reworked extend-interface queries to use registered extend declarations for nominal and builtin types, check generic extend instantiation, instantiate inherited interface types from extend target mappings, and resolve the actual superclass that provides an inherited class-to-interface boxing relation.
- Deepened `HasExtensionRelation`, `GetExtendDeclByInterface`, and `GetExtendDeclByMember` so boxing/extend queries consider direct interface inheritance, superclass-provided extends, interface member origins, and subtype-compatible inherited interfaces.
- Ported recursive `This` replacement and recursive alias substitution across class/interface/struct/enum/ref-enum/tuple/function/array/VArray/pointer/union/intersection types, preserving cyclic alias nodes and C++ generic-substitution behavior.

Remaining gaps:

- TypeManager still lacks C++ subtype cache/resource-pool behavior and placeholder unification through `LocalTypeArgumentSynthesis` in several subtype branches.
- Extend lookup still uses the self-hosted map representation only; import-manager-dependent filtering and exact accessibility side effects remain blocked by surrounding modules surfaces.
- Alias substitution does not yet reproduce alias-export diagnostics or alias-preservation choices for external declaration serialization.

Verification:

- `cjpm build` passes after this pass.
- Remaining `TODO(selfhost:Sema)` markers in the tc-core-owned files listed by the task: 0.

## 2026-06-17 Continue Pass 6

Files deepened:

- `packages/sema/src/TypeManager.cj`

Implemented behavior:

- Replaced the flattened `IsSubtype` implementation with C++-ordered subtype helper logic: quest/invalid/fast-path handling, placeholder unification through `LocalTypeArgumentSynthesis`, generic upper-bound and alias-parameter checks, classlike supertype comparison, struct/enum interface boxing, exact array/VArray/pointer checks, primitive ideal-literal handling, and extend-interface boxing.
- Added a subtype query cache keyed by `(leaf, root, implicitBoxed, allowOptionBox)` to match the C++ recursion guard behavior; placeholder-involving entries are dropped after each query like the C++ cache.
- Ported C++ `implicitBoxed` and `allowOptionBox` semantics that had previously been ignored, including the stricter `Any` behavior when boxing is disabled and nested `Option` auto-boxing only when allowed.
- Tightened function, tuple, array, VArray, pointer, and primitive subtype checks toward the C++ contracts: function parameters use `noCast`, C-function and vararg flags must match, tuple element checks disable implicit boxing, array dimensions and VArray sizes must match, and non-ideal primitive numeric widening is no longer treated as a general subtype.
- Deepened `IsTyEqual`, `IsLitBoxableType`, and `CheckTypeCompatibility` with C++-shaped generic equality, enum/ref-enum compatibility, common/specific declaration matching, and constraint snapshot/restore around equality checks.
- Cleared subtype query state from `Clear` and `ReleaseSemaQueryCaches`, matching the C++ query-cache lifecycle.

Remaining gaps:

- `CheckTypeCompatibility` still preserves the current self-hosted call-site convention (`target, actual`) instead of migrating all callers to the C++ parameter direction in one pass.
- C++ subtype cache uses pointer-identity/hash containers; the self-hosted version uses linear `SameTy` lookup because shared map/hash support for compound type keys is still local to this port.
- Placeholder unification is delegated to the current self-hosted `LocalTypeArgumentSynthesis`; any fidelity gaps in that sibling logic remain visible through subtype checks.
- Imported-declaration lookup, exact diagnostic emission, and alias-export diagnostics remain outside this pass.

Verification:

- `cjpm build` passes after this pass.
- `grep -rn "TODO(selfhost:Sema)" packages/sema/src` reports 4 package-level markers, all outside the tc-core-owned files.
- Remaining `TODO(selfhost:Sema)` markers in the tc-core-owned files listed by the task: 0.

## 2026-06-17 Continue Pass 8

Files deepened:

- `packages/sema/src/TypeManager.cj`

Implemented behavior:

- Ported the C++ `GetOverrideDeclInClassLike` member scan shape. The self-hosted path now skips non-function/property members, honors `withAbstractOverrides`, ignores generic members, and checks property getter/setter functions as override candidates.
- Tightened `IsFuncDeclSubType`, `IsFuncTySubType`, and `IsFuncDeclEqualType` toward the C++ declaration-override contract: identifiers must match, both declaration types must be function types, parameter types are checked for identity, returns are checked covariantly, and equality is subtype in both directions.
- Replaced the name-only `PairIsOverrideOrImpl` approximation with C++-shaped function and property override checks. Function matching now uses static/non-static filtering, override cache lookup/update, instantiated outer/generic type mappings, expected instantiated parent mappings, promoted parent-interface mappings, parameter instantiation before identity comparison, and common/specific cross-platform exclusion.
- Added property override matching through instantiated property types, interface-base generic mapping fallback, and top-overridden accessor map updates for same-instantiated-type property overrides.

Remaining gaps:

- The override cache remains a linear self-hosted table keyed by `SameDecl`/`SameTy` rather than the C++ pointer-keyed hash containers.
- Property matching uses structural `SameTy` for instantiated target type equality because the self-hosted type manager does not model C++ allocated type pointer identity.
- Exact diagnostics, import-manager dependent lookup, and full inherited-member accessibility filtering remain outside this pass.

Verification:

- `cjpm build` passes after this pass.
- `grep -rn "TODO(selfhost:Sema)" packages/sema/src` reports 4 package-level markers, all outside the tc-core-owned files.
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

## 2026-06-17 Continue Pass 7

Files deepened:

- `packages/sema/src/TypeManager.cj`

Implemented behavior:

- Ported the C++ constructor-shaped placeholder constraint helpers. `AddSumByCtor` now pads missing constructor type arguments with fresh solving placeholders derived from the constrained type variable, builds the constructor generic substitution, records the instantiated placeholder type in the sum bound, and returns that instantiated type.
- Replaced `ConstrainByCtor`'s previous direct upper-bound insertion with the C++ flow: reuse an existing upper bound with the same constructor shape, otherwise instantiate the constructor with fresh placeholders and accept it only when the constrained placeholder is a subtype under `allowOptionBox: false`.
- Replaced the kind/name-only `OfSameCtor` check with C++-style constructor substitution equality over valid types and matching type-argument arity.

Remaining gaps:

- The helpers conservatively return `None`/`false` when a constructor type argument is not represented by a `GenericsTy`; the C++ reference asserts that shape through `StaticCast`.
- Full override/property matching and import-manager dependent lookup remain outside this focused pass.

Verification:

- `cjpm build` passes after this pass.
- `grep -rn "TODO(selfhost:Sema)" packages/sema/src` reports 4 package-level markers, all outside the tc-core-owned files.
- Remaining `TODO(selfhost:Sema)` markers in the tc-core-owned files listed by the task: 0.
