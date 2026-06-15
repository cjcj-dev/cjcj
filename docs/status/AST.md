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
- Preserved build compatibility without touching runtime, stdx, tools, manifests, or the C++ reference repository.

## Remaining Work

- Replace AST-local Basic/Lex compatibility types with real dependencies.
- Wire AST validation to the real `DiagnosticEngine`.
- Audit the ported walker, clone, search/query, literal, and validation behavior against the complete C++ implementation once downstream packages can exercise the same API surface.
- Align all helper APIs exactly with downstream Parse/Sema/Modules expectations once those packages are ported and the real Basic/Lex packages are available as dependencies.
