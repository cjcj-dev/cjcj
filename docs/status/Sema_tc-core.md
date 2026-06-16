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
