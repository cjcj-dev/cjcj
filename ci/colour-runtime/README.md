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
native install omits boundscheck, so the producer copies its unique output from
that build tree into the package. Files are copied, never linked. The official
SDK remains the separate, uncoloured host runtime.

Artifacts expire after seven days. Refresh the reviewed pin from another
successful producer when needed; there is no SDK/depot fallback. Persistent
Release assets remain outside #102. Other platforms need their own producer and
pin before their source cell can proceed.
