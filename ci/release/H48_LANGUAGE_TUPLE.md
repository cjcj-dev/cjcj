# Retained H48 language tuple

This prerelease preserves the compiler/stdlib inputs used by the kkk2 managed
language gate. It is **not a rebuild of current master** and is not a stable
release. The release tag explicitly says `provenance-partial`.

The published release is `396986820`; its exact asset IDs and digests are in
[`ci/h48_language_tuple_pin.json`](../h48_language_tuple_pin.json).

The compiler source is `35da7be2434ad72348ed27e8a0bf599ec4e91524` (the retained
build changes its compile option to `-O1`). The target LLVM source is
`1ecb811801cae9968e0046048943e34c923a34c9`. The compiler process uses the separately
packaged official runtime and boundscheck whose host SDK identity is
`sources.compiler.host_sdk` in [`ci/h48_language_tuple_pin.json`](../h48_language_tuple_pin.json).
Every shipped file has a digest and an origin category in `language-tuple.json`.

The rebuilt std/FFI source archive's commit was **not recorded**. Its source SHA
is `unrecorded`; its retained bytes and compiler/llc/opt/ld.lld input digests are pinned.
[cjcj#135](https://github.com/cjcj-dev/cjcj/issues/135) owns rebuilding a tuple
with complete source provenance. The 2026-09-24 controller decision permits this
partial-provenance handoff specifically to reproduce the existing H48 inputs.

The coloured **target runtime is not included**. A consumer must build it from
its own immutable runtime source pin. Old target SOs, stale backend manifests,
and unused ast-support whose provenance is incomplete are excluded explicitly
by `language_tuple.EXCLUDED`. No target runtime source identity is inferred from
those old files.

## Download and check

Use `python3 ci/release/publish_language_tuple.py fetch --pin ci/h48_language_tuple_pin.json --output <new-dir>`.
The fetcher downloads by release asset ID, verifies all asset digests, validates
the prerelease identity, safely extracts the archive, and verifies the entire
payload inventory, compiler identity, and component roles. It never resolves
`latest`. Local GitHub operations use `/root/.local/bin/cjcj-bot exec gh`; in
Actions the installed `gh` uses the workflow's repository-scoped token.

Verify again before consuming a retained directory:

```sh
set -euo pipefail
python3 ci/release/language_tuple.py verify \
  --root <download-dir>/installed/tuple \
  --manifest-sha256 <pin.manifest_sha256> \
  --compiler-sha256 <pin.compiler_sha256> --env > verified.env
# Source only after the command above succeeds.
. ./verified.env
```

`CJC` points at `sdk/bin/cjc`, `CANGJIE_HOME` at `sdk`, and
`GC_UNIT_CJC_RUNTIME_LIB_DIR` at the separate `host/runtime/lib/linux_x86_64_cjnative`.
The consumer supplies `GCV2_RUNTIME_LIB_DIR` for its newly built target runtime.
The only symbolic links are `sdk/bin/cjc` and `sdk/bin/cjc-frontend`, both pointing
to the adjacent `cjcj-stage1`; this basename is part of the compiler's dispatch.
All other payloads are physical files.

## Publication

The producer supplies an explicit provenance document, including independently
collected per-file digests and origin categories. `language_tuple.py pack`
physically copies the retained SDK and official host pair, applies the documented
exclusions, and validates copied bytes against those receipts before archiving.
`publish_language_tuple.py publish` rechecks both the directory and actual
archive, creates a draft prerelease, uploads the archive/provenance/SHA256SUMS,
reads every uploaded asset back by ID, and only then publishes with `latest=false`.
Its output pin records the immutable release and asset IDs and all asset digests.
Retained builds have no Actions build run/artifact ID; provenance records those
as null rather than inventing a source build run.

The Python device contract tests use synthetic files. They establish validation
behavior only; the delivery report separately records the real downloaded H48
language gate, its ELF/SO hashes, and the wrong-digest/nightly-substitution arms.

The compiler's linker searches the SDK's own runtime directory. For compilation,
compose a **private** SDK with the consumer's verified runtime pair:

```sh
set -euo pipefail
python3 ci/release/language_tuple.py activate \
  --root <download-dir>/installed/tuple \
  --manifest-sha256 <pin.manifest_sha256> \
  --compiler-sha256 <pin.compiler_sha256> \
  --target <runtime-build-library-directory> \
  --target-runtime-sha256 <runtime-build-receipt-digest> \
  --target-boundscheck-sha256 <boundscheck-build-receipt-digest> \
  --output <new-private-directory> > activated.env
# Source only after activation succeeds.
. ./activated.env
```

Activation verifies the tuple and external runtime digests before copying, checks
all copied files, and emits the four role variables only after validation. The
original downloaded tuple remains unchanged and can still be verified against
the release pin. The official host runtime remains outside the target SDK.

`GCV2_RUNTIME_LIB_DIR` stays at the supplied runtime build directory so the
phase-entry fixture can find its adjacent generated headers. The runtime pair
copied into the private SDK is only the compiler's link input, with identical
pinned digests. Do not repoint the gate at an SDK directory lacking those headers.
The `PROVENANCE-NOTES.json` release asset lists every exclusion and its reason;
its digest is included in the pin and SHA256SUMS.
