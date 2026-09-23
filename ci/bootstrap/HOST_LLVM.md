# Bootstrap host LLVM

The Linux x86_64 source cell uses a separately produced host library. Its source
is `418ace1896e22a51a6c1fa36ec29631b00301cd8`: the official base with the
standalone build adjustment and the `visitRelocate(undef)` repair. It is separate
from the static colour tuple and the in-process colour dylib in `ci/llvm_pin.env`.

Dispatch `build-fixed-llc.yml` with `publish_host=true`, `publish_tuple=false`,
and `publish_dylib=false`. The host job uses sccache and uploads a physical
`libLLVM-15.so`, a content digest, full defined-symbol listings, and a manifest
identifying the source, producer commit, run, attempt, and platform. The upload
step records the immutable artifact ID in the run summary.

The host recipe retains RTTI for the official llc ABI and keeps the full symbol
table for inspection. It checks `llvm::cl::Option`'s type information as well as
`visitRelocate`; the colour dylib's RTTI-off recipe cannot serve as a host recipe.

After reading back the successful artifact, update the
`HOST_LLVM_PROVENANCE` comment and `libLLVM-15.so` digest together in
`stage1_host_identities.txt`. The JSON comment carries the repository, run,
attempt, artifact, source SHA, producer SHA, and platform. The runner continues
to enforce its declared digest; the preparation step reads that same declaration
and checks the downloaded manifest and bytes before making a physical copy.
The expected digest is never learned from a download during a consumer run.

`srcbuild.yml` loads the artifact and run IDs with `host_llvm.mjs env`, downloads
that artifact, and passes its directory as `CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT`.
The preparation CLI uses `CJCJ_SRCBUILD_TARGET` (or the native Node platform and
architecture for local callers) to match that download boundary. Linux x64
callers must provide the same artifact directory (library plus manifest); missing
or invalid input never falls back to the nightly library or colour dylib.
The other existing source cells (`linux-aarch64`, `darwin-arm64`, `darwin-x64`)
retain their native SDK host-library selection and content digest. They do not
consume this x64 artifact or claim its repaired provenance. Producing and pinning
repaired host libraries for those cells remains separate work; this change does
not establish that their complete bootstrap pipeline succeeds.

The CI apparatus tests enter `prepare_bootstrap_inputs.mjs` and observe its
exported library bytes and declared hash. A one-digit identity change must fail
with `HOST_LLVM_SHA256_MISMATCH`, and provenance changes must fail with
`HOST_LLVM_PROVENANCE_MISMATCH`. These checks establish acquisition and identity,
not compiler semantics. A source workflow run must separately reach the stage1
runner identity checks.
