# BLOCKED-REPORT: Driver platform parity

## Status

Correctly blocked on missing named Windows string, filesystem, diagnostic, and process facilities. No compiler source change is included in this report commit.

The task scope is the 12 Driver `DIVERGENT` rows `PB035`–`PB044`, `PB055`–`PB056` and the 2 `MISSING` rows `PB047`–`PB048` in `PLATFORM_PARITY_AUDIT.tsv`. Work stopped at the first missing dependency, as required by `AGENTS.md`; no `std.fs`/`std.process` approximation or narrow-string fallback was added.

The first blocked port is the Windows branch of `CheckExecuteResult` in `/root/cj_build/cangjie_compiler/src/Driver/Job.cpp:30-69`. Its branch at lines 34-43 calls two named facilities that selfhost does not provide:

- `Cangjie::StringConvertor::StringToWString` (`src/Basic/StringConvertor.cpp:408-418`), returning an optional UTF-16 wide string after distinguishing UTF-8 and GBK;
- `Cangjie::WErrorf` (`include/cangjie/Basic/Print.h:135-148`), writing the wide error mark and formatted wide arguments to `stderr`.

`StringToWString` is not eligible for the proportional <=40-line exception because its prerequisite `CodePageToUTF16` (`src/Basic/StringConvertor.cpp:26-45`) is also absent. That prerequisite calls the unbound Win32 `MultiByteToWideChar` API twice and requires a faithful wide-string representation. Selfhost `packages/basic/src/StringConvertor.cj` ends without `StringToWString`; its current non-ASCII `GBKToUTF8`/`UTF8ToGBK` paths return `None` at lines 371-384. Selfhost `packages/basic/src/Print.cj` has no `WErrorf` counterpart.

## Per-item ledger

| Audit ID | Official entity / branch | State | Missing prerequisite that prevents a faithful port |
|---|---|---|---|
| PB035 | `Job.cpp:25-27` Windows `StringConvertor` include | BLOCKED | `StringConvertor::StringToWString` and its `CodePageToUTF16`/`MultiByteToWideChar` prerequisite are absent. |
| PB036 | `CheckExecuteResult`, `Job.cpp:30-69`, Windows branch `:34-43` | BLOCKED | `StringConvertor::StringToWString` and `WErrorf` are absent. |
| PB037 | `Job::Execute`, `Job.cpp:97-144`, Windows branch `:117-134` | BLOCKED | `StringConvertor::StringToWString` and `WErrorf` are absent. |
| PB038 | `TempFileManager.cpp:26-30` Windows system includes | BLOCKED | The corresponding wide filesystem and CRT foreign bindings are absent; they are consumed by PB040-PB044. |
| PB039 | `TMP_DIR_ENVIRONMENT_KEY`/`DEFAULT_TMP_DIR`/`CODE`, `TempFileManager.cpp:33-41` | NOT STARTED | Independent constant branch, intentionally not cherry-picked after the earlier mandatory stop. |
| PB040 | `GetErrMessage`, `TempFileManager.cpp:75-99` | BLOCKED | Windows `strerror_s` foreign binding is absent. |
| PB041 | `MakeTempDir`, `TempFileManager.cpp:134-160` | BLOCKED | `StringConvertor::StringToWString` and `_wmkdir` are absent. |
| PB042 | `RemoveDirRecursively`, `TempFileManager.cpp:162-211` | BLOCKED | Wide path support plus `FindFirstFileW`, `FindNextFileW`, `FindClose`, `DeleteFileW`, and `RemoveDirectoryW` bindings/records are absent. |
| PB043 | `TempFileManager::DeleteTempFiles`, `TempFileManager.cpp:431-462` | BLOCKED | `StringToWString`, `GetFileAttributesW`, `DeleteFileW`, and PB042's `RemoveDirRecursively(std::wstring)` are absent. |
| PB044 | `TempFileManager::DeleteTempFilesSignalSafe`, `TempFileManager.cpp:464-480` | BLOCKED | `DeleteFileA` and `RemoveDirectoryA` foreign bindings are absent. |
| PB047 | `WriteArgsToResponseFile`, `Tool.cpp:36-64` | BLOCKED | `GetTempPathA` and `GetTempFileNameA` bindings are absent; the named entity must retain all failure branches and binary/truncate file semantics. |
| PB048 | `GetSystemErrorMessage(DWORD)`, `Tool.cpp:65-97` | BLOCKED | `FormatMessageW`, `LocalFree`, and `WideCharToMultiByte` bindings plus a faithful UTF-16 buffer representation are absent. |
| PB055 | `Tool::Run`, `Tool.cpp:202-253` | BLOCKED | `STARTUPINFOA`, `PROCESS_INFORMATION`, `CreateProcessA`, `GetLastError`, and the Windows process-future constructor are absent; PB047/PB048 are direct prerequisites. |
| PB056 | `WindowsProcessFuture` and `GetState`, `ToolFuture.h:89-108`, `ToolFuture.cpp:30-45` | BLOCKED | `PROCESS_INFORMATION`, `WaitForSingleObject`, `GetExitCodeProcess`, and `CloseHandle` are absent. |

PB039 is the only row whose local branch is just constants. It was not modified because the task had already encountered a missing dependency and the required action is to stop, preventing a partial diff from disguising an incomplete Windows execution chain.

## Mechanical absence evidence

Repository search for the required named facilities and Win32 APIs produces no implementation in the selfhost packages, apart from the already-existing unrelated `GetLastError` declaration in `FileUtil.cj`:

