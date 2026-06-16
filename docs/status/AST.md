# AST Port Status

Date: 2026-06-17

## Summary

The AST package is a multi-file Cangjie package mirroring the C++ AST component layout. It defines the ported AST kind and type-kind enums, attributes, identifiers, comments, symbols, type hierarchy, node hierarchy, declarations, expressions, patterns, macro nodes, import/package nodes, walkers, search/query helpers, cache structures, context state, cloning helpers, creation helpers, printing helpers, casting predicates, recovery utilities, validation helpers, and AST utility functions.

`cjpm build` passes for the workspace, and `packages/ast/src` currently has zero AST self-host TODO comment markers.

## Implemented In This Pass

- Added C++ `Ty` helper parity for primitive upper-bound extraction, C ABI type classification (`IsPrimitiveCType`, `IsCStructType`, `IsMetCType`, `IsCTypeConstraint`), type-argument size checks, initial-type checks, and instantiated nominal type to generic type lookup.
- Added recursive generic type-argument collection APIs, including candidate-filtered generic collection with duplicate suppression.
- Added C++ `GetTypesToStr` / `GetTypesToStableStr` parity and routed union/intersection type stringification through stable name/hash ordering for deterministic output.
- Ported C++ `Decl.GetGeneric` enum-member behavior so enum-contained `VarDecl` nodes inherit the enum generic when they have no function-body generic source.
- Deepened `Node.cpp` `ToString` parity across type nodes: invalid type spelling, qualified-type arguments, multi-question option types, varray size omission when absent, optional function-type returns, and empty generic/generic-constraint formatting.
- Added C++ pattern stringification for invalid, const, wildcard, tuple, type, enum, var-or-enum, except-type, and command-type patterns.
- Added C++ declaration stringification for function parameters, function bodies, functions, type aliases, class/struct/interface bodies, and invalid declarations, including explicit modifier prefixes and generic constraints.
- Added C++ expression stringification for blocks, if/for/while/do-while/match/try forms, let-pattern destructors, token/quote/interpolation expressions, throw/perform/resume/return/jump, casts, parens, lambdas/trailing closures, optional chains, arrays, pointers, type conversions, invalid expressions, spawn, and synchronized expressions.
- Added C++ `Ty::GetDeclOfTy` / `Ty::GetDeclPtrOfTy` parity helpers in `Types.cj`, including nominal class/interface/struct/enum/type-alias declaration lookup and `specificImplementation` remapping for generic-declaration lookups.
- Ported `ExtendDecl.IsExportedDecl` from `Node.cpp`: extended type-argument export checks, same-package direct-extension rules, `std.core` direct-extension export behavior, interface-extension inherited-interface export checks, and generic upper-bound export constraints.
- Ported extend-member export behavior for `FuncDecl` and `PropDecl`, so direct extensions of foreign-package types hide members while interface implementations export only interface-implementation members.
- Aligned `FuncDecl.IsOpen` and `PropDecl.IsOpen` with the C++ outer-declaration rules, static/imported checks, and body/accessor absence handling instead of treating local `open`/`abstract` attributes alone as sufficient.
- Deepened `InheritableDecl` inheritance helpers: direct interface types are de-duplicated, stable interface lists now use the existing `CompTyByNames` ordering, and `GetAllSuperDecls` now performs the C++ breadth-first traversal through class/interface inherited types with cycle/duplicate guards.
- Aligned `Decl.GetMemberDeclPtrs` with the C++ helper by returning a fresh member list per nominal/extend declaration and including enum constructors before enum members without changing mutable `GetMemberDecls` behavior.
- Deepened macro-call source-position recovery in `Node`: `GetMacroCallPos` now follows the C++ same-line guard for expanded nodes, skips pure custom annotations, and refuses cross-file direct macro mappings.
- Ported C++-style `GetMacroCallNewPos` behavior for LSP macro positions: it selects the outermost macro invocation, consults `originPosMap` and `origin2newPosMap`, and returns `INVALID_POSITION` when no faithful mapping exists.
- Ported `GetDebugPos` macro debug-map lookup so desugar/debug position recovery can map generated macro columns back to original positions.
- Added AST `IsPureAnnotation(MacroInvocation)` utility parity with the C++ inline helper.
- Fixed `CloneMacroInvocation` to allocate a fresh `MacroCallDiagInfo` rather than aliasing the source object's class reference, preserving scalar diagnostic fields without Cangjie reference sharing.
- De-isolated AST support types from local compatibility copies to the real sibling packages.
- Added AST package dependencies on `cangjie_compiler::basic`, `cangjie_compiler::lex`, and `cangjie_compiler::utils`.
- Re-exported real Basic/Lex/Utils APIs through `Common.cj`: `Position`, `Range`, `MakeRange`, `Linkage`, `MacroCallDiagInfo`, `TokenKind`, `Token`, `StringPart`, token helpers, `TokenVecMap`, and `OverflowStrategy`.
- Kept `TokenKindText` only as an AST spelling compatibility wrapper over `lex.TokenKindLiteral`.
- Updated comments to store real `lex.Token` values.
- Added owner-side support needed by existing AST/Sema users after de-isolation: `basic.Linkage` equality and `basic.Position.ToString()`.
- Deepened `ASTTypeValidator` toward the C++ pre/post strategy: shared walker IDs for desugared expressions, skip-child handling for ignored kinds, no-ty-kind separation, generic type-node skipping, package-decl target skipping, and rejection of unresolved invalid/ideal/quest semantic types.
- Aligned `Cache.CollectTargets` with the C++ target-cache rule so member-base targets are preserved only when the node itself has a target.
- Aligned `ScopeManagerApi.GetChildScopeName` with the C++ first-child-split replacement behavior.
- Aligned `AttributePack.ToString` and `GetAllIdxOfAttr` with the C++ `ATTR2STR` names and bit-index traversal order, including the deprecated macro-expanded-node spelling and invalid mapping guard.
- Deepened query/search behavior toward C++: canonical `scope_name`, `scope_level`, and `ast_kind` spellings now parse, pretty-print cache keys use `key=value`, unsupported scope-name suffix and AST-kind prefix matches return empty, and position equality/closed comparisons follow the C++ search implementation.
- Added C++-style inverted-index trie members for names, scopes, AST kinds, and begin/end positions; `Searcher` now evaluates name/scope/kind/level leaves through indexes when available, preserves linear fallback for unindexed partial-port callers, removes deleted symbols from query results, uses C++ position sort tie-breaks, and aligns `InvalidateCacheBut` with substring retention.
- Ported the C++ `PosSearchApi` common-root trie walk for encoded positions and routed `PositionQuery` through begin/end position tries when the AST context has populated them.
- Aligned `IntLiteral` with `IntLiteral.cpp` for byte literal parsing (`b'x'`, escapes, and `b'\u{...}'`), parse-range handling, native integer bitness resolution, signed/unsigned wrapping and saturating values, and unsigned-vs-signed `GetValue` formatting.

