# Basic Port Status

Date: 2026-06-16

Build: `cjpm build` passes.

Implemented:

- Replaced the Basic scaffold with a multi-file Cangjie package mirroring the C++ Basic components.
- Added real implementations for positions, source buffers, line offsets, source slicing, string conversion, display width, printing/color helpers, version/linkage/type enums, macro-call diagnostic mapping, diagnostic metadata tables generated from the C++ `.def` files, diagnostic engine state, text/json diagnostic output, and interop package config parsing.
- Preserved the C++ diagnostic IDs/messages/severities/warning groups by generating tables from the reference `DiagnosticsAll.def`, `DiagRefactor/DiagnosticAll.def`, and `DiagnosticWarnGroupKind.def`.
- De-isolated diagnostic warning suppression from a Basic-local manager to the real `cangjie_compiler::option.WarningOptionMgr`, keeping Basic warning group indices aligned with Option so `-Woff` state is shared with the diagnostics engine.
- Corrected refactor diagnostic category classification to mirror the C++ sentinel ranges, including lexer, import-package, module, parse-query, conditional-compilation, CHIR, parse, and sema ranges with exclusive end sentinels. Legacy `DiagKind` category mapping now follows the C++ Basic implementation for macro expansion and sema.
- Matched more C++ diagnostic emission behavior: buffered category diagnostics are sorted by begin/end range before emission, macro-origin notes are prepended ahead of existing subdiagnostics, range-error checking is deferred after existing lex/parse errors for later phases, and JSON-format reporting caches counts and emits the assembled JSON payload from `ReportErrorAndWarningCount`.
- Replaced the remaining Basic selfhost markers with working code:
  deterministic `DiagnosticBuilder.close()/Emit()` cleanup with `Resource` support for try-with-resource use, C++-schema diagnostic JSON formatting, multi-line/control-character-aware diagnostic text rendering, same-line hint composition, macro-call message/note swapping, compressed long source excerpts, C++-style help substitution source rendering, macro expansion excerpts, generic object and lambda pattern parsing for interop package configs, and UTF-8/GBK encoding detection with optional normalization.
- Corrected `MacroCallDiagInfo` and `DiagnosticEngineImpl` macro-position lookups to match the C++ `std::map::lower_bound` behavior, including the LSP exact-key successor case used when mapping macro-generated positions back to source positions.
- Tightened interop package config validation to mirror the C++ reader: per-package unknown strategies now fail validation, invalid include/exclude combinations are rejected, `GenericTypeStrategy = "None"` rejects generic instantiations, and invalid `generic_object_configuration` entries now fail parsing instead of being ignored.
- Kept LLVM/native backend out of scope as required; Basic does not bind LLVM directly.

Known fidelity caveats:

- C++ emits diagnostics from `DiagnosticBuilder::~DiagnosticBuilder`; this Cangjie port provides idempotent `Emit()` and `close()` plus `Resource` integration for deterministic cleanup, but automatic destruction-time emission is not available in the language surface used here.
- `SourceManager` still carries a small local comment-token adapter. The real `lex.Token` exists, but `lex` currently depends on `basic`, so importing it from Basic would introduce a package cycle; this should be revisited if the package graph is split to match the C++ header layering more directly.
- Basic still publishes its generated `WarnGroup` and `DiagFormat` enums for downstream Basic APIs. Warning suppression itself now uses the real Option manager by index, but fully replacing those public enum types with Option-owned types requires a coordinated API migration across users of `basic.*`.
- Diagnostic text output now covers C++-style source gutters, padded line numbers, source/no-source notes and helps, substitution previews, same-line grouped hints, multi-line ranges, long-range compression, macro-call headline/note swapping, control characters, and macro expansion excerpts, but it is not byte-for-byte identical to every overlapping-hint hanging/color branch in the C++ `DiagnosticEmitterImpl`.
- Interop package config parsing covers the table shapes consumed by the C++ reader (`default`, `package`, `generic_object_configuration`, `lambda_patterns`, `class_mappings`) without depending on an external TOML library.
- Windows-only GBK conversion is represented as optional ASCII-safe conversion plus encoding detection on this non-Windows selfhost target; non-ASCII GBK transcoding still needs a platform bridge if Windows self-hosting is enabled.

Remaining Basic selfhost markers: 0.
