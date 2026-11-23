# Bootstrap inputs on Actions and kkk2

The native descriptor accepts `visibleOptionsOnly` (default `true`). A developer
build can set it to `false`; the normal graph passes the setting to H1 and both
compiler producers as `sdk-native-stage.mjs --visible-options-only false`.
This selects the option package's existing CJPM `--cfg
CANGJIE_VISIBLE_OPTIONS_ONLY` condition, restoring its manifest after the build.
The installed compiler does not read an environment override. Help, option
lookup, option-value validation and option actions use the same compiled policy;
the separate experimental/stable checks still apply. Reusing a compiler produced
with a different policy is rejected. No setting is forwarded to std producers.
Each producer selects the requested value from the actual option manifest,
including default builds reentering after an interrupted development build.
Normal completion or failure restores the incoming manifest bytes. Legacy
sources without the switch are accepted only for `true` and only when the
three option implementations match the known hardcoded-true 8e9 source bytes;
unknown legacy implementations are rejected before build commands.

Both runners resolve bootstrap inputs with
`build/sdk/producers/release/prepare_bootstrap_inputs.mjs` before entering
`ci/bootstrap/bootstrap.mjs`. Actions consumes the exported environment through
`ci/bootstrap/gha_run.sh`; kkk2's `load_bootstrap_pins` consumes the same
resolver's quoted shell output. Preparation failures publish no bootstrap
command. The full 2..36 entry prepares native fixed tools before numbered steps
with the same `prepareColourTuple` function used by bootstrap preparation.

The resolver selects official H and repaired host LLVM for the execution host.
LLVM target, runtime, AST, runtime-artifact and dylib pins remain target inputs. Workflow-provided pin environment values
use the same validation as those loaded from the files. No runner-specific
expected digest is calculated from downloaded bytes.

| Input | Identity authority | Transport/cache selection |
|---|---|---|
| Official host SDK | `HOST_SDK_PROVENANCE` in `ci/bootstrap/stage1_host_identities.txt`, matched to `ci/host_sdk_pin.env` | `CJCJ_BOOTSTRAP_HOST_SDK_ARCHIVE`, otherwise the pinned official release archive downloaded into the input work directory |
| Repaired host LLVM | `HOST_LLVM_PROVENANCE` and platform digest in the same identities file | `CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT`, otherwise download its pinned artifact |
| AST support | `ci/ast_support/<platform>.env` / `AST_SUPPORT_SHA256` | explicit `CJCJ_BOOTSTRAP_AST_ARTIFACT`, then explicit `CJCJ_BOOTSTRAP_AST_SUPPORT`, then complete build/SDK input package, otherwise pinned artifact download |
| Static LLVM tuple | `ci/bootstrap_inputs_pin.json` per-file digests and `ci/llvm_pin.env` independent sums digest | shared bootstrap store; release by default; explicit artifact/depot mode requires `CJCJ_BOOTSTRAP_SOURCE_REASON` |
| Coloured runtime and std | `ci/colour-runtime/<platform>.env` manifest digest, source/run identity and every manifest member | `CJCJ_BOOTSTRAP_COLOUR_RT` artifact root, otherwise pinned artifact download |
| In-process LLVM dylib | `ci/llvm-dylib/<platform>.env` digest/source and artifact manifest | `CJCJ_BOOTSTRAP_DYLIB_ARTIFACT` or `CJCJ_BOOTSTRAP_COLOUR_DYLIB`, otherwise pinned artifact download |

An explicit missing or corrupt input fails preparation; it does not fall back
to another path. The AST archive's parent directory must include the producer's
`SHA256SUMS`, public headers, generated schema header, schema and flatbuffers
payload. Bare implicit build/SDK archives are not SDK input packages and do not
prevent the pinned artifact download. An explicitly selected incomplete package
fails before exporting bootstrap inputs; consumers still verify the producer's
original checksums.

Automatic artifact downloads require the existing `gh` transport
and `unzip`; supplying local artifact directories avoids that transport. All
supplied directories still pass exactly the same identity checks.

The official SDK is extracted from the verified archive without dereferencing
upstream symlinks. An installed `CJCJ_OFFICIAL_SDK_ROOT`, cjv installation, or
dereferenced sharedbuild SDK is not a bootstrap base. Its archive SHA identifies
the whole distribution and its original layout. No shared installation is
modified. Missing platform archive pins fail with `HOST_SDK_PIN_MISSING`;
All five native platform archive declarations are recorded; each platform keeps
its own version, size, URL and SHA256.

A depot is an explicit transport path (`CJCJ_BOOTSTRAP_COLOUR_TUPLE` with
`CJCJ_BOOTSTRAP_SOURCE=depot`), not an identity inferred from 12/40-character
directory names. The resolver makes no implicit `/root/llvmdepot` lookup.
Every selected payload must match the common pin before the tuple is exported.
The native fixed-tools preparation copies the verified tuple's `fixed-llc/`
members to `CJCJ_FIXED_LLVM_DIR` for setup_sdk and stage3. The former kkk2 depot
discovery and optional source-build publisher are removed. Tuple production
belongs to the independently pinned artifact producer, not this consumer.

The runtime input is the complete artifact root containing `manifest.json`,
runtime libraries, the static archive and the manifest's std/module members.
The former flat two-library directory, caller-supplied
`CJCJ_BOOTSTRAP_COLOUR_RT_SHA256` / `CJCJ_BOOTSTRAP_BOUNDSCHECK_SHA256`, and
CJRT stamp check are no longer a separate kkk2 identity contract. Likewise,
`AST_SUPPORT_SHA256` is the shared AST input pin;
`CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256` is a validated output for bootstrap.

The currently registered runtime artifact is stale relative to `runtime_pin.env`
(#501); both entries reject that mismatch. Historical pins used for preparation
acceptance do not change the product pins.

Successful preparation prints `BOOTSTRAP_INPUT_IDENTITIES=<JSON>`: the official
archive, repaired host LLVM, AST, each tuple payload, runtime manifest and dylib
SHA256 identities. Paths may differ between runners; this table must match
for the same inputs. The runtime manifest transitively authenticates its members.
The table is emitted only after all checks and C++ header preparation succeed.

Cjo headers use the existing `prepare_cpp_headers.mjs` producer and a private
`bootstrap-inputs/cjo-shim-headers` output. Defaults are the fixed compiler/LLVM/
runtime/FlatBuffers commits in `shim-source-commits.json`; historical binary tuple
pins are unchanged. `shim_source_selection` on every public workflow forwards
`CJCJ_BOOTSTRAP_SHIM_SOURCE_SELECTION`: an object keyed by compiler, llvm, runtime,
flatbuffers, with actual repository and full commit. Private commits require an
explicit reachable repository; no official URL is invented. Local callers may
instead pass `CJCJ_BOOTSTRAP_SHIM_SOURCES`, a JSON file with the same rows and
existing root, plus archive.file/archive.sha256 for a fixed Git archive.

The producer validates actual sources, configures against the selected runtime,
generates LLVM headers, builds the matching host flatc and generates CjoFormat.
It records selected sources and actual commands once in `BUILD-INPUTS.json`.
Normal CMake targets handle regeneration and re-entry; no header inventory or
second configuration certificate is produced. The selected LLVM/runtime pair
is checked when preparing its real sources.

The final `build/sdk/producers/srcbuild/steps/build-shim.mjs` validates an explicit copy or the installed object
against the same original producer source/byte facts. If that object is
unavailable, it genuinely compiles the complete TU with the selected headers,
preparing them normally when no external header output was supplied. Source
compilation uses the normal compiler launcher/cache and never reuses a local
object merely because it exists or has a newer mtime.
The manual cold-entry driver is `cpp-headers.integration.mjs`; the old shell pathname
only forwards to that implementation. Full host/tuple/N/SDK qualification is
separate from the finite real shim object and header-production tests.

The dylib is separate from the static tuple. Native CMake installs it directly;
validation reads those bytes, checks the fixed LLVM commit stamp and digest, and
executes the three target lookups through its C API. Official H bytes remain
unchanged. `prepare-bootstrap-plans.mjs` generates ordinary build targets from
fixed Git inputs and actual N/R/AST installation locations.

Run the preparation tests on the build host:

```sh
ulimit -c 0
node --test build/sdk/producers/release/bootstrap_entries.test.mjs \
  build/sdk/producers/release/prepare_bootstrap_inputs.test.mjs build/sdk/producers/release/host_llvm.test.mjs
