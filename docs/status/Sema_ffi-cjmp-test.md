# Sema ffi-cjmp-test deepening status

Date: 2026-06-17
Build: `cjpm build` passes.
Scoped selfhost TODO comments: 0 remaining in the requested files.
Whole-package selfhost TODO grep: 4 existing markers remain outside the allowed ffi-cjmp-test edit area.

## 2026-06-17 mock accessor parity pass

- Switched mock-support property marking to the real `GetUsableGetterForProperty` and `GetUsableSetterForProperty` helpers, matching the C++ behavior for inherited/usable accessors instead of assuming index-zero accessors.
- Added the C++ generated mock-accessor attribute bundle helper: clear generic-instantiated/access modifiers, apply the requested access level, and mark generated/compiler-added/classlike attributes together.
- Added mock utility parity for generic type-node creation, type-cast match construction with `matchBeforeRuntime = false`, and function type erasure to `Any`.
- Added mock-manager helper parity for package accessibility checks, framework accessor-kind string mapping, and setter-presence metadata decisions used by mock call metadata generation.
- Verified with `cjpm build`; scoped files still have no `TODO(selfhost:Sema)` markers.

## 2026-06-17 override/mock propagation pass

- Added `TypeManager`-backed `@Hide` override-function checking in `PluginCustomAnnoChecker`, including fallback to the enclosing declaration's `@Hide` annotation and the C++ missing/different-parameter diagnostics against the top overridden function.
- Made plugin annotation cache merging authoritative for syscap and lowest API level, matching the C++ `MergeCachedAnnoInfo` behavior when cached declarations have no syscap or a lower/zero level.
- Added the TestManager fixed-point walk that marks generic functions containing `createMock`/`createSpy`-relevant calls, including propagation through already marked generic callees and the post-visit reset used by the C++ pass.
- Verified with `cjpm build`; scoped files still have no `TODO(selfhost:Sema)` markers.

## 2026-06-17 continuation pass

- Added LSP relative-position lookup using the real `ASTContext` searcher, `Query` tree, and scope-gate APIs.
- Added mock-support helper parity for `this` reference creation, field/static/top-level accessor classification, desugar-chain extraction, static class member detection, and class-like/generic type filtering.
- Added mock-support bookkeeping for used internal declarations and the C++ `NeedEraseAccessorTypes` decision.
- Added mock utility generated-accessor lookup for member access, top-level variables, and class/superclass search using real AST declarations.
- Verified with `cjpm build`; the scoped files still have no `TODO(selfhost:Sema)` markers.

## 2026-06-17 follow-up pass

- Added NativeFFI parity helpers for boolean `match` construction and returning-lambda wrapping, using the real AST constructors, function types, unsafe block attribute, and current-file propagation.
- Added CJMP candidate filtering for common functions when specific candidates exist, matching the C++ rule that drops common-from-common-part functions only in the presence of specific overloads.
- Replaced the CJMP generic constraint compatibility no-op with the real `InheritanceChecker` generic-bound comparison helpers.
- Added CJMP generic type substitution for members copied from common declarations into specific declarations, including `NameReferenceExpr.instTys` rewriting.
- Added CJMP inherited-type retargeting to specific implementations for platform compilation.
- Added LSP base-name and scope-name handling for parenthesized expressions.
- Added mock utility parity for extension-aware outer declaration lookup, extended-type lookup, internal-type containment detection, and var getter/setter accessor-kind helpers.
- Verified with `cjpm build`.

## Implemented in this pass

- Deepened C FFI checks with real foreign-without-`@C` diagnostics, recursive zero-sized C type detection, unsafe/inout legality helpers, invalid reference checks for C functions, C struct member validation, and unsafe-call diagnostics wired to the shared AST and diagnostic packages.
- Added CJMP collection and matching logic for common/specific declarations, nominal declaration attribute and supertype matching, enum constructor matching, variable pattern matching, direct-extension private member conflicts, specific abstract-class member checks, and common open-class prechecks.
- Expanded plugin custom annotation checking with semantic target recognition for `@APILevel` and `@Hide`, duplicate `@Hide` diagnostics, function-parameter and compile-time visibility checks, per-declaration annotation caching, and extension/member hide consistency checks.
- Improved mock/test semantic preparation by collecting global/static/extension functions, classes with defaulted interfaces, interfaces with default implementations, and extension-default interface pairs; mock accessor argument rendering now erases generic declaration arguments like the C++ helper.
- Continued NativeFFI utility parity with Objective-C generated member predicates, CJMapping generic detection, Ty and AST-Type generic instantiation helpers, generic-parameter visibility checks, and the C++-faithful `this(...)` call-kind test.
- Added NativeFFI generic replacement and interop naming helpers: function generic type substitution, constructor argument generic actual-type collection, instantiated nominal type construction, CJMapping tuple names, function-type Java lambda names, and parameter TypeKind validation.
- Added more NativeFFI utility parity: `this`/`super` reference and constructor-call builders, unit/type/function-type node builders, Java `JArray` recognition, array operation classification, generic function-type replacement helper, and Java lambda class-name generation from the real Basic `LambdaPattern`.
- Added mock helper parity for mutable-field getter detection, original accessor identifier recovery, generated global accessor lookup, and foreign accessor naming.
- Added TestManager semantic helpers for package mock-support consistency, generic mock-creation call propagation, and in-package mock usage scanning with the real AST walker.
- Ported additional plugin custom-annotation helper behavior: module-name extraction, syscap diagnostic formatting, API/syscap/hide reference checks, C++-style target selection for `CheckNode`, imported class-like external-weak marking, and linkage propagation to desugared parameters/macros/property accessors.
- Extended plugin package traversal to match the C++ checker more closely: declaration-scope annotation accumulation, `IfAvailable` scope construction from desugared `IfExpr`, then/else branch checking with external-weak fallback marking, lower API-level diagnostics, and macro-order diagnostics for `@APILevel`/`@Hide` before other macro expansions.
- Kept all new logic on real sibling package types rather than adding local compatibility copies.

## Remaining fidelity gaps

- C FFI still lacks backend-option-sensitive unsafe-call gating and the full platform ABI diagnostic matrix from the C++ checker.
- CJMP common member symbol-table rewriting, some extension declaration-map updates, and several merged-member ownership details remain partial.
- Plugin checking now has the core reference-check helpers, external-weak marking hooks, scoped traversal, macro-order checks, IfAvailable branch walking, and override-hide comparison when a `TypeManager` is supplied, but still lacks full option/import-manager parsing, dependency annotation clearing, and call-site wiring from the complete C++ checker.
- Mock/test support now has stronger semantic classification, naming, lookup, accessor metadata, package usage detection, and preparation plumbing, but generated wrapper/body synthesis and full injection behavior are still incomplete.
- NativeFFI utilities now cover more reference, generic, type-node, Java-array, and naming helpers, but larger AST synthesis/desugaring helpers, mangler-driven method naming, import-manager core declaration helpers, abort-on-invalid array classification, and full Java/ObjC interop manager behavior remain incomplete.
- LSP base-name, scope-name, and relative-position helpers are present, but the C++ type synthesizer half remains outside the current self-host surface.

Honest real-behavior coverage for this scoped pass is estimated at 55% versus the corresponding C++ reference surface.
