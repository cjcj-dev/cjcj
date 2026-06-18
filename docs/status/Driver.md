# Driver Port Status

Implemented a multi-file Cangjie Driver package replacing the scaffold:
`Driver.cj`, `Main.cj`, `MainFrontend.cj`, `Job.cj`, `Tool.cj`,
`ToolFuture.cj`, `ToolOptions.cj`, `DriverOptions.cj`,
`DriverOptionParser.cj`, `TempFileManager.cj`, `TempFileInfo.cj`,
`Backend.cj`, `CJNATIVEBackend.cj`, `ToolChain.cj`, `Gnu.cj`,
`MachO.cj`, platform toolchain files, target/stdlib tables, GCC scanner,
and driver utilities.

Current status:

- The package now builds as part of `cjpm build`.
- Command-line parsing, driver option normalization, target/stdlib lookup,
  temporary-file management, backend orchestration, tool futures, basic native
  backend command generation, and executable driver entry are implemented in
  Cangjie files mirroring the C++ Driver decomposition.
- Native backend execution is represented by external tool invocation through
  direct POSIX process FFI on non-Windows hosts. LLVM remains external; no LLVM
  reimplementation was added.
- Driver now depends directly on the real `basic`, `option`, and `utils`
  packages instead of carrying local compatibility copies for compiler version
  printing, target/optimization/output/sanitizer enums, `TripleInfo`, and
  `FileUtil`. Driver-owned model types remain only for Driver concepts such as
  tool IDs, tool futures, and temp-file records.
- Driver no longer carries local compatibility copies of option-owned
  `OrderedInput` or `EnvironmentOptions`; those aliases now resolve to the real
  `option` package types. Environment path ingestion uses the shared
  `MaybeString` representation and mirrors the C++ absolute-path normalization
  for `CANGJIE_HOME` and `SDKROOT`.
- Driver help output now delegates to the shared `option.OptionTable.Usage`
  path with the real global/driver option groups and experimental-mode
  filtering, replacing the local abbreviated compatibility usage text. Version
  and help no-op warnings now consider all classified input kinds, matching the
  C++ Driver's `ArgList::GetInputs()` behavior more closely.
- Target parsing now fills the real option `TripleInfo` shape, including
  vendor, Android API, Apple/iOS simulator environments, and the C++ `dylib`
  compile-target mapping to `SHARED_LIB`. Host/target defaults are initialized
  through Driver helpers that mirror the C++ host triple defaults while using
  the shared option type.
- Driver now preserves frontend/global arguments in parse order, filters out
  driver-only linker/toolchain options, and passes a pre-created temporary
  bitcode output path to the self-hosted FrontendTool bridge.
- The main entry now mirrors the C++ `cjc-frontend` dispatch path by checking
  the invoked executable name before normal driver parsing and calling the
  self-hosted FrontendTool entry directly.
- Sanitizer selection, `--sanitize-set-rpath` validation, CHIR emit mode,
  `chir`/`obj`/`hotreload` output-type parsing, PGO flags, section flags, jobs,
  warning forwarding, and target-triple validation are represented in Driver
  options.
- Coverage post-action reprocessing now matches the C++ `GlobalOptions`
  behavior by warning and forcing optimization back to `O0`; optimization
  levels no longer implicitly enable function/data sections, which are now
  controlled only by their explicit section flags as in the C++ option actions.
- Driver output post-actions now normalize `-o`/`--output-dir` through the same
  writable-directory checks used by the C++ `GlobalOptions::ReprocessOutputs`,
  reject output paths that would overwrite normalized inputs, enforce the
  `lib-macro_` output-name guard, and validate `--compile-macro` conflicts with
  explicit output-type or output-file choices.
- Package-directory input handling now follows the C++ `ProcessInputs` model
  more closely: directory inputs are accepted only in `-p`/`--package` mode,
  multiple package directories are retained in parse order, duplicate canonical
  package paths are rejected, and package source trees participate in output
  overwrite checks.
- OHOS target post-processing now mirrors `DisableStaticStdForOhos` by warning
  on `--static-std` and forcing dynamic standard-library selection before
  static-link validation.
- Obfuscation post-action validation now follows the C++ `DriverOptions`
  failure order and emits the specific error for each layout-only sub-option
  instead of a single grouped compatibility diagnostic.
- Driver post-action validation now carries more of the C++ `GlobalOptions`
  behavior needed by Driver: `--compile-as-exe` is tracked separately from
  `--compile-target`, LTO mode rejects unsupported targets/options, PGO gen/use
  conflicts and profile files are checked, compile-target is normalized for
  non-object output, and aggressive parallel compile defaults/disable rules are
  derived from jobs, target OS, LTO, coverage, and obfuscation.
