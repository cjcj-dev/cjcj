# ConditionalCompilation Port Status

Date: 2026-06-16

## Summary

ConditionalCompilation is a multi-file Cangjie port of the C++ pass. It
evaluates `@When` expressions, validates builtin and user-defined conditions,
handles debug/test unary/ref forms, supports backend/arch/os/env/cjc_version
comparisons, caches validated condition expressions, removes `@When`
annotations after evaluation, filters imports, declarations, enum
members/constructors, property accessors, function parameters, and block nodes,
and recomputes the file `hasMacro` flag after filtering.

## Current Integration

- This package imports the real sibling `ast`, `basic`, and `option` packages.
  AST now re-exports Basic/Lex primitives, so diagnostics use `basic.Position`
  directly with no local position conversion.
- Default diagnostics now use Basic's `DEFAULT_POSITION`, and LSP cfg.toml
  content errors are emitted without extra format arguments, matching the C++
  diagnostic definition.
- The package still exposes `ConditionalCompilationCompilerInstance` as a small
  provider interface for the real `option.GlobalOptions` and
  `basic.DiagnosticEngine`. The current `frontend.CompilerInstance` in this
  worktree owns separate frontend-local compatibility models, so importing it
  here would re-isolate this module from the real Basic/AST/Option packages.

## Build

`cjpm build` passes for the workspace with this package.

Remaining ConditionalCompilation selfhost markers: 0.
