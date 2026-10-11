# #934 remaining causal source preparation

This prepares tests only. It grants no execution permission. The preparation
base is cjcj `892c3abf035db61cb4e67ed1633292d7c6fed097`, tree
`9945087c5a316f206d82b16d7e0d9a7c38822d4e`; the read-only tools input is
`629d2f5bf3deb8df90e9c9e155a8f914c7d6c801`, tree
`cebdae8acc5349a285ddc5f0f605aa64b1909ca9`. All dynamic arms remain NOT_RUN.
Original resource, input, SDK, ABI, independent review and release holds apply.

## Actual entries and affected consumers

The task's directory-closure and layout-consumer names resolve to
`sdk-directory-closure.integration.mjs` and
`sdk-layout-consumers.integration.mjs`; the bootstrap fixture is under
`fixtures/`. `ci/test-registry.json` registers both integrations as manual and
registers `test_bootstrap.sh`, whose only command execs
`bootstrap-consumer-cases.mjs`. The latter imports the bootstrap fixture.
`vendor_contract.mjs` authenticates both changed bootstrap modules.

These source queries derive the direct entries and indirect candidates:

```sh
git diff --name-only 892c3abf035db61cb4e67ed1633292d7c6fed097..HEAD
git grep -n -E '(bootstrap-consumer-fixture.mjs|bootstrap-consumer-cases.mjs|sdk-directory-closure.integration.mjs|sdk-layout-consumers.integration.mjs|test_bootstrap.sh)' -- ci build .github
rg -n '^test\(|^  .check-(phase-results|dry-contract|std-compiler-identity).|qualifyBootstrapPhases|phaseIdentities' ci/bootstrap/sdk-directory-closure.integration.mjs ci/bootstrap/sdk-layout-consumers.integration.mjs ci/bootstrap/bootstrap-consumer-cases.mjs ci/bootstrap/fixtures/bootstrap-consumer-fixture.mjs
```

Classify actual calls separately from documentation and quoted strings:

| Source edge | Affected obligation |
| --- | --- |
| registry → directory integration → real `sdk_build.sh` | Full three-test directory suite, both original verifiers and ordinary-final control |
| registry → layout consumer integration → actual tools `build --recipe` | Full consumer suite, including three new marker/history/metadata tests |
| `test_bootstrap.sh` → cases → fixture `phaseIdentities` | `check-dry-contract` and full `test`, which calls it; new `check-phase-results` filters |
| segmented-workflow test → `test_bootstrap.sh dry-run` | Indirect fixture/module-closure preparation; its three existing phase cases remain |
| vendor contract → changed bootstrap modules → srcbuild vendor tests | Original blob/content identity checks remain required |
| Android workflow → `test_bootstrap.sh` | Platform/input qualification remains; local micro fixtures do not qualify Android |

The grep output is a source-derived candidate set, not a Q62 automatic complete
execution closure. No lightweight check replaces the full existing entries.

## Subsequent normal, target, control, cut and restore arms

Only after separately authorized input/resource admission, invoke the existing
entries in an exclusively owned Linux workspace. Use the fixed complete tools
Git checkout, genuine native fixture producers and original receipts. Preserve
argv, child rc/signal, stdout/stderr, input identities and all failures.

| Mechanism | Normal / target | Independent control |
| --- | --- | --- |
| Authenticated empty directories | `node --test --test-name-pattern='^real final SDK preserves authenticated empty directories and readonly source modes$' ci/bootstrap/sdk-directory-closure.integration.mjs` | Same entry filtered to `^ordinary final SDK remains the independent control$` |
| Marked lock lacking layout | `node --test --test-name-pattern='^marked SDK without source layout reaches the public recipe consumer rejection$' ci/bootstrap/sdk-layout-consumers.integration.mjs` | Separate filters `^historical unmarked file-only SDK remains a legal public recipe consumer control$` and `^publisher reserved metadata remains excluded in the public recipe consumer control$` |
| Selected phase installs its producer result | `bash ci/bootstrap/test_bootstrap.sh check-phase-results stage1-initial` | Independent command `bash ci/bootstrap/test_bootstrap.sh check-phase-results stage1-std` |

Normal marker target requires child rc=1 and exactly
`SHAREDBUILD_ERROR SDK_LOCK_REJECT missing source layout`. A cut that removes
the actual consumer guard must make this target assertion fail because the
actual CLI accepts the otherwise qualified input. Both legal controls must
still succeed; arbitrary nonzero, loading failure or earlier seal rejection is
not evidence. The publisher control also reads the actual emitted marker and
layout after real recipe consumption. Its reserved names must stay absent from
payload membership.

`historicalSdk` constructs a separate, legal historical-format file-only input
from genuine published payload bytes. It is explicitly synthetic historical
format, not an original retained historical producer result. Its lock and
MANIFEST/DONE authenticate its standalone input bytes, including the malformed
marked variant. It creates no `output.json`, successful execution record or
producer receipt. The original plan, distribution, recipe and receipts stay
unchanged. Actual new recipe results can only come from the public tools CLI.

