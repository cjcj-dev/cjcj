# AST Port Status

Date: 2026-06-15

## Summary

The AST package has been expanded from the placeholder scaffold into a multi-file Cangjie package that mirrors the C++ AST component layout. It now defines the AST kind and type-kind enums, attributes, identifiers, comments, symbols, type hierarchy, node hierarchy, declarations, expressions, patterns, macro nodes, import/package nodes, walkers, search/query helpers, cache structures, context state, cloning helpers, creation helpers, printing helpers, casting predicates, recovery utilities, validation helpers, and AST utility functions.

`cjpm build` passes for the workspace with this package, and the AST package currently has zero AST self-host marker comments.

## Important Blocker

The current AST package cannot import `cangjie_compiler::basic` without editing package metadata. A probe import failed with:

`root package 'cangjie_compiler::ast' imports package 'cangjie_compiler::basic' in its source code, but it is not added as a dependency in cjpm.toml`

The task explicitly disallows editing `cjpm.toml`, so AST currently carries local compatibility definitions for `Position`, `Range`, `TokenKind`, `Token`, `Linkage`, and macro diagnostic position mapping. Those must be replaced by the real Basic/Lex APIs when manifest changes are allowed.

## Implemented In This Pass

- Replaced `ASTScaffold.cj` with per-component AST source files under `packages/ast/src`.
- Ported the main public node/type surfaces from `Node.h`, `Types.h`, `AttributePack.h`, `Identifier.h`, `Comment.h`, `Symbol.h`, `IntLiteral.h`, and the import/package node portions.
- Added compiling implementations for context, cache, create, print, scope, casting, reference, and desugar helper components.
- Implemented AST child traversal across the ported node hierarchy, including package/import nodes, declarations, patterns, type nodes, expression nodes, literals, references, macro nodes, and file/package trees.
- Implemented cloning across the ported node hierarchy, including source ranges, comments, attributes, macro invocations, owned child nodes, pattern/type/expr/declaration fields, and reference preservation for resolved back-links.
- Implemented query parsing and search helpers for names, scopes, AST kinds, scope levels, file hashes, position predicates, wildcard matching, boolean operators, parser caching, and deterministic position ordering.
- Implemented literal constant initialization for boolean, integer, rune, string, unit, and floating-point literal nodes, plus AST type validation over semantic types, target types, and owner declarations.
- Expanded AST utility parity with C++ `Utils.cpp`: size-property lookup, Java attribute probing, outer function ownership propagation, declaration-attribute ancestry checks, pattern flattening, top-level/exportable declaration iteration, package member access detection, `this`/`super` detection, access-level mapping and formatting, import item name reconstruction, condition detection, enum-subpattern checks, source-export predicates, virtual-member checks, generic instance-member variable checks, member-variable export checks, variable initialization ordering, and mirror property signature synthesis.
- Extended the AST-local Basic/Lex compatibility layer with `Linkage` equality plus the `mut`, pipeline, composition, assignment, comparison, and unary-not tokens needed by mirror-property conversion, desugar recovery, and factory construction.
- Expanded `Symbol` and `ASTContext` parity with C++ symbol hash IDs, scope level/kind/target data, context reset behavior, desugared type-check cache keys, declaration removal by declaration identity, outer variable-with-pattern ownership, macro-origin filtering for enum constructors, enum constructor lookup by name and arity, and member-signature subtype expansion.
- Expanded scope/search parity with C++ scope-name tail, parent, child, and gate helpers; C++ top-level scope encoding; trie reset/delete/suffix matching; position string formatting; and position range symbol collection APIs.
- Expanded type-system parity with C++ `Types.cpp`: generic lower-bound subtype predicates, type-alias extendability through aliased types, core-package nominal checks for `Option`, `Array`, `Object`, `Any`, `CType`, `String`, and `Range`, union/intersection-aware recursive type queries, nominal generic type lookup, inherited interface lookup on nominal types, structural type hashing, and type-cache keys based on structural hashes.
- Expanded print-node parity with a walker-backed recursive AST dump that emits node kind and display name, source summaries, positions, file/scope/type/attribute/package metadata, symbol and target links, declaration linkage/const/export details, comments, indentation, and optional root labels.
- Expanded recover-desugar parity with C++-shaped recovery for unary, binary, subscript, assignment, call, array-constructor, pointer-constructor, and variadic-call desugar forms, plus clear-path recovery hooks for overloaded expression nodes.
- Expanded `Create` parity with C++ factory helpers for scope/file copying, unit/bool literals, overloadable expressions, calls, function arguments, parameters, bodies, declarations, blocks, if/match expressions, reference expressions/types, member access, tuple access, variable patterns/declarations, import specs, and throw/perform/resume/type-pattern helpers.
- Preserved build compatibility without touching runtime, stdx, tools, manifests, or the C++ reference repository.

## Remaining Work

- Replace AST-local Basic/Lex compatibility types with real dependencies.
- Wire AST validation to the real `DiagnosticEngine`.
- Audit the ported context, walker, clone, printer, recover-desugar, search/query, literal, type, utility, and validation behavior against the complete C++ implementation once downstream packages can exercise the same API surface.
- Align all helper APIs exactly with downstream Parse/Sema/Modules expectations once those packages are ported and the real Basic/Lex packages are available as dependencies.
