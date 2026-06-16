# Sema ffi-cjmp-test deepening status

Date: 2026-06-17
Build: `cjpm build` passes.
Scoped TODO markers: 0 remaining `TODO(selfhost:Sema)` markers in the requested files.

## Implemented in this pass

- Replaced scoped stubs in C FFI, NativeFFI utilities, CJMP declaration matching, CJMP annotation matching, plugin custom annotation checking, mock/test semantic helpers, and LSP type-check helpers with real code wired to the shared AST, sema type manager, option, and basic diagnostic packages.
- Added CJMP diagnostics for mismatched parameters, generic arity, missing common/specific implementations, annotation mismatches, return type mismatches, variable type mismatches, and default-argument conflicts.
- Added focused C FFI prechecks for `@C`, `@CallingConv`, `@FastNative`, `@Frozen`, foreign linkage setup, C function signature validation, and invalid C parameter/reference cases.
- Added NativeFFI helpers for foreign-name annotations, Objective-C mirror names, constructor-call classification, generic instantiation config, primitive type lookup, and Cangjie library-name derivation through the real option package wrappers.
- Added plugin custom annotation parsing/checking for API level, `since`, `syscap`, `ifAvailable`, and `@Hide` arguments using real plugin data structures.
- Added mock/test helpers for mock call recognition, mock class naming, mockability checks, generated accessor naming, accessor-kind classification, mock preparation collection, and package-name normalization through the real source manager suffix.
- Added LSP scope-name and base-name helpers for declarations, references, member access, calls, type references, and selected pattern/selector forms.

## Remaining fidelity gaps

- NativeFFI still lacks the full C++ AST synthesis/desugaring helper surface for generated `this`/`super` calls, synthesized lambda wrappers, mangling integration, Objective-C bridging, and import-manager driven core declarations.
- Mock/test support is semantic classification and preparation plumbing only; full C++ desugar/injection behavior, generic instantiation handling, and accessor body synthesis remain incomplete.
- C FFI covers core annotation/signature checks but not the entire reference matrix of platform ABI handling, every diagnostic edge case, and full downstream integration.
- Plugin custom annotation checking parses the main argument shapes but does not yet load or merge the complete external plugin JSON configuration path from the C++ implementation.
- LSP support covers common scope/base-name propagation, but not all C++ visitor edge cases.

Honest real-behavior coverage for this scoped pass is estimated at 24% versus the corresponding C++ reference surface.
