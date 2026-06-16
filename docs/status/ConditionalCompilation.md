# ConditionalCompilation Port Status

Date: 2026-06-17

## Summary

ConditionalCompilation is a multi-file Cangjie port of the C++ pass. It
evaluates `@When` expressions, validates builtin and user-defined conditions,
handles debug/test unary/ref forms, supports backend/arch/os/env/cjc_version
comparisons, caches validated condition expressions, removes `@When`
annotations after evaluation, filters imports, declarations, enum
members/constructors, property accessors, function parameters, and block nodes,
and recomputes the file `hasMacro` flag after filtering. The target-condition,
supported-operator, and supported-value data now live in
`ConditionalCompilationTables.cj`, mirroring the C++ pass's explicit
`TARGET_CONDITION`, `CONDITION_OP`, and `CONDITION_VALUES` tables instead of
encoding them as scattered branch logic.

## Current Integration

- This package imports the real sibling `ast`, `basic`, `option`, and `utils`
  packages. AST now re-exports Basic/Lex primitives, so diagnostics use
  `basic.Position` directly with no local position conversion.
- Validation of condition names, supported operators, and supported builtin
  values is table-driven from the module's C++-owned condition metadata while
  preserving user-defined-condition behavior.
- Default diagnostics now use Basic's `DEFAULT_POSITION`, and LSP cfg.toml
  loading now mirrors the C++ constructor path: file read failures, malformed
  TOML entries, invalid identifiers, built-in keys, and duplicate keys emit the
  corresponding Basic diagnostics while preserving Option's identifier and NFC
  normalization behavior.
- The package still exposes `ConditionalCompilationCompilerInstance` as a small
  provider interface for the real `option.GlobalOptions` and
  `basic.DiagnosticEngine`. The current `frontend.CompilerInstance` in this
  worktree owns separate frontend-local compatibility models, so importing it
  here would re-isolate this module from the real Basic/AST/Option packages.

## Build

`cjpm build` passes for the workspace with this package.

Remaining ConditionalCompilation selfhost markers: 0.
