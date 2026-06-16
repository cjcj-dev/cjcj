# Utils Port Status

Date: 2026-06-16

Build: `cjpm build` passes.

Implemented:

- Replaced the Utils scaffold with a multi-file Cangjie package mirroring the C++ Utils component layout.
- Added working ports for constants, check/assert helpers, pointer wrappers, partially persistent set helpers, SipHash, string/numeric helpers, C++ header-style hash/collection predicates, bounded native random hex generation, file/path helpers with C++-style canonicalized I/O and length checks, Unicode conversion/range helpers, generated NFC/width/XID tables with C++-style salted NFC lookups, floating point formatting, ICE helpers, semaphore/task queue/parallel dispatch/profile recorder utilities, user profiling output, POSIX/Windows signal registration, platform memory trimming/pressure relief, casting helpers, and standard-library metadata maps.
- Filled in interop constants from `ConstantsUtils.h`, corrected Cangjie cast facade recursion, preserved C++ task-queue exception storage behavior, and matched `StringRef.ToUTF32` invalid UTF-8 recovery.
- Preserved native/back-end boundaries by keeping LLVM and external native behavior behind Cangjie FFI or standard runtime APIs.
- Kept code changes within the Utils module and added only the required `utils -> lex` package dependency for real lexer token metadata.
- Deepened FileUtil platform fidelity: public path/injection constants now match the C++ Windows/POSIX split, normalization uses platform slash rules, empty-base `JoinPath` matches C++, environment path splitting is platform-specific, case-sensitive `FileExist` verifies the directory entry name, and package/serialization/LTO path helpers share the same separator handling.
- Matched `FileUtil::Access` and `AccessWithResult` to the C++ `access(2)`/`_access` model: file mode flags now use native `F_OK`/`X_OK`/`W_OK`/`R_OK` values, Unix failures distinguish `ENOENT`, `EACCES`, and unknown errors, and the file-scan `_test.cj` filter now follows the C++ suffix/substring rules.
- Deepened Semaphore startup behavior by deriving the singleton count from processor count on Linux/macOS via `sysconf`, preserving the C++ "leave two cores free, minimum one" policy.
- Aligned `Semaphore.SetCount` with the C++ implementation by updating the count under lock without broadcasting to waiters.
- Corrected Unicode identifier classification to match the lexer token tables: raw identifiers can wrap keywords, `_` and built-in type token names are rejected as identifiers, and contextual modifier keywords are allowed only when requested.
- De-isolated Unicode keyword and ICE version/color handling to real sibling packages: Utils now depends on `basic` for compiler version and ANSI ICE prefix constants, and on `lex` for `TOKENS`, `TokenKind.IDENTIFIER`, and contextual keyword classification instead of local compatibility copies.
- Matched the C++ identifier keyword set construction by deriving keywords from lexer `TOKENS[0..<TokenKind.IDENTIFIER]` plus boolean literals, so future lexer keyword changes are reflected without another Utils-local copy.
- Restored the C++ `UserTimer` unfinished-scope diagnostic when profile output is collected while a timer has a beginning time but no ending time, including the Windows/plain and non-Windows/red message split.
- Deepened `StdUtils` integer conversion fidelity: `Sto*` helpers now follow the C++ `std::sto*` family more closely for leading ASCII whitespace, optional signs, base-0 autodetection, hexadecimal prefixes, partial numeric consumption, and range failures.
- Restored the C++ signal utility split with `SignalUtil.cj`, and brought Unix alternate signal stack setup closer to `SignalUnix.cpp` by querying/preserving the old stack and reusing an existing active or sufficiently large alternate stack.

Known fidelity caveats:

- Utils exposes normal and signal-safe ICE temp-file cleanup hooks for the Driver port to register; the actual C++ `TempFileManager` deletion policy still belongs to Driver and is outside Utils' dependency boundary here.
- `ParallelUtil` provides real generic indexed parallel dispatch, but the exact C++ CHIRBuilder/Translator entrypoint still requires CHIR-facing Cangjie types.
- Non-Linux memory profiling still uses the conservative Cangjie fallback rather than the C++ Windows/macOS process-memory APIs.

Remaining Utils selfhost markers: 0.
