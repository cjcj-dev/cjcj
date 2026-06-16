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
  the current Cangjie process APIs. LLVM remains external; no LLVM reimplementation
  was added.
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
- GNU/Linux native linking now mirrors the C++ driver more closely: target-
  specific Cangjie library directories, GCC CRT scanning, Linux CRT/linker
  script placement, sanitizer runtime lookup/fallbacks, PGO runtime placement,
  LTO linker options, target runtime rpath, standard-library static/dynamic
  grouping, and multi-module package partial linking are implemented.
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
- External tool execution now uses the Driver's sanitized environment vector on
  POSIX hosts through an `env -i` launcher, so `LD_LIBRARY_PATH` and blocked
  loader/compiler-wrapper variables are applied to the actual process rather
  than only to verbose command text.

Residual fidelity risks:

- Driver self-host markers have been removed. Bitcode package names are read
  through LLVM C API bindings, and source compilation now invokes the
  self-hosted FrontendTool package.
- GNU/Mach-O/platform toolchains are functional command builders with
  substantially more C++ parity, but symbol-localization data still depends on
  the frontend/codegen package boundary exposing the C++ in-process
  `GlobalOptions` state to Driver, and some platform-specific runtime library
  edge cases remain below the C++ driver.
- The Windows-specific `main-frontend.cpp` process wrapper is represented by a
  direct Cangjie frontend shim rather than a separate `CreateProcess`-style
  executable launcher.
- POSIX external-process execution now has sanitized environment parity through
  the standard process API, but it still goes through an `env` launcher rather
  than a direct `posix_spawn`/`CreateProcess` FFI implementation.

Module completion:

- Not complete. The build passes, but frontend/codegen package boundaries still
  do not expose the full C++ in-process `DefaultCompilerInstance` behavior to
  Driver, and cross-target behavior still needs runtime-backed validation.
