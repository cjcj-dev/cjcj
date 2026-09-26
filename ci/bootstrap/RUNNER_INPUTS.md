# Bootstrap inputs per runner

kkk2 and GitHub Actions both exec `ci/bootstrap/bootstrap.sh` from the cjcj tree.
They do not exec `/root/cj_build/tools/bootstrap.sh`.

| runner | --base | --host-llvm-so | --ast-support | --colour-tuple | --colour-rt | --cpp-src | --cjcj-sha |
|---|---|---|---|---|---|---|---|
| kkk2 | `$HOME/.cjv/toolchains/$CJCJ_TOOLCHAIN` after `ci/setup_sdk.mjs` | same SDK `third_party/llvm/lib/libLLVM-15.so` | `CANGJIE_BUILD_ROOT/lib/libcangjie-ast-support.a` after static-libs, else campaign pin | `/root/llvmdepot/$LLVM_SHA/$CANGJIE_COMPILER_SHA` | `/root/sodepot/$RUNTIME_REF` | `$CANGJIE_WORKSPACE/cangjie_compiler` | `git rev-parse HEAD` |
| ubuntu-22.04 (linux-x64) | `$HOME/.cjv/toolchains/$CJCJ_TOOLCHAIN` from `ci/setup_sdk.mjs` + `ci/host_sdk_pin.env` | verified physical copy of `host-llvm-linux_x86_64`, pinned by `stage1_host_identities.txt` provenance | static-libs `CANGJIE_BUILD_ROOT/lib/libcangjie-ast-support.a` | download-artifact `fixed-llvm-tools-linux_x86_64` | explicit `CJCJ_BOOTSTRAP_COLOUR_RT`, verified against `ci/colour-runtime/` pin | `$CANGJIE_WORKSPACE/cangjie_compiler` after fetch | `GITHUB_SHA` |
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
| `build/build/schema/flatbuffers/ModuleFormat_generated.h` | source-built `flatc --no-warnings -c` | `ci/llvm_pin.env`: `CANGJIE_COMPILER_URL`, `CANGJIE_COMPILER_SHA`, `schema/ModuleFormat.fbs`, pinned FlatBuffers |

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

## In-process LLVM (Linux bootstrap)

The static tuple retains its eight entries. `prepare_bootstrap_inputs.mjs`
separately validates `dylib/libLLVM-15.so` against the platform pin under
`ci/llvm-dylib/`, then exports `CJCJ_BOOTSTRAP_COLOUR_LLVM_SO` and
`CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256`. `gha_run.sh` forwards both as
`--colour-llvm-so` and `--colour-llvm-sha256`; the kkk2 entry uses the same
platform digest rather than hashing an unreviewed input as its expected value.

`bootstrap.sh` physically copies `sdk-stage0` to `sdk-stage0-run`, installs the
pinned library, and checks both the installed identity and preserved host
identity. The official compiler continues using `sdk-stage0`. The cjcj compiler
runner loads LLVM from `sdk-stage0-run`; cjpm keeps the official host loader
binding. Official `llvm-objcopy` and `llvm-ar` children also use the host
loader binding, even when their parent cjcj process uses the pin library. The target SDK also receives the process library separately from its
static tuple. The existing official runtime/boundscheck/LLVM identity checks
remain in force. There is no LLVM fallback on an identity failure.

`COLOUR_LLVM_SO=/pin/libLLVM-15.so HOST_LLVM_SO=/official/libLLVM-15.so
python3 ci/bootstrap/test_colour_llvm.py -v` exercises the real preparation and
runner scripts, calls LLVMContextCreate/Dispose, checks `/proc/self/maps`, and
rejects wrong producer/consumer inputs. This device test uses a Python process
fixture; actual stage1 compiler acceptance additionally requires its own
loader trace and successful compilation. Run it on the build host.
