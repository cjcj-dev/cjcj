# Native Windows Clang and runtime input

`native-cjdb-job` supplies the normal `native-cjdb.json` and calls
`native-cjdb.mjs`. On Windows that producer now calls
`probeWindowsToolchain` before the large N configuration. CI owns installation
and PATH selection of the fixed toolchain; the producer resolves actual
`tools.cc`/`tools.cxx` files and records their hashes, version and target output.

Selected provider: official `mstorsjo/llvm-mingw` release `20261020`,
`llvm-mingw-20261020-msvcrt-x86_64.zip`, 172961237 bytes,
SHA256 `52a3e3f584a74c3cde8ceb0c6960549683178e03b36818cb02b7ed109a68ff67`.
Unpack the normal archive on the admitted runner; prepend its `bin` directory,
or pass its absolute `clang.exe` and `clang++.exe` paths. Keep the root and
`x86_64-w64-mingw32/bin` layout. The package's named version is a source fact;
actual compiler version and execution are recorded only when it runs.

The probe uses the compiler source's real MinGW toolchain and runtime install
module. It compiles a C++ exception/string consumer with MSVCRT headers, runs
normal CMake install and executes the installed program with only installation
and Windows system directories on PATH. It checks actual PE imports for CRT
compatibility, but those imports are not a loaded-library trace. ETW loaded
evidence remains the separate collector/decoder contract.

The large build receives the same actual compiler paths and DLL list. After
normal CMake install, the producer verifies the manifest and bytes at the
three consumer locations, then runs installed llc and flatc with the restricted
PATH. `BUILD-INPUTS.json.windowsToolchain` stores the observed compiler,
installed relative file paths/hashes and an `original` relative reference to
`share/cjcj/build-inputs/windows-toolchain.json`. That file contains the actual
probe commands/results. No consumer fabricates a success status or receipt.

The selected archive has been downloaded and its required members checked.
The former package's PE and installation evidence does not qualify this version. Actual Windows compiler version,
small compilation, N/CJDB/AST build, installation execution, ETW loading and
full SDK package/clean-unpack consumption remain NOT_RUN until runner approval.
The native source pair and compiler/AST selection come from the source pins
or an explicit paired input. Their compatible Windows CMake changes and a
qualified runtime/compiler/AST ABI tuple are required independently.

Finite helper tests accept an explicit existing host `LLVM_READOBJ` plus
`TOOLCHAIN_DLL_DIRECTORY` and `TOOLCHAIN_TEST_EVIDENCE`. They inspect actual
PE imports, check failing CRT controls, resolve paths, and exercise the
non-Windows rejection through both public CLIs. They do not emulate a Windows
runner or certify dynamic loading.
