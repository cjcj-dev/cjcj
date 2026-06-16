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
- Sanitizer selection, `--sanitize-set-rpath` validation, CHIR emit mode,
  `chir`/`obj`/`hotreload` output-type parsing, PGO flags, section flags, jobs,
  warning forwarding, and target-triple validation are represented in Driver
  options.
- GNU/Linux native linking now mirrors the C++ driver more closely: target-
  specific Cangjie library directories, GCC CRT scanning, Linux CRT/linker
  script placement, sanitizer runtime lookup/fallbacks, PGO runtime placement,
  LTO linker options, target runtime rpath, standard-library static/dynamic
  grouping, and multi-module package partial linking are implemented.

Residual fidelity risks:

- Driver self-host markers have been removed. Bitcode package names are read
  through LLVM C API bindings, and source compilation now invokes the
  self-hosted FrontendTool package.
- GNU/Mach-O/platform toolchains are functional command builders. Linux/GNU
  linkage has substantially more C++ parity, but exact symbol-localization data
  from codegen partial-linking, some Android/OHOS/MinGW specialized linker
  arguments, Darwin SDK/codesign behavior, and full platform-specific runtime
  library edge cases remain below the C++ driver.
- Main frontend support is a compiling shim rather than the full C++
  `main-frontend.cpp` standalone flow.

Module completion:

- Not complete. The build passes, but frontend/codegen package boundaries still
  do not expose the full C++ in-process `DefaultCompilerInstance` behavior to
  Driver, and platform toolchain parity remains incomplete.
