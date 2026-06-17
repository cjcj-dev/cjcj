# Utils Port Status

Date: 2026-06-17

Build: `cjpm build` passes.

Implemented:

- Replaced the Utils scaffold with a multi-file Cangjie package mirroring the C++ Utils component layout.
- Added working ports for constants, check/assert helpers, pointer wrappers, partially persistent set helpers, SipHash, string/numeric helpers, C++ header-style hash/collection predicates, bounded native random hex generation, file/path helpers with C++-style canonicalized I/O and length checks, Unicode conversion/range helpers, generated NFC/width/XID tables with C++-style salted NFC lookups, floating point formatting, ICE helpers, semaphore/task queue/parallel dispatch/profile recorder utilities, user profiling output, POSIX/Windows signal registration, platform memory trimming/pressure relief, casting helpers, and standard-library metadata maps.
- Filled in interop constants from `ConstantsUtils.h`, corrected Cangjie cast facade recursion, preserved C++ task-queue exception storage behavior, and matched `StringRef.ToUTF32` invalid UTF-8 recovery.
- Preserved native/back-end boundaries by keeping LLVM and external native behavior behind Cangjie FFI or standard runtime APIs.
- Kept code changes within the Utils module and reused the existing `utils -> basic` dependency for shared Basic utilities.
- Deepened FileUtil platform fidelity: public path/injection constants now match the C++ Windows/POSIX split, normalization uses platform slash rules, empty-base `JoinPath` matches C++, environment path splitting is platform-specific, case-sensitive `FileExist` verifies the directory entry name, and package/serialization/LTO path helpers share the same separator handling.
- Matched `FileUtil::Access` and `AccessWithResult` to the C++ `access(2)`/`_access` model: file mode flags now use native `F_OK`/`X_OK`/`W_OK`/`R_OK` values, Unix failures distinguish `ENOENT`, `EACCES`, and unknown errors, and the file-scan `_test.cj` filter now follows the C++ suffix/substring rules.
- Tightened `FileUtil.RemoveDirectoryRecursively` to match the C++ entrypoint: regular files are rejected, symbolic links are removed without descending, and recursive deletion is reserved for real directories.
- Matched the C++ `ReadBinaryFileToBuffer` output-buffer contract more closely by preserving the caller's existing buffer on early read failures and only replacing it after a successful read.
- Added the Windows-only `FileUtil.HideFile` API with Win32 `GetFileAttributesA`/`SetFileAttributesA` FFI, mirroring the C++ header surface and hidden-attribute behavior.
- Matched the POSIX `FileUtil.GetAllDirsUnderCurrentPath` traversal more closely by enumerating only real directories and returning the directories collected so far when an intermediate directory cannot be opened, instead of reusing `GetDirectories` and following symbolic links.
- Deepened Semaphore startup behavior by deriving the singleton count from processor count on Linux/macOS via `sysconf`, preserving the C++ "leave two cores free, minimum one" policy.
- Aligned `Semaphore.SetCount` with the C++ implementation by updating the count under lock without broadcasting to waiters.
- Corrected Unicode identifier classification to match the lexer token tables: raw identifiers can wrap keywords, `_` and built-in type token names are rejected as identifiers, and contextual modifier keywords are allowed only when requested.
- De-isolated ICE version/color handling to real Basic constants instead of Utils-local compatibility copies.
- De-isolated the Utils string split/qualified-name/join wrappers to the real Basic helpers, removing the local duplicate implementation and matching the C++ `Basic/Utils.cpp` behavior used by Utils clients.
- Added the C++ UTF-32 raw-byte conversion path in Unicode utilities, including multiple-of-four validation, native/scalar BOM skipping, and swapped-BOM byte-order correction before strict UTF-8 emission.
- Restored the C++ `UserTimer` unfinished-scope diagnostic when profile output is collected while a timer has a beginning time but no ending time, including the Windows/plain and non-Windows/red message split.
- Aligned `ProfileRecorder` resource cleanup with the C++ destructor by swallowing `Stop` exceptions during close so profiling cleanup cannot leak exceptions.
- Deepened `StdUtils` integer conversion fidelity: `Sto*` helpers now follow the C++ `std::sto*` family more closely for leading ASCII whitespace, optional signs, base-0 autodetection, hexadecimal prefixes, partial numeric consumption, and range failures.
- Tightened `StdUtils` hexadecimal prefix handling to match `std::sto*`: `0x`/`0xg` without a following hex digit now parse the leading zero instead of failing conversion.
- Aligned `TryParseInt` with the C++ `std::optional<int>` API by returning `Option<Int32>` after the existing `Stoi` 32-bit range check.
- Switched `StdUtils.Stod`/`Stold` to libc `strtod` behind C FFI with C++-style subject detection, preserving leading whitespace, `inf`/`nan`, and partial numeric consumption behavior that `std::stod` accepts.
- Added libc `errno`/`ERANGE` handling around `StdUtils.Stod`/`Stold`, so floating overflow and underflow now map to `None` like the C++ wrappers catching `std::out_of_range`.
- Aligned `GenerateRandomHexString` with the C++ native-random fallback path: the random word is initialized to zero, native random API failures are ignored, and the returned hex string reflects the final word rather than a time-hash substitute.
- Added the unsigned `FillZero` overload from the C++ header facade and matched Windows environment-variable key normalization in `StringifyEnvironmentPointer`.
- Added the Windows-only no-argument `GetApplicationPath` overload backed by `GetModuleFileNameA`, matching the C++ `Utils.cpp` platform split while preserving the existing argv/PATH overload for non-Windows.
- Brought `UserBase` profiling output closer to the C++ implementation: result-generation exceptions now print the same `OutputResult` diagnostic, and JSON profile writes no longer auto-create missing parent directories.
- Matched the C++ `UserBase` default output directory by leaving it empty until configured, so default profile filenames are passed through `JoinPath` as bare filenames.
- Aligned `CheckUtils` failure paths with C++ fatal semantics: assertions and abort helpers now call libc `abort` through C FFI, message variants write diagnostics to stderr before aborting, and `CJC_NULLPTR_CHECK` delegates to assertion failure instead of throwing a recoverable argument error.
- Restored the C++ signal utility split with `SignalUtil.cj`, and brought Unix alternate signal stack setup closer to `SignalUnix.cpp` by querying/preserving the old stack and reusing an existing active or sufficiently large alternate stack.
- Updated the Utils-local standard library map used by `ConvertPackageNameToLibCangjieBaseFormat` to include the same standard, deriving, and macro package entries as the real Driver table that C++ Utils consults.
- Deepened `SipHash` API fidelity by adding typed byte-representation hashing overloads for booleans, signed and unsigned fixed-width integers, and `Float32`/`Float64`, matching the C++ template entrypoint for arithmetic values instead of requiring callers to widen everything to `UInt64`.
- Matched `FloatFormat.IsUnderFlowFloat` to the C++ stream-extraction behavior by parsing directly through native `strtod` and intentionally ignoring `ERANGE`, so representational underflow such as `1e-400` is classified as underflow instead of being rejected by `StdUtils.Stod`.
- Aligned `StringifyEnvironmentPointer` duplicate handling with C++ `unordered_map::emplace`: the first normalized environment-variable key now wins instead of relying on `HashMap.add` duplicate semantics.
- Aligned the Windows `FileUtil.IsAbsolutePathAboveLengthLimit` path with the C++ `GetFullPathNameA`/`ERROR_FILENAME_EXCED_RANGE` check instead of only comparing the raw input length.

Known fidelity caveats:

- Utils exposes normal and signal-safe ICE temp-file cleanup hooks for the Driver port to register; the actual C++ `TempFileManager` deletion policy still belongs to Driver and is outside Utils' dependency boundary here.
- Unicode identifier keyword classification still mirrors lexer keyword metadata locally because the current `lex -> utils` package dependency would make a direct `utils -> lex` import cyclic.
- `StdlibMap.cj` still mirrors Driver standard-library metadata locally because importing Driver from Utils would create a package cycle; table contents are synced with the Driver port in this pass.
- `ParallelUtil` provides real generic indexed parallel dispatch, but the exact C++ CHIRBuilder/Translator entrypoint still requires CHIR-facing Cangjie types.
- Non-Linux memory profiling still uses the conservative Cangjie fallback rather than the C++ Windows/macOS process-memory APIs.

Remaining Utils selfhost markers: 0.
