# AST Port Status

Date: 2026-06-18

## Summary

The AST package is a multi-file Cangjie package mirroring the C++ AST component layout. It defines the ported AST kind and type-kind enums, attributes, identifiers, comments, symbols, type hierarchy, node hierarchy, declarations, expressions, patterns, macro nodes, import/package nodes, walkers, search/query helpers, cache structures, context state, cloning helpers, creation helpers, printing helpers, casting predicates, recovery utilities, validation helpers, and AST utility functions.

`cjpm build` passes for the workspace, and `packages/ast/src` currently has zero AST self-host TODO comment markers.

## Implemented In This Pass

- Added C++ `Ty::IsCTypeBasePointer` API parity for C ABI pointer-like types and changed `Ty.GetInitialTy` to return a shared `InitialTy` sentinel like the C++ static object instead of allocating a fresh sentinel for each call.
- Aligned `CommentGroups.ToString` with `Comment.cpp` inner-comment formatting by using the C++ no-space separator for `innerComments` groups while preserving the spaced separators for leading and trailing groups.
- Aligned `File.GetFeatures` with the C++ `std::set` result semantics by returning feature names in sorted order with duplicates suppressed while preserving the Cangjie `ArrayList<String>` API.
- Added C++ `InvertedIndex::Reset` parity for AST-kind suffix searches: AST now keeps a shared `AST_KIND_VALUES` string table and preloads `astKindTrie` with every AST kind name after reset, matching the reference behavior for fresh contexts before symbols are indexed.
- Aligned import/package node stringification and import-name helpers with `Node.cpp`: `ImportContent` now handles import-all package names, declaration-import package names, double-colon organization prefixes, possible package-name resolution order, aliases, multi-import formatting, feature dot placement, and C++-style `ImportSpec`, `PackageSpec`, `File`, and `Package` `ToString` output.
- Aligned `CreateMemberAccess(expr, fieldName)` with the C++ class receiver lookup: generated member accesses now search superclass declarations until the first matching member is found, while preserving direct nominal lookup for structs, interfaces, and enums.
- Expanded AST `ScopeKind` and `ExprKind` from one-value macro compatibility placeholders to the full C++/Parse value sets, added equality helpers with reference-order indexes, and switched AST `MacroInvocation` defaults to `UNKNOWN_SCOPE` / `UNKNOWN_EXPR` while preserving the old `UNKNOWN` spelling as an equality-compatible downstream alias.
- Deepened `ASTTypeValidator` to follow the C++ pre/post visitor shape: pre-visit now records valid diagnostic ranges and check status, walks desugared expressions with the same walker ID and post visitor, and post-visit performs semantic type/target validation after children.
- Added `ValidateUsedNodes(DiagnosticEngine, Package)` parity that emits the real `sema_invalid_node_after_check` diagnostic with the C++ note text while preserving the existing boolean validation helper for current self-hosted callers.
- De-isolated `CacheEntry` diagnostics to the real `basic.DiagnosticCache` and aligned `CacheKey.diagKey` with the Basic diagnostic-cache key type used by `DiagnosticCache.ExtractKey`.
- Replaced the generic `PrintNode` walker dump with a C++-style recursive AST printer dispatcher: package/file, declaration, expression, type, pattern, macro, feature/import/package, annotation, and modifier nodes now print labeled sections and children in the reference order where the self-hosted node model has equivalent fields.
- Added `PrintNode` parity for desugared-expression forwarding, macro invocation attribute/argument token rendering, target/mangled-name printing, declaration modifier/annotation/generic sections, inherited-type/member sections, operator/overflow details, type-argument lists, and literal string recovery through the real `basic.StringConvertor`.
- Added C++ `Searcher` file-hash filtering parity: `Query` now carries file-hash filters, string searches can receive hash filters, normalized cache keys include file hashes and sort direction, cached/fresh results are filtered through `Symbol.hashID.hash64`, and `SetCache`/`GetCache` are exposed for warmup-cache parity.
- Aligned the AST-local `FileHashQuery` leaf to use the symbol file hash instead of mutable node file state, and normalized its pretty-printed key spelling.
- Deepened `Clone` visitor parity with C++: `SetIsClonedSourceCode` now unconditionally marks cloned targets, `CloneGeneric` accepts a visitor callback, and `ASTCloner.Clone` has a visitor overload that applies callbacks across the cloned tree for source-to-target clone hooks.
- Added C++ `Searcher` scope-level comparison parity for programmatic `scope_level < N` and `scope_level <= N` queries, with indexed lookup and linear fallback sharing the same `ScopeLevelQuery` semantics.
- Added later `Utils.cpp` interop-helper parity: Java mirror/impl/CJ-mapping/JObject/Object/forward-class predicates, CFunc constructor-call validation, Java ref-getter stub generation, Java synthetic wrapper class generation, and ObjC synthetic wrapper class generation using existing AST creation helpers.
- Reused real `cangjie_compiler::utils` constants and `GetRootPackageName` for Java/ObjC generated declarations instead of local string copies.
- Aligned `Walker` post-visit action handling with C++: `VisitPost` now overrides the current decision unless it returns `KEEP_DECISION`, preserves immediate `STOP_NOW`, and asserts that the final decision is not `KEEP_DECISION`.
- Deepened `Walker` traversal parity for desugared AST nodes: macro and main declarations now walk either `desugarDecl` or the original body, return/literal/optional-chain/synchronized nodes skip stale original children after desugaring, and try-handler blocks are skipped once the try expression has a desugared replacement.
- Aligned package traversal order with the C++ walker by visiting generic instantiated declarations before package files.
- Added C++ walker parity for macro expansion invocations by walking `MacroInvocation.decl` for macro expand expressions, declarations, and parameters while preserving the self-hosted macro pipeline's existing expansion-node traversal.
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
- Deepened `ASTCloner` toward C++ `CloneWithRearrange`: top-level clones now collect source/target preorder pairs and remap cloned-subtree semantic pointers for declaration outers/generics, expression source/map links, function-body ownership, pattern context expressions, reference targets/call owners, member accesses through `this`, array initializers, for-in desugar patterns, call resolutions, return/jump links, qualified/ref type targets, function owner/property links, and variable parent patterns.
- Aligned clone-time semantic-pointer copy behavior with the C++ reference for `sourceExpr`, `mapExpr`, pattern `ctxExpr`, jump loops, for-in desugar patterns, captured variables, function-body back references, and cloned member-call ownership instead of deep-cloning those backpointers eagerly.
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