- Driver option parsing now matches additional C++ `OptionTable` behaviors for
  path-bearing driver options: `-L`, `-B`, and `--sysroot` validate directories
  and store absolute paths, obfuscation mapping/config inputs are validated as
  readable files, and joined separated aliases such as `-Bpath`, `-opath`, and
  `-j4` are accepted.
- Driver input and linker argument ordering now tracks raw argv positions more
  closely: source/object/archive/bitcode inputs are validated during Driver
  parsing, object/archive/bitcode/shared-library inputs are normalized to
  absolute paths, `.a` inputs follow the C++ object/archive path, and `-l`,
  `--link-option`, and split `--link-options` values are emitted through the
  sorted input tuple stream instead of delayed synthetic positions.
- Host triple defaults now use compile-time `@When` OS/architecture selection
  instead of hardcoded Linux/x86_64 values.
- GNU/Linux native linking now mirrors the C++ driver more closely: target-
  specific Cangjie library directories, GCC CRT scanning, Linux CRT/linker
  script placement, sanitizer runtime lookup/fallbacks, PGO runtime placement,
  LTO linker options, target runtime rpath, standard-library static/dynamic
  grouping, and multi-module package partial linking are implemented.
- Thin-LTO linker option generation now resolves the cache directory to an
  absolute path and escapes backticks before emitting `--thinlto-cache-dir`,
  matching the C++ `ToolOptions::LLD::SetLTOOptions` behavior.
- Mach-O native linking now mirrors the C++ Darwin/iOS command builders more
  closely: SDK version probing, `ld64.lld` `-platform_version` arguments,
  target-qualified runtime/library search paths, `section.o`/`cjstart.o`
  placement, PGO/coverage runtime placement, dSYM plus ad-hoc codesign command
  scheduling, strip-to-final-output behavior, and Darwin/iOS runtime archive
  selection are implemented.
- Android, OHOS, and MinGW native linking now have platform-specific command
  builders rather than only generic Linux/Windows option tails: Android
  toolchain/sysroot library deduction, Android/OHOS CRT ordering and linker
  scripts, OHOS page-size/unwind/profile runtime behavior, MinGW sysroot
  library search, PE security flags, CRT object ordering, archive LD_LIBRARY_PATH
  handling, and the full MinGW system-library tail are represented.
- GNU partial linking now writes per-package `.__symbols` files, selects
  package-specific symbol-localization lists when available, schedules the
  `objcopy --localize-symbols` visibility pass, and copies combined package
  objects into the aggressive-parallel cache slot.
- Job execution now preserves C++ batch semantics more closely by running tools
  within a `ToolBatch` through a bounded worker set derived from `--jobs`, while
  keeping dependency-ordered batches sequential.
- External tool execution now uses direct POSIX `posix_spawn`/`posix_spawnp`
  and `waitpid` FFI with the Driver's sanitized environment vector, host-specific
  loader path variables (`LD_LIBRARY_PATH`/`DYLD_LIBRARY_PATH`), and libc spawn
  error text.

Residual fidelity risks:

- Driver self-host markers have been removed. Bitcode package names are read
  through LLVM C API bindings, and source compilation now invokes the
  self-hosted FrontendTool package. If the current frontend/codegen package
  boundary reports success without materializing the requested native bitcode,
  Driver keeps the run in frontend-only mode rather than invoking the backend
  on a missing file.
- GNU/Mach-O/platform toolchains are functional command builders with
  substantially more C++ parity, but symbol-localization data still depends on
  the frontend/codegen package boundary exposing the C++ in-process
  `GlobalOptions` state to Driver, and some platform-specific runtime library
  edge cases remain below the C++ driver.
- Package-directory input handling now has Driver-owned package path state and
  duplicate-canonicalization parity for direct directory inputs. Some scan-
  dependency `.cjo` package-input diagnostics still depend on broader shared
  option/front-end package state.
- The Windows-specific `main-frontend.cpp` process wrapper is represented by a
  direct Cangjie frontend shim rather than a separate `CreateProcess`-style
  executable launcher.
- POSIX external-process execution now has sanitized environment parity through
  direct `posix_spawn`/`waitpid` FFI. Windows process-launch parity still needs
  a native `CreateProcess`-style path when that backend is made host-active.

Module completion:

- Not complete. The build passes, but frontend/codegen package boundaries still
  do not expose the full C++ in-process `DefaultCompilerInstance` behavior to
  Driver, and cross-target behavior still needs runtime-backed validation.
