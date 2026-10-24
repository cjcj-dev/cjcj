# Cross producer resource inputs

Android, OHOS and iOS use the caller's `CANGJIE_BUILD_JOBS`, then a nonempty
`CMAKE_BUILD_PARALLEL_LEVEL`, then Node's available CPU domain. The std producer
first honors its separate `STD_BUILD_JOBS`. An explicit selection must be a
positive safe integer; explicit oversubscription is allowed. The existing CMake meaning
of an empty `CMAKE_BUILD_PARALLEL_LEVEL` is preserved as an unspecified value.

R79b's runtime `build.py` consumes `CANGJIE_BUILD_JOBS` from its environment; it
has no `-j` option. Its stdlib `build.py` consumes `-j`. Each platform caller
passes the selected value through that actual interface. This does not assign
more memory or disk, change the admitted CPU allocation, or authorize a CI run.

`cross-jobs-entry.test.mjs` invokes the public Android runtime and Android/OHOS
std scripts using a real Python command fixture. It checks the child environment
and argv, separate runtime/std selections, source rejection and invalid budgets.
The fixture emits clearly nonproduction runtime bytes to reach the std command,
then stops before std installation. It is not a runtime/std build result.
Actual iOS execution requires the registered Darwin source cell and Xcode.

`cross-runtime-build-type.test.mjs` invokes the public platform runtime script
for the upstream-supported release, debug and relwithdebinfo configurations.
It checks the build selection, actual install argument and artifact directory;
its command fixture is not a compiled Windows runtime. The existing release
workflow still selects release and therefore keeps its release artifact path.

For native Windows runtime builds, an explicit `RUNTIME_TOOLCHAIN` selects that
root's `bin/clang.exe` for the existing compile probe. A failed explicit compiler
does not silently fall back to another installation. The selected MINGW64 root
then supplies both the MSYS2 PATH and build.py's `--target-toolchain`; the script
does not replace it with `/mingw64`. The existing MINGW64/MSVCRT requirement and
linker configuration are unchanged. `MSYS2_BASH` remains the shell selector.