## Existing Ported Coverage

- Per-component AST source files under `packages/ast/src`.
- Main public node/type surfaces from `Node.h`, `NodeX.h`, `Types.h`, `AttributePack.h`, `Identifier.h`, `Comment.h`, `Symbol.h`, `IntLiteral.h`, import/package nodes, and reference-type classification.
- AST child traversal, cloning, query/search helpers, source-position helpers, context/cache helpers, creation helpers, print helpers, recover-desugar helpers, casting/category predicates, literal constant initialization, and AST type validation.
- Utility parity for size-property lookup, Java attribute probing, outer function ownership propagation, declaration-attribute ancestry checks, pattern flattening, top-level/exportable declaration iteration, package member access detection, `this`/`super` detection, access-level mapping and formatting, import item name reconstruction, condition detection, enum-subpattern checks, source-export predicates, virtual-member checks, generic instance-member variable checks, member-variable export checks, variable initialization ordering, and mirror property signature synthesis.
- Type-system helpers for generic lower-bound subtype predicates, type-alias extendability through aliased types, core-package nominal checks, union/intersection-aware recursive type queries, nominal generic type lookup, inherited interface lookup on nominal types, structural type hashing, and type-cache keys.

## Remaining Work

- Wire AST validation and diagnostics through the real `DiagnosticEngine` instead of the current local validation result surface.
- Resolve `ScopeKind` and `ExprKind` layering with Parse once the self-hosted packages can share those APIs without introducing a package cycle. The C++ AST only forward-declares the related parse concepts, so the current AST-local minimal enums are kept until that dependency direction is settled.
- Finish exact C++ `Searcher` parity for diagnostic-producing query parse failures, file-hash query normalization/filtering, and broader downstream validation of indexed position searches once the collector/scope-manager pipeline fully populates indexes in the Cangjie port.
- Continue auditing macro diagnostic map lifetimes through Parse/Macro/Sema; AST now avoids clone-time `MacroCallDiagInfo` aliasing, but full private Basic map reconstruction is still owned by the macro pipeline.
- Continue auditing context, walker, clone, printer, recover-desugar, search/query, type, utility, and validation behavior against the complete C++ implementation under downstream Parse/Sema workloads.
- Replace any remaining compatibility API spellings only after downstream packages no longer depend on them.