```text
$ rg -n 'CreateProcessA|WaitForSingleObject|FormatMessageW|WideCharToMultiByte|GetTempPathA|GetTempFileNameA|FindFirstFileW|_wmkdir|DeleteFile[AW]|RemoveDirectoryW|CloseHandle|PROCESS_INFORMATION|STARTUPINFO|StringToWString|WErrorf' packages
packages/compiler_unittest/src/PortDeferred.cj:19:// PORT-DEFERRED: Utils/SignalTests main/parser signal and stack-overflow cases require C++ ExecuteProcess fork/exec and CreateProcessA harnesses ...
packages/compiler_unittest/src/PortDeferred.cj:20:// PORT-DEFERRED: Utils/UtilsTest.RemoveDirectoryWithSymlinkChild and RemoveDirectoryTargetIsSymlink require C++ CreateSymlinkCrossPlatform ...
packages/utils/src/signal_test.cj:5:// Windows CreateProcessA branch at :189; the selfhost std.unittest harness cannot faithfully run crashing
packages/utils/src/file_util_test.cj:439:    // PORT-DEFERRED: RemoveDirectoryWithSymlinkChild and RemoveDirectoryTargetIsSymlink require
```

All four hits are comments documenting other deferred tests; none declares or implements a required API.

The narrower declaration search shows only the unrelated ANSI file metadata API already used by `FileUtil`:

```text
$ rg -n 'GetLastError|GetFileAttributesA|SetFileAttributesA' packages/utils/src/FileUtil.cj
105:    func GetFileAttributesA(pathname: CString): UInt32
106:    func SetFileAttributesA(pathname: CString, attributes: UInt32): Int32
109:    func GetLastError(): UInt32
```

The source-level string facility gap is:

```text
$ rg -n 'StringToWString|CodePageToUTF16|MultiByteToWideChar' packages/basic/src packages/driver/src packages/utils/src
<no matches>
```

## Required restoration APIs

Resume this Driver lane only after dedicated dependency ports supply these official facilities:

1. **Windows string lane**: `StringConvertor::CodePageToUTF16(unsigned, String) -> Option<wide string>` and `StringConvertor::StringToWString(String) -> Option<wide string>`, preserving UTF-8/GBK/unknown branches from `StringConvertor.cpp:26-45,408-418`, backed by `MultiByteToWideChar` and an ABI-correct UTF-16 representation.
2. **Windows diagnostic lane**: `WErrorf` semantics from `Print.h:135-148`, including wide error-mark conversion and wide `stderr` output.
3. **Windows filesystem lane**: ABI-correct bindings and records for `strerror_s`, `_wmkdir`, `WIN32_FIND_DATAW`, `FindFirstFileW`, `FindNextFileW`, `FindClose`, `GetFileAttributesW`, `DeleteFileW`, `DeleteFileA`, `RemoveDirectoryW`, and `RemoveDirectoryA`.
4. **Windows temporary-file/error lane**: bindings for `GetTempPathA`, `GetTempFileNameA`, `FormatMessageW`, `LocalFree`, and `WideCharToMultiByte`.
5. **Windows process lane**: ABI-correct `STARTUPINFOA` and `PROCESS_INFORMATION`, plus `CreateProcessA`, `GetLastError`, `WaitForSingleObject`, `GetExitCodeProcess`, and `CloseHandle`.

These are system-bound ABI surfaces, not ordinary <=40-line helpers. Their record layouts, calling conventions, ownership rules, constants, and Windows linking behavior must be established by dedicated ports; declaring guessed signatures in Driver would violate the faithful-port constraint.

After those dependencies are merged, resume in dependency order: PB047/PB048, PB056, PB055, PB035-PB037, then PB038-PB044 (including PB039). Each official function must be ported with every branch and early return.

## Platform and branch audit

Raw platform grep for all four official source files:

```text
/root/cj_build/cangjie_compiler/src/Driver/Job.cpp:25:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Job.cpp:34:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Job.cpp:117:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/TempFileManager.cpp:26:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/TempFileManager.cpp:33:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/TempFileManager.cpp:79:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/TempFileManager.cpp:140:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/TempFileManager.cpp:162:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/TempFileManager.cpp:438:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/TempFileManager.cpp:471:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:15:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:30:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:36:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:65:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:119:#ifdef __APPLE__
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:122:#elif !defined(_WIN32)
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:143:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:149:#ifndef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:155:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:161:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:182:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/Tool.cpp:202:#ifdef _WIN32
/root/cj_build/cangjie_compiler/src/Driver/ToolFuture.cpp:30:#ifdef _WIN32
```

Full-branch coverage is N/A because no target function was ported. The complete task platform surface is recorded above: Windows branches in all 14 rows, plus the already-COVERED Apple/POSIX environment-name chain at `Tool.cpp:119-125`; no platform branch was silently approximated.

## Delivery declarations

- `/root/cj_build/audit_persist/verify.sh /root/cj_build/wt/fix_platdriver delta fix_platdriver` was invoked, but it produced no gate line because it remained queued on the shared `/tmp/verify_global.lock` behind other worktrees. It was stopped after the blocker report was complete (`VERIFY-EXIT=130`, no build or test stage started). Since there is no compiler-source diff, no green gate is claimed.
- 无任何 grep 不到 C++ 出处的新符号；本报告没有新增编译器符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的系统根已 BLOCKED 上报、未自行替代。
- No temporary instrumentation, debug output, or generated test artifact was added.
