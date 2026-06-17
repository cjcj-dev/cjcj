# ConditionalCompilation Port Status

Date: 2026-06-18

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
  values is table-driven from the module's C++-owned condition metadata.
  Undefined non-builtin conditions now match the reference pass: they are
  treated as absent and evaluate false without emitting
  `conditional_compilation_not_support_this_condition`.
- Operator-class detection now enumerates the exact C++-accepted conditional
  operators (`&&`/`||`, `==`/`!=`, and `<`/`>`/`<=`/`>=`) instead of relying on
  lexer enum ordinal ranges. This preserves the reference behavior while
  avoiding accidental acceptance if the token table is reordered or extended.
- Judge-condition and expression cache keys now share the same explicit enum
  field helper, matching the reference helper split between enum fields and
  string fields while retaining length-prefixed string fields to avoid
  collisions in Cangjie strings.
- Default diagnostics now use Basic's `DEFAULT_POSITION`, and LSP cfg.toml
  loading now mirrors the C++ constructor path: file read failures, malformed
  TOML entries, invalid identifiers, built-in keys, and duplicate keys emit the
  corresponding Basic diagnostics. The local LSP reader now uses Basic's real
  `SplitLines`/`SplitString` helpers, matching the C++ `Basic/Utils` call path,
  and Utils' real `FileUtil.JoinPath`/`FileUtil.FileExist`, matching the C++
  FileUtil owner for cfg file discovery, while preserving Option's identifier
  and NFC normalization behavior. The cfg-file builtin-key set intentionally
  follows Option's parser (`os`,
  `backend`, `arch`, `debug`, `cjc_version`, `test`); `env` remains a target
  condition for expression evaluation but is not rejected by cfg.toml parsing,
  matching the C++ split.
- Malformed `@When` annotations without a condition emit the reference
  diagnostic and remove only the annotation; the annotated node is left in place
  as in `ConditionalCompilationImpl::EvalNodeCondition`.
- Removed the unused `DefaultTargetTriple` shim from this module; target triples
  are owned by the real Option package just as in the C++ compiler.
- Removed the package-local `ConditionalCompilationCompilerInstance`
  compatibility interface. Until `frontend.CompilerInstance` is moved onto the
  real AST/Basic/Option model, this package is configured through
  `ConditionalCompilationConfig` or real `option.GlobalOptions` plus
  `basic.DiagnosticEngine` instead of owning a fake CompilerInstance shape.

## Build

`cjpm build` passes for the workspace with this package.

Remaining ConditionalCompilation selfhost markers: 0.
