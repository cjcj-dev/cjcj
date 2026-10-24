# Bootstrap inputs on Actions and kkk2

Both runners resolve bootstrap inputs with
`ci/release/prepare_bootstrap_inputs.mjs` before entering
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
upstream symlinks. An installed `CJCJ_SRCBUILD_HOST_SDK`, cjv installation, or
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

The final `ci/srcbuild/steps/build-shim.mjs` validates an explicit copy or the installed object
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
node --test ci/release/bootstrap_entries.test.mjs \
  ci/release/prepare_bootstrap_inputs.test.mjs ci/release/host_llvm.test.mjs
```

## Native target configuration

The source workflow requires `native_inputs_artifact` and its original
`native_inputs_run_id`. The artifact contains complete N/R/AST native install
roots and the two paired tools modules exported with
`node ci/bootstrap/deploy-native-tools.mjs TOOLS_REPO COMMIT EMPTY_DESTINATION`.
Its `locations.json` records `platform`, `installations` (each has relative
`install`, original `buildResult`, and `configuration`) and
`tools.privateRoot`. No removed receipt or SDK lock is a prerequisite.
`configure-gha-inputs.mjs` checks out the fixed LLVM, runtime, AST compiler and
H1 repositories, reads the actual candidate checkout, selects execution-host H,
and writes `CJCJ_SDK_INPUTS` into GITHUB_ENV. The artifact must contain genuine
native outputs; a source workflow cannot create this input by naming empty paths.
The eight bootstrap phases then use `sdk-targets.mjs`; native production and full
SDK qualification remain distinct from configuration-only checks.

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
