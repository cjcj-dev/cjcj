# Bootstrap inputs per runner

kkk2 and GitHub Actions both exec `ci/bootstrap/bootstrap.sh` from the cjcj tree.
They do not exec `/root/cj_build/tools/bootstrap.sh`.

| runner | --base | --host-llvm-so | --ast-support | --colour-tuple | --colour-rt | --cpp-src | --cjcj-sha |
|---|---|---|---|---|---|---|---|
| kkk2 | `$HOME/.cjv/toolchains/$CJCJ_TOOLCHAIN` after `ci/setup_sdk.mjs` | same SDK `third_party/llvm/lib/libLLVM-15.so` | `CANGJIE_BUILD_ROOT/lib/libcangjie-ast-support.a` after static-libs, else campaign pin | `/root/llvmdepot/$LLVM_SHA/$CANGJIE_COMPILER_SHA` | `/root/sodepot/$RUNTIME_REF` | `$CANGJIE_WORKSPACE/cangjie_compiler` | `git rev-parse HEAD` |
| ubuntu-22.04 (linux-x64) | `$HOME/.cjv/toolchains/$CJCJ_TOOLCHAIN` from `ci/setup_sdk.mjs` + `ci/host_sdk_pin.env` | `$base/third_party/llvm/lib/libLLVM-15.so` | static-libs `CANGJIE_BUILD_ROOT/lib/libcangjie-ast-support.a` | download-artifact `fixed-llvm-tools-linux_x86_64` | `CJCJ_BOOTSTRAP_COLOUR_RT` if set, else host SDK | `$CANGJIE_WORKSPACE/cangjie_compiler` after fetch | `GITHUB_SHA` |
| ubuntu-24.04-arm (linux-aarch64) | same nightly install | `$base/third_party/llvm/lib/libLLVM-15.so` | static-libs archive | `fixed-llvm-tools-linux_aarch64` | same |
| macos-15 (darwin-arm64) | same nightly install | `$base/third_party/llvm/lib/libLLVM*.dylib` or `.so` | host SDK `lib/*/libcangjie-ast-support.a` (no static-libs job) | `fixed-llvm-tools-darwin_aarch64` | same |
| macos-15-intel (darwin-x64) | same nightly install | same dylib search | host SDK archive | `fixed-llvm-tools-darwin_x86_64` | same |

`ci/release/prepare_bootstrap_inputs.mjs` resolves those paths, hashes them, and exports `CJCJ_BOOTSTRAP_*`.

For the default fetched `--cpp-src`, both runners execute
`ci/bootstrap/prepare_cpp_headers.mjs` before stage0. kkk2 calls it in
`run_bootstrap_stage`; Actions calls it while resolving bootstrap inputs.
Explicit `CJCJ_BOOTSTRAP_CPP_SRC` / `CANGJIE_CPP_SRC` trees remain supplied by the
caller and must already satisfy `bootstrap.sh`'s header checks.

| Shim include root under the fetched compiler | Producer | Source identity |
|---|---|---|
| `third_party/llvm-project/llvm/include` | exact LLVM source checkout | `ci/llvm_pin.env`: `LLVM_URL`, `LLVM_SHA` |
| `build/build/third_party/llvm/include` | LLVM CMake configure and `llvm-headers` target | same LLVM checkout |
| `build/build/include/flatbuffers` | copy FlatBuffers public includes | `ci/llvm_pin.env`: `FLATBUFFERS_URL`, `FLATBUFFERS_SHA` |
| `build/build/schema/flatbuffers/ModuleFormat_generated.h` | source-built `flatc --no-warnings -c` | `ci/source_pin.env`: `COMPILER_REF`, `schema/ModuleFormat.fbs`, pinned FlatBuffers |

This preparation builds LLVM header dependencies and flatc; it does not build
the C++ compiler. The independent LLVM and FlatBuffers builds run concurrently.
`build/build/shim-headers.json` records source revisions, schema and flatc hashes,
executed commands, and a file/hash inventory of each include root.

On a build host, with the other bootstrap inputs configured as above, run
`bash ci/bootstrap/test_cpp_headers.sh /absolute/path/to/new-test-directory`.
The integration test fetches a clean compiler checkout, confirms the real shim
consumer rejects missing inputs, invokes the Actions input resolver, verifies the
header inventory, and builds the actual shim object. It preserves logs and
artifacts in the supplied directory. No external CPP_SRC or shim object is used.
