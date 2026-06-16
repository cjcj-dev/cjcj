# Utils Port Status

Date: 2026-06-16

Build: `cjpm build` passes.

Implemented:

- Replaced the Utils scaffold with a multi-file Cangjie package mirroring the C++ Utils component layout.
- Added working ports for constants, check/assert helpers, pointer wrappers, partially persistent set helpers, SipHash, string/numeric helpers, C++ header-style hash/collection predicates, bounded native random hex generation, file/path helpers with C++-style canonicalized I/O and length checks, Unicode conversion/range helpers, generated NFC/width/XID tables with C++-style salted NFC lookups, floating point formatting, ICE helpers, semaphore/task queue/parallel dispatch/profile recorder utilities, user profiling output, POSIX/Windows signal registration, platform memory trimming/pressure relief, casting helpers, and standard-library metadata maps.
- Filled in interop constants from `ConstantsUtils.h`, corrected Cangjie cast facade recursion, preserved C++ task-queue exception storage behavior, and matched `StringRef.ToUTF32` invalid UTF-8 recovery.
- Preserved native/back-end boundaries by keeping LLVM and external native behavior behind Cangjie FFI or standard runtime APIs.
- Kept the package self-contained within `packages/utils` and avoided manifest or cross-module package edits.
- Deepened FileUtil platform fidelity: public path/injection constants now match the C++ Windows/POSIX split, normalization uses platform slash rules, empty-base `JoinPath` matches C++, environment path splitting is platform-specific, case-sensitive `FileExist` verifies the directory entry name, and package/serialization/LTO path helpers share the same separator handling.
- Deepened Semaphore startup behavior by deriving the singleton count from processor count on Linux/macOS via `sysconf`, preserving the C++ "leave two cores free, minimum one" policy.
- Corrected Unicode identifier classification to match the lexer token tables: raw identifiers can wrap keywords, `_` and built-in type token names are rejected as identifiers, and contextual modifier keywords are allowed only when requested.

Known fidelity caveats:

- Utils exposes normal and signal-safe ICE temp-file cleanup hooks for the Driver port to register; the actual C++ `TempFileManager` deletion policy still belongs to Driver and is outside Utils' dependency boundary here.
- `ParallelUtil` provides real generic indexed parallel dispatch, but the exact C++ CHIRBuilder/Translator entrypoint still requires CHIR-facing Cangjie types.
- The package remains intentionally dependency-light; duplicated Basic namespace string helpers are retained here because adding a `utils -> basic` package edge would be a manifest-level graph change outside this pass.
- Non-Linux memory profiling still uses the conservative Cangjie fallback rather than the C++ Windows/macOS process-memory APIs.

Remaining Utils selfhost markers: 0.
