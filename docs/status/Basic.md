# Basic Port Status

Date: 2026-06-16

Build: `cjpm build` passes.

Deepening pass updates:

- Separated `InteropCJPackageConfigReader.Parse` from semantic validation to match the C++ reader flow: parse now
  reports file/read/TOML-shape failures, while strategy consistency checks remain in the explicit `Validate()` step.
- Added the C++ `DiagnosticEngine::StashDisableDiagnoseStatus` behavior as a Cangjie `Resource`, including
  temporary re-enable/restore of disabled diagnostic state and replay of non-error stored diagnostics for the
  `hasTargetType` path. Exposed the missing `DisableDiagnose()`, no-argument `EnableDiagnose()`, and
  `AutoStashDisableDiagnoseStatus()` API surface on `DiagnosticEngine`.
- Tightened `InteropCJPackageConfigReader`'s TOML subset handling for escaped quotes in comments/string arrays,
  trimmed lambda signatures before parameter/return parsing, and changed generic type argument validation to fail on
  the first unsupported type with C++-style diagnostics instead of silently dropping the invalid segment.
- Matched the C++ `Utils::GetLineTerminator()` platform split by returning `"\r\n"` on Windows and `"\n"` elsewhere.
- Matched `MacroCallDiagInfo` lookup with the C++ descending `std::map<unsigned, Position, std::greater<...>>`
  behavior. `lower_bound` now selects the largest key not greater than the queried position, and the LSP exact-key
  path advances to the next lower key before falling back, matching the reference macro position remapping.
- Aligned `PackageConfig` defaults with the C++ public structure by starting package-local API and generic strategies
  as `UNKNOWN`, while preserving the C++ parser behavior that absent package strategy keys default to `None`.
  Explicit invalid strategy strings remain `UNKNOWN` and fail validation.
- Made `InteropCJPackageConfigReader.Parse` return `false` on file read failures instead of allowing the filesystem
  exception to escape, matching the C++ reader's caught parse/open failure path.
- Matched two byte-level utility behaviors from C++ Basic: `SplitString` advances one byte past a found delimiter, and
  `StringConvertor.Normalize` drops an unrecognized escape backslash while preserving the escaped byte for later
  processing.
- Matched the C++ compiler diagnostic handler's saved-category filter: `PARSE_QUERY` diagnostics are still handled and
  counted, but are not cached into the category buffers used for deferred emission.
- Aligned `GetDiagnosticInfo` with the C++ `Emit(true)` path when a `SourceManager` is present, returning only the
  rendered source/hint body in the `hint` field while keeping the diagnostic message in `msg`; the no-source-manager
  fallback keeps the full render path like the C++ implementation.
- Tightened diagnostic JSON formatting to match the C++ formatter's top-level severity schema (`error` vs `warning`)
  and source-backed empty-path position formatting.
- Propagated diagnostic emitter range-check failures back into `DiagEngineErrorCode.DIAG_RANGE_ERROR` from normal
  emission and `GetDiagnosticInfo`, matching the C++ `DiagnosticEmitter::Emit()` result handling.
- Added the C++ Basic `PrintCommandDesc` helper for option/help text alignment and matched `ErrorWithColor` emission
  order/reset behavior from `Print.cpp` without changing diagnostic emitter color formatting.
- Audited Basic path handling against the C++ `FileUtil` calls. The current selfhost package graph still leaves this
  behavior implemented by Basic-local helpers because importing `utils.FileUtil` from Basic would create a cycle.
  `IsInMacroCallSourceFile` follows the C++ size/source-id guard shape, but full path-helper de-isolation remains
  blocked on package graph work.

Implemented:

- Replaced the Basic scaffold with a multi-file Cangjie package mirroring the C++ Basic components.
- Added real implementations for positions, source buffers, line offsets, source slicing, string conversion, display width, printing/color helpers, version/linkage/type enums, macro-call diagnostic mapping, diagnostic metadata tables generated from the C++ `.def` files, diagnostic engine state, text/json diagnostic output, and interop package config parsing.
- Preserved the C++ diagnostic IDs/messages/severities/warning groups by generating tables from the reference `DiagnosticsAll.def`, `DiagRefactor/DiagnosticAll.def`, and `DiagnosticWarnGroupKind.def`.
- Kept a Basic-local `WarningOptionMgr` compatibility manager because the selfhost `option` package depends on Basic;
  the warning group indices are still generated from Basic's C++ `.def` data, but replacing the local manager with the
  real Option-owned warning state requires package graph work.
- Kept Basic-local source path normalization, extension checks, existence checks, and package display file-name helpers
  as compatibility logic pending a package-graph split that allows Basic to depend on FileUtil without a cycle.
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
- The same package-cycle issue blocks replacing Basic-local path helper logic with the real selfhost
  `cangjie_compiler::utils.FileUtil` package even though the C++ Basic source calls `FileUtil`.
- The same package-cycle issue currently blocks replacing Basic-local warning suppression state with the real
  selfhost `option.WarningOptionMgr`, even though the C++ Basic implementation owns a pointer to Option's manager.
- Basic still publishes its generated `WarnGroup` and `DiagFormat` enums for downstream Basic APIs. Warning suppression itself now uses the real Option manager by index, but fully replacing those public enum types with Option-owned types requires a coordinated API migration across users of `basic.*`.
- Diagnostic text output now covers C++-style source gutters, padded line numbers, source/no-source notes and helps, substitution previews, same-line grouped hints, multi-line ranges, long-range compression, macro-call headline/note swapping, control characters, and macro expansion excerpts, but it is not byte-for-byte identical to every overlapping-hint hanging/color branch in the C++ `DiagnosticEmitterImpl`.
- Interop package config parsing covers the table shapes consumed by the C++ reader (`default`, `package`, `generic_object_configuration`, `lambda_patterns`, `class_mappings`) without depending on an external TOML library.
- Windows-only GBK conversion is represented as optional ASCII-safe conversion plus encoding detection on this non-Windows selfhost target; non-ASCII GBK transcoding still needs a platform bridge if Windows self-hosting is enabled.

Remaining Basic selfhost markers: 0.
