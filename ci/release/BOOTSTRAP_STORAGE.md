# Persistent bootstrap inputs

`build-fixed-llc.yml` is the publication entry point. In one workflow
run it calls the existing fixed tuple producer, waits for its artifact ID, then
publishes exactly that artifact's reviewed file list to a dedicated prerelease
`bootstrap-<run>-<attempt>-<artifact>-prerelease`. The publisher reads back both the artifact
and every Release asset before publishing the draft or emitting its candidate
pin. Both release mutations explicitly set `prerelease: true` and
`make_latest: "false"`; formal release publication requires separate approval.
It does not overwrite an existing tag or asset. The pin carries both
SHA-256 values (required to agree), source provenance, immutable asset IDs and
file modes. Release assets have no Actions artifact retention deadline.

Release assets are the first choice: they support individual downloads by ID
and fit the tuple payload sizes. GHCR would add a registry packaging and
retrieval layer without a requirement that Release assets cannot meet.
GitHub documents the per-file 2 GiB limit at
https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases.

The existing dispatchable publishing entry point confines `contents: write` to its publish
job. Existing read-only callers use `build-llvm-tools.yml` and remain read-only;
reusable workflows cannot elevate a caller's token permissions:
https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations.

After checking the actual publication and its digests, commit the emitted
`bootstrap-inputs-pin.json` as `ci/bootstrap_inputs_pin.json`, together with any
corresponding `ci/llvm_pin.env` and `ci/llvm_tuple_SHA256SUMS` update. Never fill
asset IDs with placeholders or compute the consumer's expected digest from an
unreviewed download. The initial checked publication is
[`bootstrap-35858653195-1-10748596481-prerelease`](https://github.com/cjcj-dev/cjcj/releases/tag/bootstrap-35858653195-1-10748596481-prerelease),
from [run 35858653195, attempt 1](https://github.com/cjcj-dev/cjcj/actions/runs/35858653195).
Its nine asset IDs and both per-file digests are recorded in
`ci/bootstrap_inputs_pin.json`; the fixed artifact is `10748596481`.

`prepare_bootstrap_inputs.mjs` defaults to Release assets. To explicitly recover
from another source set `CJCJ_BOOTSTRAP_SOURCE=artifact` or `depot` and provide
`CJCJ_BOOTSTRAP_SOURCE_REASON`. Depot mode uses
`CJCJ_BOOTSTRAP_COLOUR_TUPLE` or the existing nested depot coordinates. Every
selected source must satisfy the same pin. Unavailable or changed input stops
that invocation; there is no automatic fallback. Output is a private directory
of regular files, exposed only after the entire list verifies. Executable modes
come from the reviewed pin rather than transport-specific ZIP metadata.

The mechanism accepts a file list; the current workflow publishes the ten
static LLVM payloads plus SHA256SUMS. The fixed in-process LLVM and ast-support inputs from #82/#86 retain their
existing download and reviewed-digest checks. They are not connected to this
persistent publisher (advisor ruling
sym_cjcj_87_implement_r5786084191-20260922T233426Z).

Focused checks (run on kkk2):

```
node --test ci/release/bootstrap_store.test.mjs ci/release/publish_bootstrap_inputs.test.mjs ci/release/prepare_bootstrap_inputs.test.mjs
```

The publisher tests simulate only GitHub transport. They execute the real
publisher CLI and artifact extractor, but do not certify GitHub authorization,
published assets, or stage0. Those require the real publication acceptance run.
