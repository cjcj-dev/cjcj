# Official Darwin host runtime

`build-host-runtime.yml` runs on macos-15 and macos-15-intel. It loads
`ci/host_sdk_pin.env` and provisions the official SDK with `ci/setup_sdk.mjs`,
then copies its runtime and boundscheck libraries with `ci/release/host_runtime.mjs`.
The manifest retains the actual toolchain identity and both source digests.
The verifier compares each output against the original SDK bytes. Native
candidate/cut/restored checks replace the runtime copy with boundscheck and
require the runtime digest assertion to fail before restoring the source.

Dispatch the existing `platform-matrix.yml` with `darwin_host_only=true`.
Preserve the original Actions ZIPs and manifests in a prerelease together with
SHA256SUMS. Download and compare every asset byte for byte before and after
publication; record immutable coordinates in `release.json`.

These are official host libraries, not coloured target runtime or std.
`prepare_bootstrap_inputs.mjs` currently takes the host pair from its complete
base SDK. The standalone artifacts preserve the same native libraries for
Darwin bootstrap assembly; their publication does not establish a coloured
std or successful source bootstrap.
