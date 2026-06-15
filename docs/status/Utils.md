# Utils Port Status

Date: 2026-06-15

Build: `cjpm build` passes.

Implemented:

- Replaced the Utils scaffold with a multi-file Cangjie package mirroring the C++ Utils component layout.
- Added working ports for constants, check/assert helpers, pointer wrappers, partially persistent stack/vector/map helpers, SipHash, string/numeric helpers, file/path helpers, Unicode conversion/range helpers, generated NFC/width/XID tables with C++-style salted NFC lookups, floating point formatting, ICE helpers, semaphore/task queue/parallel dispatch/profile recorder utilities, user profiling output, POSIX/Windows signal registration, platform memory trimming/pressure relief, casting helpers, and standard-library metadata maps.
- Preserved native/back-end boundaries by keeping LLVM and external native behavior behind Cangjie FFI or standard runtime APIs.
- Kept the package self-contained within `packages/utils` and avoided manifest or cross-module package edits.

Known fidelity caveats:

- Signal cleanup calls `ICE.RemoveTempFile()`, but the C++ `TempFileManager` behavior belongs to Driver and is still outside Utils' dependency boundary here.
- `ParallelUtil` provides real generic indexed parallel dispatch, but the exact C++ CHIRBuilder/Translator entrypoint still requires CHIR-facing Cangjie types.

Remaining Utils selfhost markers: 0.
