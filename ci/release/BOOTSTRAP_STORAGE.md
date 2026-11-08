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
That initial publication used fixed artifact `10748596481`. The current asset IDs,
fixed artifact and per-file digests are recorded in `ci/bootstrap_inputs_pin.json`.

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


## Persistent archive inputs

`ci/bootstrap_artifacts_pin.json` maps immutable producer artifact IDs to
prerelease ZIP asset IDs and reviewed archive SHA256 values. Artifact IDs remain
provenance labels; the default downloader never queries Actions for these inputs.
`bootstrap_artifact.mjs` and the pinned workflow downloads use
`download_pinned.mjs`, which checks the archive SHA256 before extraction. Missing
pins, unavailable assets and digest mismatches stop without an artifact fallback.
Existing host, AST, LLVM and runtime payload/manifest checks still run downstream.
Same-run job handoffs and dynamically selected build artifacts keep their existing
Actions transport; they are not frozen input pins.

The #857 migration copies original artifact ZIP bytes to
`bootstrap-input-archives-857-prerelease`, retaining their GitHub artifact digests.
Colour runtime, LLVM dylib and host runtime archives already had prerelease assets.
The existing Linux colour archive preserves the reviewed manifest SHA256
`401becfac2b48477ae7096d64bc41703c9699c26871a61050cad557039f07bbe`, but that
manifest identifies runtime `4c4cbf53b44497103e76e2a47a8fa35f5d7a7287`, while
`ci/runtime_pin.env` selects `9733dfc09d29eca27d19cc3937a149838b4e3322`.
Persistent storage does not resolve that separate source identity mismatch (#859);
the 9733 input remains pending #855. These temporary prereleases must be removed
before the formal 0.0.2 release; no formal release or latest is created here.

## Native platform continuation

The current single-platform official pin is retained byte for byte. Its legacy
untagged payload belongs only to `linux_x86_64`. Explicit version-2 registries
select a platform entry before acquisition; a version-1 candidate carrying its
own `platform` is also accepted. Missing ARM/Darwin pins never fall back to x64.
The manifest platform, selected pin digest, and independent sums override remain
checked by the shared `bootstrap_tuple.mjs` consumer, including the existing
`acquire_fixed_tuple.mjs DESTINATION FIXED_TOOLS` entry. No retired shell
consumer is restored.

`build-fixed-llc.yml` -> `build-llvm-tools.yml` selects exactly the requested
native platforms, builds tools with the existing sccache action, and creates
one `static-llvm-tuple-<platform>` artifact per selected Linux/Darwin host.
Darwin preserves `ld64.lld` through compressed tools, executable tuple and
checksums; Linux preserves `ld.lld`. The persist job identifies each immutable
artifact separately. The output is a candidate pin; this source change does
not update official pins or establish native execution qualification.

Full Darwin bootstrap still requires its native host LLVM, AST/std/runtime and
SDK inputs plus the separately reviewed #904 integration. Source readiness
continues to report those missing producers. #906 Apple capture, #907 installed
alternate-stack behavior, device execution and full SDK packaging are separate
uncompleted acceptance obligations.

## Full native SDK

This is the complete source-built SDK (`srcbuild-target.yml` artifact
`cjcj-srcbuild-<target>-<version>`), not an LLVM component prerelease and not
the qualified language SDK above. Its upload step runs under `always()`, so an
artifact existing is not evidence that the SDK passed its gates.

Chain: producer `srcbuild` job (package-install, source-tool install, verify)
-> `ci.yml` `package-tests` in candidate mode (`workflow_dispatch` with
`native_sdk_run_id` and `native_sdk_version`) -> `persist-native-sdk`
(only with `persist_native_sdk: true` and a successful candidate
`package-tests`) -> new prerelease -> readback -> reviewed registry commit ->
default consumers.

Producer binding (`persist_native_sdk.mjs`, applied both when a candidate is
received and again before publication): the producer run is a completed
`workflow_dispatch` run of this repository from an allowed srcbuild caller
(`release.yml`, `release-matrix.yml`, `arm-soak.yml`). In that run's current
attempt, exactly one `<target> / srcbuild` job ran with that attempt number and
the run's head and concluded `success`. The artifact was created between that
job's start and completion, so bytes uploaded under the same name by a failed
earlier attempt are refused. The producer commit must equal or be an ancestor of
the accepting commit. A target job that was not re-run in the current attempt
fails closed; the producer has to be re-run.

Acceptance: `select` resolves the candidate run and version to one artifact ID.
`receive-candidate` checks that ID's name, run, expiry, recorded digest and
size (at most 2 GiB - 1, the release asset limit), applies the producer binding,
downloads exactly that ID, requires the bytes to match the recorded digest and
unpacks them for `receive_native_sdk.mjs` and the registered package tests. The
digest is a `package-tests` job output.

`ci/release/persist_native_sdk.mjs publish` requires that accepted digest to
equal the artifact's recorded digest and the downloaded bytes. It reapplies the
producer binding, requires exactly one packaged SDK archive with a matching
`.sha256`, and checks that the uploaded SDK asset reads back with the same
SHA-256. It then creates a draft prerelease
`native-sdk-<target>-<version>-<artifact>-<persist run>-<attempt>-prerelease`
(`make_latest: "false"`). It uploads the original artifact ZIP, a separate
`gate-logs.zip` and a `provenance.json`, and reads every asset back. It then
selects the new entry the way consumers will and downloads it with
`download_pinned.mjs`, unpacks the package facts, and only after that publishes
the draft as a prerelease. Existing tags, releases and assets are never reused
or overwritten. The job's `native-sdk-persist-<target>` artifact keeps the
provenance and log even when publication fails.

The emitted `registry-entry.json` is an ordinary `ci/bootstrap_artifacts_pin.json`
entry with a `native_sdk: {target, version, ...}` marker. The artifact ID is a
provenance key; consumers download the release asset by ID and SHA-256 and never
query Actions for it. `download_pinned.mjs --select-native-sdk <target>` accepts
exactly one marked entry per target: none stops with
`NATIVE_SDK_PERSISTENT_PIN_MISSING` and more than one stops with
`NATIVE_SDK_PERSISTENT_PIN_AMBIGUOUS`. The default consumers are `ci.yml`
`package-tests` (linux-x64) and `platform-matrix.yml` `colour-runtime` for each
matrix target (linux-x64 and linux-aarch64). Both use the same
`persist_native_sdk.mjs select` + `download_pinned.mjs` path, so linux-aarch64
stops with `NATIVE_SDK_PERSISTENT_PIN_MISSING` until an accepted entry for that
target exists. Nothing falls back to a run ID, repository variable or expired
artifact.

Lifecycle: one current SDK per target. A replacement commit removes the old
marked entry and adds the new one; both prereleases briefly coexist.
`persist-native-sdk` only reports older `native-sdk-<target>-*` prereleases as
`NATIVE_SDK_RETIRE_CANDIDATE ... action=kept`. A maintainer retires the old
prerelease after these checks: the switch is on master, `package-tests` passes
on the new entry, and no active branch, open PR or frozen evidence still names
the old artifact ID or tag. The workflow never deletes anything. A failure
before the undraft step leaves an unpublished, untagged draft; these drafts are
reported in the job log and provenance artifact and are not purged
automatically.
