# Basic Port Status

Date: 2026-06-15

Build: `cjpm build` passes.

Implemented:

- Replaced the Basic scaffold with a multi-file Cangjie package mirroring the C++ Basic components.
- Added real implementations for positions, source buffers, line offsets, source slicing, string conversion, display width, printing/color helpers, version/linkage/type enums, macro-call diagnostic mapping, diagnostic metadata tables generated from the C++ `.def` files, diagnostic engine state, text/json diagnostic output, warning suppression state, and interop package config data structures.
- Preserved the C++ diagnostic IDs/messages/severities/warning groups by generating tables from the reference `DiagnosticsAll.def`, `DiagRefactor/DiagnosticAll.def`, and `DiagnosticWarnGroupKind.def`.
- Kept LLVM/native backend out of scope as required; Basic does not bind LLVM directly.

Known remaining gaps:

- Diagnostic builder emission is explicit through `Emit()` because no deterministic Cangjie destructor equivalent was found for C++ RAII builder emission.
- Diagnostic text and JSON emitters are functional but not byte-for-byte identical to the C++ formatting paths.
- Interop package config parsing handles the common default/package scalar and string-array keys, but not full tinytoml nested table semantics.
- Windows-only string encoding conversion helpers are not implemented on this Linux selfhost pass.

Remaining Basic selfhost markers: 5.
