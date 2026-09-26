# Bootstrap host LLVM

Each source cell uses a separately produced native host library. The per-platform
source declarations in `host_llvm_source.env` currently select `418ace1896e22a51a6c1fa36ec29631b00301cd8`: the official base with the
standalone build adjustment and the `visitRelocate(undef)` repair. It is separate
from the static colour tuple and the in-process colour dylib in `ci/llvm_pin.env`.

Dispatch `build-fixed-llc.yml` with `publish_host=true`, `publish_tuple=false`,
and `publish_dylib=false`. The four native host jobs use sccache and each upload a physical
`libLLVM-15.so` (Linux) or `libLLVM.dylib` (Darwin), a content digest, full defined-symbol listings, and a manifest
identifying the source, producer commit, run, attempt, and platform. The upload
step records the immutable artifact ID in the run summary.

The host recipe retains RTTI for the official llc ABI and keeps the full symbol
table for inspection. It checks `llvm::cl::Option`'s type information as well as
`visitRelocate`; the colour dylib's RTTI-off recipe cannot serve as a host recipe.

After reading back a successful artifact, pin its `HOST_LLVM_PROVENANCE` JSON
comment in `stage1_host_identities.txt`. The record carries repository, run,
attempt, artifact, source SHA and producer SHA. Linux digest rows use
`<platform> <library> <sha256>` for the full runtime/boundscheck/LLVM triple.
Both acquisition and the Linux stage1 runner select those rows by platform;
there is no unscoped fallback. Darwin acquisition continues to use its JSON
record's library digest. JSON Linux library digests are producer provenance;
the scoped row is the expected digest used to verify downloaded bytes.

The runtime and boundscheck rows are fixed from the official release named by
`ci/host_sdk_pin.env`; archive names and SHA256 receipts accompany the pins.
Updating the SDK requires reviewing these rows as well. Neither preparation nor
the runner learns an expected digest from the input it is checking.

`test_host_identities.py` enters the real runner on its native Linux platform,
checks its installed binding, and exercises per-library rejection before any SDK
mutation. Supplying `HOST_IDENTITY_SDK` and `HOST_IDENTITY_LLVM` adds a real
three-library receipt against the checked-in pins. This proves the identity
apparatus only, not a complete stage1 compilation.

| Source target | Producer platform | Library |
| --- | --- | --- |
| linux-x64 | linux_x86_64 | libLLVM-15.so |
| linux-aarch64 | linux_aarch64 | libLLVM-15.so |
| darwin-arm64 | darwin_aarch64 | libLLVM.dylib |
| darwin-x64 | darwin_x86_64 | libLLVM.dylib |

`srcbuild.yml` loads the artifact and run IDs with `host_llvm.mjs env`, downloads
that artifact, and passes its directory as `CJCJ_BOOTSTRAP_HOST_LLVM_ARTIFACT`.
The preparation CLI uses `CJCJ_SRCBUILD_TARGET` (or the native Node platform and
architecture for local callers) to select the platform declaration. Every source
cell must provide the corresponding artifact directory (library plus manifest).
Missing pins, missing artifacts, changed bytes, or mismatched provenance stop
preparation; none selects a nightly SDK library or a colour dylib. The verified
output is a physical copy with the library's native filename.

This establishes host LLVM acquisition and provenance, not complete platform
bootstrap support. The existing bootstrap/stage1 runner platform and runtime
identity constraints still apply independently.

The CI apparatus tests enter `prepare_bootstrap_inputs.mjs` and observe its
exported library bytes and declared hash. A one-digit identity change must fail
with `HOST_LLVM_SHA256_MISMATCH`, and provenance changes must fail with
`HOST_LLVM_PROVENANCE_MISMATCH`. These checks establish acquisition and identity,
not compiler semantics. A source workflow run must separately reach the stage1
runner identity checks.