Empty-directory observation saves the real assembly result, authenticated
receipt, resolved manifest, final metadata, artifact/installed lstat results
and retained staging observations before assertions. Source type/mode and
receipt qualification remain strict. A nonzero assembly is routed to the empty
target only for the specific directory path with a PAYLOAD directory diagnostic
or ENOENT stat/lstat/chmod; other failures have a separate qualification failure.
The target still demands complete producer-to-install preservation, including
normal assembly success afterward. Staging observations never substitute for
successful installation. Both verifiers and the original provenance/member
assertions remain after the preservation target.
For producer/installation cuts, leave `SDK_DIRECTORY_EXISTING` unset so the
actual assembly runs in every arm. The existing reuse option is retained for
observing an already completed input and its verifiers; evidence now identifies
that origin explicitly as `retained-assembly`. It is not current assembly
causality, even if its preservation assertion passes.

Before any selected-phase target, the direct `toolchain-sdk.mjs` CLI completes
both legal phase plans. `readOutput` authenticates their actual original receipt
bytes, DONE, recipe/component/dependency/source identities. Installed std bytes,
compiler bytes and original std-producer compiler lineage must agree. Plans and
receipts are not relabelled or edited. The selected-phase normal result enters
the plan/std build ID/std bytes/compiler bytes/STD_CJC target before dry-run
assertions. Failure of a legal direct control, including STD_CJC, stops that
mechanism as a contract/input contradiction with original output preserved.
Missing receipt or load failure never counts as phase causality.

Use a conditional phase-selector cut that substitutes the already qualified
`stage1-std` plan only for `stage1-initial`. The child must assemble normally;
the changed installed plan/std identity must cause the named target to fail.
Run the lawful `stage1-std` control separately so a red target cannot hide it.

The first normal `check-phase-results` preparation writes only an input locator
`phase-causal-input.json` under its fixture root. Reuse that exact locator with
`SDK_PHASE_INPUT` for subsequent target/control/cut/restore commands. It names
the original bundle and source; it is not a plan or producer receipt. Existing
qualification command evidence must name the exact direct CLI/plan/output;
original plan copies and qualification results must compare equal, not be
overwritten. Actual receipts and installed STD_CJC are read again. A retained
qualification is explicitly logged, never relabelled as current production.
Set a distinct `SDK_PHASE_WORK_ROOT` for every arm and `SDK_PHASE_PRODUCT_ROOT`
to that arm's private product module root. Current selected-phase assembly,
observations and dry-run records stay in that arm directory. Keep the original
fixture source/plan/receipts unchanged: changing its copied product modules
would change the compiler recipe identity and invalidate the comparison.

Each authorized cut needs its exact diff and product Git identity, unchanged
test source identity across normal/cut/restore, target failure stack and
`TARGET_ASSERTION_BEGIN` observation plus the actual assertion outcome.
`TARGET_ASSERTION_PASS` is emitted only after the assertion returns. Neither
label exists from this source-only preparation. Restore and rerun the same
target/control collection, then the source-derived affected full entries.
Do not resample already completed unrelated groups.

## Cut provenance relative to this preparation base

| Existing at frozen input | Proposed real product cut / target |
| --- | --- |
| cjcj `sdk-producers.mjs:76–84` | Official directory copy/declaration; authenticated-empty target |
| cjcj `toolchain-sdk.mjs:94–128` | Actual directory creation/mode installation; authenticated-empty target |
| tools `main.py:253–254` at fixed629d | Actual marker consumer rejection; marked-no-layout target |
| tools `main.py:231` at fixed629d | Published layout marker; emitted-marker assertion in publisher control |
| cjcj `bootstrap-sdk.mjs:23` | Actual selected plan; normal installed-phase target with lawful alternate |

These product lines already exist at this round's frozen inputs. Some were
candidate additions relative to the original081486/f625 baseline; retain that
original classification. If an experiment instead cuts a newly added test
observation/assertion/qualification line from this preparation, list it as a
candidate-new harness cut proving only the harness, never product behavior.
This round executed neither category. No product hook, counter, wrapper,
schema or invariant is added or weakened.

The historical eight patches are not a one-to-one map to valid groups:
`publisher-consumer` was invalid because an earlier file-category assertion
hid the directory target; `publisher-directory` later used the related product
cut with independent directory evidence. Preserve both original records. The
previous directory/official-mode groups now have changed test file identity;
their old result remains historical and supplies no current green arm.
Unchanged layout-contract/verifier/publisher-source/enumeration records are
outside this preparation's code impact, without promoting them to full package
qualification. The accepted892c N0 directory-mode review is unchanged.

The old checker rc=1 and SDK phase-entry registration gap remain. Do not edit
the shared checker/ops to manufacture qualification. The full six-slot real
SDK input set, original STD_CJC qualification, fixed engine/GHA inputs,
8GiB dynamic/35GiB admission, native CPU requirements and ABI/release holds
still need the controller's explicit execution contract.
