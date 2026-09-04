# Bootstrap inputs per runner

kkk2 and GitHub Actions both exec `ci/bootstrap/bootstrap.sh` from the cjcj tree.
They do not exec `/root/cj_build/tools/bootstrap.sh`.

| runner | --base | --host-llvm-so | --ast-support | --colour-tuple | --colour-rt |
|---|---|---|---|---|---|
| kkk2 | `$HOME/.cjv/toolchains/$CJCJ_TOOLCHAIN` after `ci/setup_sdk.mjs` | same SDK `third_party/llvm/lib/libLLVM-15.so` | `CANGJIE_BUILD_ROOT/lib/libcangjie-ast-support.a` after static-libs, else campaign pin | `/root/llvmdepot/$LLVM_SHA/$CANGJIE_COMPILER_SHA` | `/root/sodepot/$RUNTIME_REF` |
| ubuntu-22.04 (linux-x64) | `$HOME/.cjv/toolchains/$CJCJ_TOOLCHAIN` from `ci/setup_sdk.mjs` + `ci/host_sdk_pin.env` | `$base/third_party/llvm/lib/libLLVM-15.so` | static-libs `CANGJIE_BUILD_ROOT/lib/libcangjie-ast-support.a` | download-artifact `fixed-llvm-tools-linux_x86_64` | `CJCJ_BOOTSTRAP_COLOUR_RT` if set, else host SDK |
| ubuntu-24.04-arm (linux-aarch64) | same nightly install | `$base/third_party/llvm/lib/libLLVM-15.so` | static-libs archive | `fixed-llvm-tools-linux_aarch64` | same |
| macos-15 (darwin-arm64) | same nightly install | `$base/third_party/llvm/lib/libLLVM*.dylib` or `.so` | host SDK `lib/*/libcangjie-ast-support.a` (no static-libs job) | `fixed-llvm-tools-darwin_aarch64` | same |
| macos-15-intel (darwin-x64) | same nightly install | same dylib search | host SDK archive | `fixed-llvm-tools-darwin_x86_64` | same |

`ci/release/prepare_bootstrap_inputs.mjs` resolves those paths, hashes them, and exports `CJCJ_BOOTSTRAP_*`.
