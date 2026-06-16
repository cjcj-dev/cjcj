# Sema ffi-cjmp-test deepening status

Date: 2026-06-17
Build: `cjpm build` passes.
Scoped selfhost TODO comments: 0 remaining in the requested files.

## Implemented in this pass

- Deepened C FFI checks with real foreign-without-`@C` diagnostics, recursive zero-sized C type detection, unsafe/inout legality helpers, invalid reference checks for C functions, C struct member validation, and unsafe-call diagnostics wired to the shared AST and diagnostic packages.
- Added CJMP collection and matching logic for common/specific declarations, nominal declaration attribute and supertype matching, enum constructor matching, variable pattern matching, direct-extension private member conflicts, specific abstract-class member checks, and common open-class prechecks.
- Expanded plugin custom annotation checking with semantic target recognition for `@APILevel` and `@Hide`, duplicate `@Hide` diagnostics, function-parameter and compile-time visibility checks, per-declaration annotation caching, and extension/member hide consistency checks.
- Improved mock/test semantic preparation by collecting global/static/extension functions, classes with defaulted interfaces, interfaces with default implementations, and extension-default interface pairs; mock accessor argument rendering now erases generic declaration arguments like the C++ helper.
- Kept all new logic on real sibling package types rather than adding local compatibility copies.

## Remaining fidelity gaps

- C FFI still lacks backend-option-sensitive unsafe-call gating and the full platform ABI diagnostic matrix from the C++ checker.
- CJMP generic constraint diagnostics, common member symbol-table rewriting, some extension declaration-map updates, and several merged-member ownership details remain partial.
- Plugin checking still lacks the complete external plugin configuration and API-level/global-option integration path from the C++ implementation.
- Mock/test support now has stronger semantic classification and preparation plumbing, but generated wrapper/body synthesis and full injection behavior are still incomplete.
- NativeFFI and LSP files were reviewed for this scope but not changed in this pass; their broader C++ helper surface remains incomplete.

Honest real-behavior coverage for this scoped pass is estimated at 36% versus the corresponding C++ reference surface.
