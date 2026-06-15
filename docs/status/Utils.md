# Utils Port Status

Date: 2026-06-15

Build: `cjpm build` passes.

Implemented:

- Replaced the Utils scaffold with a multi-file Cangjie package mirroring the C++ Utils component layout.
- Added working ports for constants, check/assert helpers, pointer wrappers, partially persistent set helpers, SipHash, string/numeric helpers, C++ header-style hash/collection predicates, bounded native random hex generation, file/path helpers with C++-style canonicalized I/O and length checks, Unicode conversion/range helpers, generated NFC/width/XID tables with C++-style salted NFC lookups, floating point formatting, ICE helpers, semaphore/task queue/parallel dispatch/profile recorder utilities, user profiling output, POSIX/Windows signal registration, platform memory trimming/pressure relief, casting helpers, and standard-library metadata maps.
- Filled in interop constants from `ConstantsUtils.h`, corrected Cangjie cast facade recursion, preserved C++ task-queue exception storage behavior, and matched `StringRef.ToUTF32` invalid UTF-8 recovery.
- Preserved native/back-end boundaries by keeping LLVM and external native behavior behind Cangjie FFI or standard runtime APIs.
- Kept the package self-contained within `packages/utils` and avoided manifest or cross-module package edits.

Known fidelity caveats:

- Utils exposes normal and signal-safe ICE temp-file cleanup hooks for the Driver port to register; the actual C++ `TempFileManager` deletion policy still belongs to Driver and is outside Utils' dependency boundary here.
- `ParallelUtil` provides real generic indexed parallel dispatch, but the exact C++ CHIRBuilder/Translator entrypoint still requires CHIR-facing Cangjie types.

Remaining Utils selfhost markers: 0.
