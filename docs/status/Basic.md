# Basic Port Status

Date: 2026-06-17

Build: `cjpm build` passes.

Deepening pass updates:

- Replaced the Basic-local placeholder polynomial `Utils::GetHash` with the C++ reference's platform string-hash
  behavior for this selfhost target: the non-Windows path now implements libstdc++ `_Hash_bytes`/`std::hash<string>`
  mixing, with a Windows FNV path matching MSVC-style string hashing. This makes source file hashes and CJMP hash IDs
  align with the C++ `Utils::GetHash` contract instead of using a port-only hash.
- Added explicit mutating `Position.AddAssign` and `Position.SubAssign` methods for the C++ `operator+=` and
  `operator-=` behavior. Cangjie cannot return `this` from a mutable struct method, so the methods mutate in place and
  return `Unit` while preserving the C++ field-update semantics.
- Aligned diagnostic text rendering for missing backing source files with the C++ emitter: location lines are skipped
  when `SourceManager::IsSourceFileExist` is false, and source excerpts omit numbered prefixes in that case while
  keeping the gutter/source body.
- Matched two C++ edge cases in core Basic value handling: `Position - Position` now returns a default
  non-current-file result like the C++ constructor path, and Unicode escape normalization consumes the first
  non-hex delimiter after `\u{...` exactly as the C++ iterator loop does.
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
- Extended `InteropCJPackageConfigReader` beyond inline-array TOML to cover the C++ parser's nested package
  array-of-table forms for `generic_object_configuration` and `lambda_patterns`, including nested
  `class_mappings` tables. Inline and nested generic configuration entries are now accumulated and validated through
  the same two-pass type-argument/symbol processing as the C++ implementation, and package entries without a required
  `name` now fail parsing instead of being silently ignored.
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
- Matched the C++ `DisplayWidth(std::string)` malformed UTF-8 behavior by validating the input byte sequence before
  display-width decoding and returning the raw byte length for invalid, overlong, surrogate, truncated, or out-of-range
  UTF-8 sequences.
- Tightened refactor diagnostic `%s` substitution to match the C++ `Diagnostic::InsertArguments` invariant: missing
  replacement arguments and unused extra arguments now fail instead of silently leaving placeholders or dropping inputs.
- Matched `DiagnosticEngineImpl::CheckRange`'s C++ fatal/internal-error split: zero ranges now raise in normal mode,
  and only degrade to `DIAG_RANGE_ERROR` when `EnableCheckRangeErrorCodeRatherICE()` is active.
- Tightened the Basic-local `WarningOptionMgr` compatibility shim to match the C++ warning manager's vector
  replacement API and invalid-index assertions while retaining the selfhost bulk boolean helper used by `option`.
- Matched the C++ CJMP source-file ID path in `SourceManager`: the stored `fileHash` remains the full
  `Utils::GetHash()` value, while CJMP file IDs now use the low 32 bits just like the reference
  `static_cast<unsigned int>(hashValue)` path.
- Matched C++ diagnostic argument integer narrowing for `int64_t` and `size_t` inputs by storing the same
  two's-complement 32-bit value that the reference `std::variant<int, ...>` receives before `%d` formatting.
- Matched the C++ `Utils::SplitString` empty-delimiter edge case: non-empty strings now produce the same
  `std::string::find("")` zero-length split slots while empty input still returns no splits.
- Restored the C++ diagnostic formatter's mismatch side effects: unsupported `%` directives and wrong argument kinds
  now emit `Errorln` diagnostics while leaving the original placeholder in the formatted message, and `%c` has a real
  byte-character `DiagArgument` constructor.

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
- Aligned `DisplayWidth(String)` with the C++ `std::range_error` fallback path for malformed UTF-8 so diagnostics keep
  byte-count spacing instead of decoding permissive replacement code points.
- Matched the C++ refactor diagnostic formatter's placeholder-count checks for `Diagnostic.InsertArguments`.
- Matched C++ range-check handling for zero-position diagnostics, preserving the special error-code mode used by
  libast callers while restoring fatal behavior in the normal diagnostic path.
- Extended the Basic-local warning suppression manager with the C++ whole-vector `UpdateFlags` shape and C++-style
  range checks for single-flag updates/lookups.
- Preserved C++ hash-width behavior for CJMP file IDs without changing the full source-file hash stored on each
  `Source`.
- Matched C++ `DiagArgument` integer storage for wide signed and unsigned inputs, including wraparound values that
  differ from their original 64-bit representation.
- Aligned `SplitString` and legacy diagnostic format-argument handling with the C++ edge cases for empty delimiters,
  `%c` character arguments, bad argument kinds, and illegal format characters.
- Kept LLVM/native backend out of scope as required; Basic does not bind LLVM directly.

Known fidelity caveats:

- C++ emits diagnostics from `DiagnosticBuilder::~DiagnosticBuilder`; this Cangjie port provides idempotent `Emit()` and `close()` plus `Resource` integration for deterministic cleanup, but automatic destruction-time emission is not available in the language surface used here.
- `SourceManager` still carries a small local comment-token adapter. The real `lex.Token` exists, but `lex` currently depends on `basic`, so importing it from Basic would introduce a package cycle; this should be revisited if the package graph is split to match the C++ header layering more directly.
- The same package-cycle issue blocks replacing Basic-local path helper logic with the real selfhost
  `cangjie_compiler::utils.FileUtil` package even though the C++ Basic source calls `FileUtil`.
- The same package-cycle issue currently blocks replacing Basic-local warning suppression state with the real
  selfhost `option.WarningOptionMgr`, even though the C++ Basic implementation owns a pointer to Option's manager.
- Basic still publishes its generated `WarnGroup` and `DiagFormat` enums for downstream Basic APIs. Warning
  suppression is still stored in the Basic-local compatibility manager, with `option.WarningOptionMgr` forwarding
  updates by generated warning-group index; fully replacing those public enum/storage types with Option-owned types
  requires a coordinated package-graph and API migration across users of `basic.*`.
- Diagnostic text output now covers C++-style source gutters, padded line numbers, source/no-source notes and helps, substitution previews, same-line grouped hints, multi-line ranges, long-range compression, macro-call headline/note swapping, control characters, and macro expansion excerpts, but it is not byte-for-byte identical to every overlapping-hint hanging/color branch in the C++ `DiagnosticEmitterImpl`.
- Interop package config parsing covers the table shapes consumed by the C++ reader (`default`, `package`,
  inline and nested `generic_object_configuration`, inline and nested `lambda_patterns`, and nested/inline
  `class_mappings`) without depending on an external TOML library.
- Windows-only GBK conversion is represented as optional ASCII-safe conversion plus encoding detection on this non-Windows selfhost target; non-ASCII GBK transcoding still needs a platform bridge if Windows self-hosting is enabled.

Remaining Basic selfhost markers: 0.
