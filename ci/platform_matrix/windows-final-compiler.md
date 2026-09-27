# Windows final compiler release acceptance

The workspace `cjpm.toml` is the release optimization source for native stage3
and Windows W2. `build_cjcj.mjs` saves it before changing W1 to `-O1` and passes
the saved text to `buildWindowsFinalCompiler`. W2 restores it before `cjpm clean`
and `cjpm build`. The current release setting is `-O2`.

The upstream release anchor is
`cangjie_build@d4be4ed309919fece8e7d4b8720ed861ebeccae4:docs/linux_cross_windows.md:226`
(`build.py build -t release`); upstream builds a C++ compiler. The Cangjie
optimization setting comes from this repository's `cjpm.toml`, also consumed by
`ci/srcbuild/steps/build-stage3.mjs`.

For an actual Windows release run, retain all of the following:

- The source commit and the workspace TOML read by W2, showing `-O2`. Its SHA256
  must match `production.workspaceOptionsSha256` in
  `FINAL-COMPILER-PROVENANCE.json`.
- The W2 `cjpm clean` and `cjpm build` logs, with actual compiler commands; check
  that no later option overrides `-O2`. Record the W1 parent, final std, runtime,
  LLVM manifest and W2 executable hashes from the same run.
- Unpack the SDK in a fresh Windows location. Run the packaged compiler to
  compile and run a small program using only the packaged environment. Record
  exit codes and hashes; `cjc --version` alone is not acceptance.
- Collect the PE import table for the final `cjc.exe` and recursively for its
  non-system DLL dependencies. For every imported DLL, record its installed
  relative path, SHA256 and source artifact. Do not satisfy dependencies using
  the build machine's MSYS2 installation on PATH.

## DLL inventory to verify in the unpacked SDK

| DLL family | Expected provider / packaged location | Acceptance |
| --- | --- | --- |
| `libcangjie-runtime.dll` (or `cangjie-runtime.dll`) | Same-run coloured Windows runtime, `runtime/lib/windows_x86_64_cjnative/` | Exact runtime artifact hash; no official runtime substitute |
| `libboundscheck.dll` | Same runtime install, `runtime/lib/windows_x86_64_cjnative/` | Exact artifact hash and recursive import resolution |
| `libcangjie-std*.dll` | Same-run Windows final std, `runtime/lib/windows_x86_64_cjnative/` | Exact final-std artifact hashes; no inherited official std |
| `libstdc++-6.dll`, `libgcc_s_seh-1.dll`, `libwinpthread-1.dll` | Selected MinGW toolchain | For each actual PE import, locate a bundled provider reachable in the packaged environment and record its hash; build-only copies do not qualify |
| LLVM DLLs, if imported | Selected Windows LLVM tuple, normally `third_party/llvm/lib/` or next to the executable | Record actual imports and bundled providers; do not infer dynamic dependencies from archive link flags |
| Windows system/API-set DLLs | Supported Windows OS | Record names separately from bundled dependencies |

The three MinGW names are the existing tool-staging list, not a claim that W2
imports all three. The PE import closure determines the required set. Compiler
artifacts currently carry the executable and provenance; copying DLLs into the
W2 build SDK does not prove those DLLs reach the release package.

`build/test/windows-final-compiler.test.mjs` exercises the actual JavaScript
continuation with a subprocess fixture. It checks the workspace at the build
handoff, provenance and DLL staging. It does **not** execute a Windows compiler,
prove emitted code optimization, or validate the final SDK's PE import closure.
Those checks require the Windows release run above.
