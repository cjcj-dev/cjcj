# Basic Port Status

Date: 2026-06-15

Build: `cjpm build` passes.

Implemented:

- Replaced the Basic scaffold with a multi-file Cangjie package mirroring the C++ Basic components.
- Added real implementations for positions, source buffers, line offsets, source slicing, string conversion, display width, printing/color helpers, version/linkage/type enums, macro-call diagnostic mapping, diagnostic metadata tables generated from the C++ `.def` files, diagnostic engine state, text/json diagnostic output, warning suppression state, and interop package config parsing.
- Preserved the C++ diagnostic IDs/messages/severities/warning groups by generating tables from the reference `DiagnosticsAll.def`, `DiagRefactor/DiagnosticAll.def`, and `DiagnosticWarnGroupKind.def`.
- Replaced the remaining Basic selfhost markers with working code:
  deterministic `DiagnosticBuilder.close()/Emit()` cleanup with `Resource` support for try-with-resource use, C++-schema diagnostic JSON formatting, multi-line/control-character-aware diagnostic text rendering, macro-call message/note swapping, compressed long source excerpts, macro expansion excerpts, generic object and lambda pattern parsing for interop package configs, and UTF-8/GBK encoding detection with optional normalization.
- Kept LLVM/native backend out of scope as required; Basic does not bind LLVM directly.

Known fidelity caveats:

- C++ emits diagnostics from `DiagnosticBuilder::~DiagnosticBuilder`; this Cangjie port provides idempotent `Emit()` and `close()` plus `Resource` integration for deterministic cleanup, but automatic destruction-time emission is not available in the language surface used here.
- Diagnostic text output now covers C++-style source gutters, padded line numbers, source/no-source notes and helps, multi-line ranges, long-range compression, macro-call headline/note swapping, control characters, and macro expansion excerpts, but it is not byte-for-byte identical to every overlapping-hint hanging/color branch in the C++ `DiagnosticEmitterImpl`.
- Interop package config parsing covers the table shapes consumed by the C++ reader (`default`, `package`, `generic_object_configuration`, `lambda_patterns`, `class_mappings`) without depending on an external TOML library.
- Windows-only GBK conversion is represented as optional ASCII-safe conversion plus encoding detection on this non-Windows selfhost target; non-ASCII GBK transcoding still needs a platform bridge if Windows self-hosting is enabled.

Remaining Basic selfhost markers: 0.
