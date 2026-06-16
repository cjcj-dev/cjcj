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

- Driver self-host markers have been removed. Bitcode package names are read
  through LLVM C API bindings, and source compilation now invokes the
  self-hosted FrontendTool package.
- GNU/Mach-O/platform toolchains are functional command builders but still omit
  many C++ driver details around SDK/sysroot discovery, exact sanitizer/runtime
  library selection, and linker flag parity.
- Main frontend support is a compiling shim rather than the full C++
  `main-frontend.cpp` standalone flow.

Module completion:

- Not complete. The build passes, but frontend/codegen package boundaries still
  do not expose the full C++ in-process `DefaultCompilerInstance` behavior to
  Driver, and platform toolchain parity remains incomplete.
