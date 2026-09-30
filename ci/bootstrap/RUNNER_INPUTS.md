# Bootstrap inputs on Actions and kkk2

Both runners resolve bootstrap inputs with
`ci/release/prepare_bootstrap_inputs.mjs` before entering
`ci/bootstrap/bootstrap.sh`. Actions consumes the exported environment through
`ci/bootstrap/gha_run.sh`; kkk2's `load_bootstrap_pins` consumes the same
resolver's quoted shell output. Preparation failures publish no bootstrap
command. Stage 31/32 preparation does not run the separate fixed-tools publisher.

The resolver reads the common host SDK, LLVM, runtime, AST, runtime-artifact and
dylib pin files for the selected target. Workflow-provided pin environment values
use the same validation as those loaded from the files. No runner-specific
expected digest is calculated from downloaded bytes.

| Input | Identity authority | Transport/cache selection |
|---|---|---|
| Official host SDK | `HOST_SDK_PROVENANCE` in `ci/bootstrap/stage1_host_identities.txt`, matched to `ci/host_sdk_pin.env` | `CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE`, otherwise the pinned official release archive downloaded into the input work directory |
| Repaired host LLVM | `HOST_LLVM_PROVENANCE` and platform digest in the same identities file | `CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT`, otherwise download its pinned artifact |
| AST support | `ci/ast_support/<platform>.env` / `AST_SUPPORT_SHA256` | explicit `CJCJ_BOOTSTRAP_AST_ARTIFACT`, then explicit `CJCJ_BOOTSTRAP_AST_SUPPORT`, then build/SDK archive, otherwise pinned artifact download |
| Static LLVM tuple | `ci/bootstrap_inputs_pin.json` per-file digests and `ci/llvm_pin.env` independent sums digest | shared bootstrap store; release by default; explicit artifact/depot mode requires `CJCJ_BOOTSTRAP_SOURCE_REASON` |
| Coloured runtime and std | `ci/colour-runtime/<platform>.env` manifest digest, source/run identity and every manifest member | `CJCJ_BOOTSTRAP_COLOUR_RT` artifact root, otherwise pinned artifact download |
| In-process LLVM dylib | `ci/llvm-dylib/<platform>.env` digest/source and artifact manifest | `CJCJ_BOOTSTRAP_DYLIB_ARTIFACT` or `CJCJ_BOOTSTRAP_COLOUR_DYLIB`, otherwise pinned artifact download |

An explicit missing or corrupt input fails preparation; it does not fall back
to another path. Automatic artifact downloads require the existing `gh` transport
and `unzip`; supplying local artifact directories avoids that transport. All
supplied directories still pass exactly the same identity checks.

The official SDK is extracted from the verified archive without dereferencing
upstream symlinks. An installed `CJCJ_SRCBUILD_HOST_SDK`, cjv installation, or
dereferenced sharedbuild SDK is not a bootstrap base. Its archive SHA identifies
the whole distribution and its original layout. No shared installation is
modified. Missing platform archive pins fail with `HOST_SDK_PIN_MISSING`;
Darwin archive pins remain pending registration by #766.

A depot is an explicit transport path (`CJCJ_BOOTSTRAP_COLOUR_TUPLE` with
`CJCJ_BOOTSTRAP_SOURCE=depot`), not an identity inferred from 12/40-character
directory names. The resolver makes no implicit `/root/llvmdepot` lookup.
Every selected payload must match the common pin before the tuple is exported.
The fixed-tools producer used by other source-build steps does not supply
bootstrap's static tuple implicitly.

The runtime input is the complete artifact root containing `manifest.json`,
runtime libraries, the static archive and the manifest's std/module members.
The former flat two-library directory, caller-supplied
`CJCJ_BOOTSTRAP_COLOUR_RT_SHA256` / `CJCJ_BOOTSTRAP_BOUNDSCHECK_SHA256`, and
CJRT stamp check are no longer a separate kkk2 identity contract. Likewise,
`AST_SUPPORT_SHA256` is the shared AST input pin;
`CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256` is a validated output for bootstrap.

Successful preparation prints `BOOTSTRAP_INPUT_IDENTITIES=<JSON>`: the official
archive, repaired host LLVM, AST, each tuple payload, runtime manifest and dylib
SHA256 identities. Paths may differ between runners; this table must match
for the same inputs. The runtime manifest transitively authenticates its members.
The table is emitted only after all checks and C++ header preparation succeed.

For the default fetched compiler source, the common resolver invokes
`ci/bootstrap/prepare_cpp_headers.mjs` before stage0. Explicit
`CJCJ_BOOTSTRAP_CPP_SRC` / `CANGJIE_CPP_SRC` trees are caller-owned and must
already satisfy bootstrap's header checks. Header preparation uses pinned LLVM
and FlatBuffers sources, builds LLVM headers and flatc concurrently, and records
the commands and file inventory in `build/build/shim-headers.json`.

The dylib is separate from the static tuple. Bootstrap installs it in the cjcj
runner SDK while preserving the official compiler's host LLVM binding.
`bootstrap_entries.test.mjs` executes the actual kkk2 driver and Actions resolver,
compares identities and consumer argument bytes, and independently changes each
input to verify rejection before command publication. These are preparation
device tests, not stage1 compilation acceptance.

Run the preparation tests on the build host:

```sh
ulimit -c 0
node --test ci/release/bootstrap_entries.test.mjs \
  ci/release/prepare_bootstrap_inputs.test.mjs ci/release/host_llvm.test.mjs
```
