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
- The implementation is intentionally conservative at package boundaries: this
  module-only pass did not change project manifests or adjacent packages, so the
  executable Driver cannot yet call the self-hosted FrontendTool package through
  a typed package dependency.

Residual fidelity risks:

- Two Driver self-host markers remain in source. One covers LLVM bitcode
  source-file-name extraction through an LLVM C FFI binding; the other covers
  typed FrontendTool invocation once the package graph exposes that dependency.
- GNU/Mach-O/platform toolchains are functional command builders but still omit
  many C++ driver details around SDK/sysroot discovery, exact sanitizer/runtime
  library selection, and linker flag parity.
- Main frontend support is a compiling shim rather than the full C++
  `main-frontend.cpp` standalone flow.

Module completion:

- Not complete. The build passes, but the remaining Driver self-host markers and
  toolchain/frontend fidelity gaps must be eliminated before this module can be
  marked production-grade and behavior-faithful.