```

## Native target configuration

The source workflow requires `native_inputs_artifact` and its original
`native_inputs_run_id`. The artifact contains complete N/R/AST native install
roots. On Windows the job checks out the exact workflow SHA for both the H1
seed and the next compiler stages; Node runs the job-installed zx CLI.
Native Windows builds the public `cjcj-dev/cjcj-tools` at the `TOOLS_REF` of
`ci/source_pin.env` (`build/sdk/producers/srcbuild/source-selection.mjs`); no
read token is needed. The repository variable WINDOWS_TOOLS_REPOSITORY can still
name another owner/name, which must serve that same pinned commit.
Do not put adapter sources or a tools.privateRoot in any native-inputs artifact;
`configure-gha-inputs.mjs` rejects a `tools.privateRoot`. Linux and Darwin build
H1 through the same public CJPM producer of `sdk-native-stage.mjs`: H's cjpm/cjc
compile the pinned workspace, the host's `packages/cjc` target section supplies
the ELF or Mach-O link inputs, and the H LLVM library and directory (the Mach-O
`-rpath`) become N's, so the transitional stages execute H1 with N LLVM.
`locations.json` records `platform`, `host` (`install`, the original official
`archive` file and `version`), `installations` (each has relative `install`,
original `buildResult`, and `configuration`), `tools` and, for tools builds,
`hleDependencies`. No removed receipt or SDK lock is a prerequisite.

The release `phase=prepare` producer (`prepare_native_inputs.mjs`) uploads each
native-inputs root and each runtime installation as one tar
(`native-inputs.tar`, `runtime-install.tar`) because Actions artifacts drop
POSIX modes; consumers run `ci/bootstrap/native-artifact-archive.mjs unpack`,
which requires that single archive, before the host is executed. The host is
the pinned official archive downloaded by `bootstrap_host_sdk.mjs` and kept
under `host-archive/` with its original name; `HOST-INPUT.json` binds its size
and SHA-256. The same producer supplies the HLE dependency package, the N shim
object and cjdb. Its cjbind is the fixed cjbind-cangjie v1.1.0-alpha.53.1
release, which has no darwin-x64 asset; its four assets embed four different
Cangjie toolchains and none comes from the tag commit's own build, so no
darwin-x64 source build can be verified to match it and that host fails closed
with `HLE_CJBIND_UNAVAILABLE darwin_x86_64`.
`configure-gha-inputs.mjs` checks out the fixed LLVM, runtime, AST compiler and
H1 repositories, reads the actual candidate checkout, selects execution-host H,
and writes `CJCJ_SDK_INPUTS` into GITHUB_ENV. The artifact must contain genuine
native outputs; a source workflow cannot create this input by naming empty paths.
The eight bootstrap phases then use `sdk-targets.mjs`; native production and full
SDK qualification remain distinct from configuration-only checks.

For a native Windows tools build the same input root must also contain the
Lombok JAR used to build cjprof. Set `cjprofLombok` in `locations.json` to
`{"path":"dependencies/lombok.jar","sha256":"<digest of the supplied JAR>"}`.
The tools step verifies the relative file against this digest, then invokes the
normal tools producer with the installed stage3 frontend, shim, LLVM and stdx.
The selected cjcj-tools commit must itself build and install the Windows tools.

The manual `verify-windows-install.yml` reuses the package job on windows-2025.
Pass the successful native producer run ID, version, its exact `std_artifact`
output and native runtime artifact prefix. Leave both source refs empty for the
pinned pair or provide both full SHAs and the original host version. Both SDK
and std come from the same repository/run at the verifier commit. This workflow
uploads consumer diagnostics; it does not publish the SDK.

The same native artifact also carries the independently produced HLE dependency
package. Extract it under an artifact-owned directory and record
`hleDependencies` in `locations.json`, relative to that artifact root, pointing
to its `hle-dependencies.relative.json`. Keep the Node, modules and cjbind paths
relative to that descriptor. `configure-gha-inputs.mjs` uses `hle-input.mjs` to
validate and export this selection; `job-handoff.mjs` preserves its archived
closure and `tools.run` resolves the three paths at consumption. The component
can be checked separately with `node ci/bootstrap/hle-input.mjs ROOT PLATFORM`;
this does not create or qualify missing LLVM/runtime/AST native inputs.

For a tools-only target dependency build, `build/cli.mjs --stdx-profile sdk-tools
build stdx` selects the fixed stdx producer's existing `--skip-chir`,
`--skip-syntax`, and `--without-effect-handlers` options. This does not qualify
complete stdx. The default remains `full`. Set `CANGJIE_BUILD_JOBS` explicitly
when bounding the native build; stdx, cjfmt and LSP forward the value (capped to
the admitted CPU affinity) to their existing `--jobs` options.
