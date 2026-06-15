# Utils Port Status

Date: 2026-06-15

Build: `cjpm build` passes.

Implemented:

- Replaced the Utils scaffold with a multi-file Cangjie package mirroring the C++ Utils component layout.
- Added working ports for constants, check/assert helpers, pointer wrappers, partially persistent stack/vector/map helpers, SipHash, string/numeric helpers, file/path helpers, Unicode conversion/range helpers, generated NFC/width/XID tables, floating point formatting, ICE helpers, semaphore/task queue/profile recorder utilities, user profiling output, POSIX/Windows signal registration, platform memory trimming/pressure relief, casting helpers, and standard-library metadata maps.
- Preserved native/back-end boundaries by keeping LLVM and external native behavior behind Cangjie FFI or standard runtime APIs.
- Kept the package self-contained within `packages/utils` and avoided manifest or cross-module package edits.

Known fidelity caveats:

- Generated Unicode NFC and width data are now ported from the C++ `.inc` files, but the lookup implementation uses simple linear scans for some normalization tables instead of the C++ perfect-hash helpers.
- Signal cleanup calls `ICE.RemoveTempFile()`, but the C++ `TempFileManager` behavior belongs to Driver and is still outside Utils' dependency boundary here.
- `ParallelUtil` provides a real bounded task runner, but cannot expose the C++ CHIRBuilder/Translator entrypoint until Utils is allowed to depend on CHIR-facing Cangjie types.

Remaining Utils selfhost markers: 0.