- Wire downstream AST validation call sites to the `DiagnosticEngine` overload once the type-check pipeline enables the C++ post-check validation pass by default.
- Resolve `ScopeKind` and `ExprKind` layering with Parse once the self-hosted packages can share those APIs without introducing a package cycle. The C++ AST only forward-declares the related parse concepts, so AST currently carries a value-faithful mirror plus legacy `UNKNOWN` aliases until that dependency direction is settled.
- Finish exact C++ `Searcher` parity for diagnostic-producing query parse failures and broader downstream validation of indexed position searches once the collector/scope-manager pipeline fully populates indexes in the Cangjie port.
- Continue auditing macro diagnostic map lifetimes through Parse/Macro/Sema; AST now avoids clone-time `MacroCallDiagInfo` aliasing, but full private Basic map reconstruction is still owned by the macro pipeline.
- Continue auditing clone pointer rearrangement under ambiguous generated-node cases. The current Cangjie pass remaps unique structural source/target pairs and preserves external pointers; C++ still has stricter pointer-identity fidelity through `source2cloned`.
- Continue auditing context, walker, clone, printer, recover-desugar, search/query, type, utility, and validation behavior against the complete C++ implementation under downstream Parse/Sema workloads.
- Continue tightening `PrintNode` byte-for-byte formatting against C++ where C++ exposes raw pointer values or fields not represented in the current Cangjie AST model.
- Replace any remaining compatibility API spellings only after downstream packages no longer depend on them.
