# Bootstrap colour runtime artifacts

`platform-matrix.yml` publishes `colour-runtime-linux_x86_64` from the exact
`ci/runtime_pin.env` revision. Dispatch with `runtime_only=true` to build that
input alone. The producer uses Ubuntu 22.04, matching the source SDK cell, and
RelWithDebInfo so the full symbol table remains available for verification.

Copy the four `COLOUR_RT_*` values printed by the successful producer into
`linux_x86_64.env`. `COLOUR_RT_MANIFEST_SHA256` pins `manifest.json`, which binds
the runtime source revision, platform, run ID/attempt, and every required library
SHA256. The source workflow downloads by run ID and artifact ID, then validates
the manifest and payloads before exporting the runtime path. A changed runtime
source pin requires a matching new runtime artifact.

The dynamic runtime, static runtime and boundscheck are from one build. Linux's
native install omits boundscheck, so the producer copies it from the exact
published configuration selected by the installed runtime digest and verified
by the runtime's output resolver. Staging and earlier configurations are not
package inputs. Files are copied, never linked.

The producer fetches the pinned H48 prerelease in `ci/h48_language_tuple_pin.json`.
Its native build runs the existing gate in `defer` mode, then
`ci/release/gate_colour_runtime.sh` activates a private SDK with the same target
pair and runs the complete gate in `all` mode before packaging. The H48 compiler
uses its separately pinned official host runtime; its generated executables use
the newly built coloured target runtime. The runner installs gdb for the native
teardown proof. H48's partial source provenance remains documented in
`ci/release/H48_LANGUAGE_TUPLE.md` and tracked by #135.

Artifacts expire after seven days. `release.json` records the matching
prerelease (tag, asset IDs, archive and manifest digests). Consumers still
download the exact Actions artifact named in the platform env. There is no
SDK/depot fallback. Linux aarch64 and Windows are not published by this pin.

Darwin uses `darwin_runtime_only=true` on the same workflow, with native
`macos-15` and `macos-15-intel` runners and sccache. Its independent input
contains the dynamic runtime, boundscheck and static runtime, built from
`ci/runtime_pin.env`. `darwin_runtime.mjs` records source/run/platform and
per-file digests and verifies the copied bytes. Native producer and consumer
controls must each reject their targeted corruption before artifact upload.

The Darwin entries in `release.json` contain their own complete prerelease
provenance; the top-level historical provenance belongs to the Linux entry.
The platform env files select the corresponding immutable Actions artifacts.
Darwin source jobs verify all three libraries, then report
`COLOUR_RT_STD_MISSING: <platform>` because these independent archives do not
provide coloured std. They do not certify a complete bootstrap input.
Issue #473 owns the native coloured std build and registration of the complete
input. The existing full-input std guard remains mandatory. The official host
runtime and boundscheck are a separate, unchanged SDK extraction described in
`ci/host-runtime/README.md`.

`verify-darwin-runtime.yml` downloads the pinned native inputs on both runners
and executes the actual source workflow shell entries. It verifies platform
pin presence, exact platform-specific rejection when that pin is removed,
restoration, library verification and the missing-std classification.
