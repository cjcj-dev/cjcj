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

## Current Integration Limits

- `Frontend.CompilerInstance` is not ported in this worktree. The public class
  therefore exposes an option/config based constructor that carries the same
  state the C++ implementation reads from `CompilerInstance`. The implementation
  has one `TODO(selfhost:ConditionalCompilation)` marker for replacing that
  bridge once Frontend is real.
- AST currently uses compatibility copies of Basic/Lex primitives, so this
  package converts AST positions to Basic positions before reporting diagnostics.

## Build

`cjpm build` passes for the workspace with this package.

Remaining ConditionalCompilation selfhost markers: 1.
