# ConditionalCompilation Port Status

Date: 2026-06-15

## Summary

Replaced the placeholder with a multi-file Cangjie implementation of the C++
ConditionalCompilation pass. The port evaluates `@When` expressions, validates
builtin and user-defined conditions, handles debug/test unary/ref forms,
supports backend/arch/os/env/cjc_version comparisons, caches validated condition
expressions, removes `@When` annotations after evaluation, filters imports,
declarations, enum members/constructors, property accessors, function
parameters, and block nodes, and recomputes the file `hasMacro` flag after
filtering.

## Current Integration

- `Frontend.CompilerInstance` is not ported in this worktree. The module exposes
  `ConditionalCompilationCompilerInstance`, a small provider interface for the
  `GlobalOptions` and `DiagnosticEngine` state the C++ implementation reads from
  `CompilerInstance`, plus option/config constructors used by current packages.
- AST currently uses compatibility copies of Basic/Lex primitives, so this
  package converts AST positions to Basic positions before reporting diagnostics.

## Build

`cjpm build` passes for the workspace with this package.

Remaining ConditionalCompilation selfhost markers: 0.
