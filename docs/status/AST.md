# AST Port Status

Date: 2026-06-15

## Summary

The AST package has been expanded from the placeholder scaffold into a multi-file Cangjie package that mirrors the C++ AST component layout. It now defines the AST kind and type-kind enums, attributes, identifiers, comments, symbols, type hierarchy, node hierarchy, declarations, expressions, patterns, macro nodes, import/package nodes, walkers, search/query helpers, cache structures, context state, cloning helpers, creation helpers, printing helpers, casting predicates, recovery utilities, and AST utility functions.

`cjpm build` passes for the workspace with this package.

## Important Blocker

The current AST package cannot import `cangjie_compiler::basic` without editing package metadata. A probe import failed with:

`root package 'cangjie_compiler::ast' imports package 'cangjie_compiler::basic' in its source code, but it is not added as a dependency in cjpm.toml`

The task explicitly disallows editing `cjpm.toml`, so AST currently carries local compatibility definitions for `Position`, `Range`, `TokenKind`, `Token`, `Linkage`, and macro diagnostic position mapping. Those must be replaced by the real Basic/Lex APIs when manifest changes are allowed.

## Implemented In This Pass

- Replaced `ASTScaffold.cj` with per-component AST source files under `packages/ast/src`.
- Ported the main public node/type surfaces from `Node.h`, `Types.h`, `AttributePack.h`, `Identifier.h`, `Comment.h`, `Symbol.h`, `IntLiteral.h`, and the import/package node portions.
- Added compiling implementations for context, cache, walker, search/query, clone, create, print, validation, scope, casting, reference, and desugar helper components.
- Preserved build compatibility without touching runtime, stdx, tools, manifests, or the C++ reference repository.

## Remaining Work

- Replace AST-local Basic/Lex compatibility types with real dependencies.
- Complete exhaustive `Walker.cpp` child traversal for every node field.
- Complete deep clone coverage for every AST node kind.
- Port the full Lucene-like query parser and search semantics.
- Wire AST validation to the real `DiagnosticEngine`.
- Align all helper APIs exactly with downstream Parse/Sema/Modules expectations once those packages are ported.
