# New Apple input admission apparatus (#906)

Coordinates: source fixture `e121383180798b3601de66c9a1f0d1b9dc3d3081`,
immutable preparation/identity input `845a2d7eee50868f04eb29f848c18964f15af2fa`,
main `227b34ad4c1b78b3eebfe0605570d6d8b398e579`.

These zx ESM entries are private admission apparatus. They do not run clang,
cjpm, a native fixture, or an observer. The pinned legacy Python validators
remain immutable inputs, checked against `legacy-pins.json` before each call.
Materialize its four files in a private directory from the pinned Git object;
materialize the source inventory at the fixture pin in a separate directory.
Do not copy a whole old candidate into main or overwrite historical calibration.

`zx capture.mjs spec.json new-capture.json` materializes a separately authorized
collection's original dependency, layout and tool outputs. `spec` supplies the
absolute `apple_sdkroot`, `dependencies_path` (original clang `-M` output),
`layout_path`, `layout`, `tools` (`clang`, `xcrun`, `xcodebuild` absolute entities),
`xcode`, `sdk_version`, `batch`, `started_at`, `finished_at`, full nested `argv`,
collection `environment`, and `raw_outputs` paths. The record preserves the
original capture fields, resolved root, SDKSettings, recursive SDK header
closure, external dependencies, tool entities and original-output hashes.
Collection itself needs a separate runner/tool/command/deadline authorization;
materializing synthetic inputs is not proof of a genuine SDK collection.

`zx prepare.mjs source output inputs.json legacy-directory new-capture.json`
uses the real pinned prepare entry, including complete source/SDK/environment
validation, then binds the new capture and actual recipe `clang -isysroot` to
one `apple_input`. No Mach-O or BUILT receipt is required. Every prelaunch
repeats the pinned source/tool/SDK checks and rereads capture/settings/headers/
dependencies/layout/Xcode tools from disk, comparing them to both the capture
and the prepared consumption manifest.

`zx first-build.mjs recipe.json authorization.json legacy-directory step`
validates one step and returns `AUTHORIZED_BOUNDARY_NOT_LAUNCHED` with the actual
argv, environment and Apple manifest. Authorization is deliberately
`offline-launch-boundary`, with count=1, source_head, recipe_sha256,
input_manifest_sha256, new_batch_id, absolute_deadline_epoch, and
archive_reserve_seconds >=30. This module has no native/compiler dispatch.
Calling it repeatedly is validation, not a counted build authorization.
The original `first_build.py` is not an approved alternative launcher.

`node offline-batch.mjs new-private-output materialized-input` is the explicit
five-recipe synthetic batch, not a public CI test. It exercises normal admission,
same-version wrong root, post-prepare header mutation, actual consumer-call cut,
and restored admission. The consumer cut invokes the same assertion in a child
Node process and preserves its true nonzero rc. Normal and restored traverse
both generated step boundaries. Synthetic SDK transport pin substitution is
restricted to the labelled import API; CLI preparation has no such override.
No tests fabricate a BUILT receipt or qualification approval.

Historical `apple_headers=null`, original layout and qualification null are not
changed. These results qualify apparatus relationships only. Actual SDK capture,
first compilation, three-package bridge, selected source/std closure, no-LTO,
unique Create and loaded-runtime proof remain NOT_RUN. Before any real build,
hash verification and artifact archival must fit the absolute deadline, with
remaining timeout/reserve and exact child/descendant ownership and timeout
cleanup proved under a separately authorized short-child budget. TIMEOUT rc
and LAUNCH_ERROR errno must be retained. None of those process-management
capabilities is claimed or tested by this zero-product-execution package.

`node producer-batch.mjs new-private-output materialized-input` is the separate
four-recipe producer supplement: cut the capture's pre-write snapshot call,
restore and verify required-header rejection plus both legal launch boundaries,
then reject Settings drift and tool/raw-output drift. The last recipe uses one
prepared manifest with two independently restored entity mutations (xcrun and
raw output); it never launches. The cut runs the same producer-target assertion
in a child process and saves its original rc and emitted manifest. This is a
candidate-new-line apparatus cut, not a frozen-main product cut. Its scope is
synthetic relationship qualification only; historical calibration remains intact.

A1 repair: a new capture
requires `consumer.source` (absolute actual helper path), `consumer.argv` (the
clang compilation argv without sccache), `consumer.cwd`, `consumer.environment`,
and collection `cwd`. The original dependency invocation must equal that compile
argv with `-c` replaced by `-M` and the output pair removed. Source bytes must
appear in the dependency output and match the generated recipe's helper; all
remaining options, clang identity, cwd and environment must match consumption.
The old probe-based offline fixtures are incompatible and cannot qualify this
repair. No guessed list of additional header names is used.

For genuine collection using the prepared cwd, call `prepare(..., null)` to
materialize the pinned source and recipe without Apple admission. Under a
separate collection authorization, collect dependencies of that recipe's actual
helper with its compilation options and environment. Then call
`bindPrepared(recipePath, capturePath, legacyDirectory)` to validate the pinned
recipe again and bind the capture. An unbound recipe has no header_capture and
cannot pass the first-build entry. This permits collection before the first
compilation without a Mach-O or BUILT receipt. This two-stage path has not been
executed in the exhausted nine-recipe contract.

`node consumer-batch.mjs output materialized-input` is a six-recipe private
consumer supplement using the pinned helper and a recipe produced by real
`prepare(..., null)` then `bindPrepared`. Set `APPLE_BATCH_DEADLINE` to the
contract's absolute epoch. It tests admission, pthread.h byte drift and recovery,
a legal HOME change and recovery, and a candidate-new-line consumer cut with
the same target module. Every successful admission reaches both launch boundaries.
The tools, SDK, layout and dependency output are explicitly synthetic; the list
is derived from this helper's direct includes and is **not** a clang dependency
collection. This batch establishes apparatus causality only. It cannot establish
that the actual compiler dependency closure was collected or that an Apple build
works. No compiler or native target is dispatched. Cut restoration checks bytes;
there is no seventh post-cut execution under the six-recipe allowance.

The private `apple_input` dispatch option in `verify-darwin-runtime.yml` runs
`zx darwin-batch.mjs` on the authorized official macOS carrier. Existing workflow
calls and ordinary dispatches retain the published-runtime jobs. `green` runs one
admission; `controls` runs SDK pthread.h drift, restoration, a valid HOME change,
and restoration. The collector copies actual SDK header bytes into a private root,
prepares the fixed helper, runs its exact preprocessing command with clang `-M`,
and collects clang record-layout output without compiling or running a native
binary. Full official Cangjie archive transport and the immutable legacy validators
remain in use; no synthetic SDK substitution is made. Each failure preserves its
original command rc/signal/errno and stops dependent work. Results only qualify
admission and never qualify a native build.

`pinned-inputs.tar.gz` contains the four byte-identical legacy inputs from local
845a and the source inventory from e121, identified by `legacy-pins.json` and the
immutable frozen inventory. The Git objects are not assumed to be available from
remote checkout. Materialization does not update those originals. New capture
and original stdout/stderr, actual argv/environment/cwd, runner identity, consumed
headers and receipts are uploaded as evidence. The job requires the frozen
Xcode 16.4 (16F6) / SDK 15.5; a runner image lacking it stops before product entry,
without accepting a different tool identity. Layout evidence is newly collected;
historical header null, layout and qualification records remain unchanged.
