# Frozen SDK consumer inputs

The shell/Python compatibility entries retain their public names and test
registry settings. The SDK consumers execute `sdk_build.sh --plan … --to …`,
and bootstrap phase consumers execute `bootstrap-sdk.mjs --plans … --phase …`.
There is no loose `--from`/`--std`/`--llvm-tuple` assembly route.

All entries require a private `SDK_MANIFEST_TEST_ROOT`, private `TMPDIR` and an
already provisioned `SDK_SHAREDBUILD_ENGINE`. The qualifier
`prepare-sdk-test-inputs.mjs` checks the actual private tools checkout at commit
`662b51ce8e4337a5fb034ed8d2cf46e1de26eb00`, tree
`5bbb4acfbdfaf4ebf02d9a8b3204ca44a7545489`, including HEAD, tree, clean status and
`ts/src/sharedbuild/main.py` path. It qualifies this supplied entity; it does not
supply or download an engine.
Supply a complete, clean private checkout of this fixed candidate; its engine
entry is `ts/src/sharedbuild/main.py`. An older retained checkout does not
qualify this combination or provision its dependencies on an execution host.

For subsequent authorized private execution, use that fixed tools entity and
its existing `main.py` transport (`transport` at lines 629–641): the engine
physically sends its own entry to `/root/<lane>/sharedbuild-engine-<digest>.py`
via the existing box, then invokes `--remote` under the existing resource broker
for builds. The SDK fixture's producer repository identity still names the
actual fixed Git checkout. A lone transported Python file is not a replacement
for the checkout required by the input qualifier or fixture. No source SHA is
invented, no engine is copied into cjcj, and no HEAD/tree verification is disabled.
The retained private checkout/transport and native dependencies must be prepared
under an explicit later execution contract. This document does not authorize
transport, deployment or execution.

GHA has no reviewed engine supply source. Its existing qualifier steps remain
an unsatisfied prerequisite; merely adding `SDK_SHAREDBUILD_ENGINE` to an
environment is insufficient. Do not guess a tools repository URL or download
an engine. Hosted-runner CPU eligibility for the fixture's complete sharedbuild
plan must also be checked: plan jobs currently require at least 64. The private
kkk2 route and GHA supply/qualification are separate unfinished work.

The native dependency qualifier now includes the commands used by the migrated
bootstrap contract (including npx, rsync, readelf, strings and c++filt). The
existing source module, bootstrap and SDK identities must travel together.
`vendor_contract.mjs` checks the new cjcj-owned consumer modules against the
actual checkout commit along with the historical shell entry. Historical
TOOLS import records retain their original meaning; new native consumers have
no invented upstream import record.

## Tuple permissions

`test_tuple_permissions.py` delegates to the tuple suite. Its two public test
names are retained: `test_tuple_tools_execute_after_install` and
`test_executable_tuple_control`. The genuine native fixture emits llc/opt/ld.lld
as 0644 or 0755 before sharedbuild seals its original artifact inventory. The
cjcj adapter retains that source mode and byte digest, grants execute bits on
its physical output and seals its own final output receipt. The unique assembler
installs that receipt's bytes/mode. The installed-byte/execute assertion runs
before success/provenance assertions, including when assembly refuses to publish.
This is a consumer and adapter contract, not compiler correctness evidence.

## Real SDK runtime/std arms

Supply all six options together to `test_sdk_runtime.py`:

- `--real-coloured-sdk` and `--real-official-sdk`: explicit retained SDK entities
  containing their original plan, manifest and lock;
- `--real-coloured-plan`: full target plan selecting coloured runtime/std;
- `--real-official-plan`: full host plan selecting official runtime/std;
- `--real-official-std-plan`: full target plan selecting coloured runtime and
  official std (expected STD-RUNTIME-COLOUR-MISMATCH);
- `--real-coloured-std-plan`: full host plan selecting official runtime and
  coloured std (expected STD-RUNTIME-COLOUR-MISMATCH).

These are existing complete frozen plans with their original successful producer
receipts, not plans derived or fabricated from a raw SDK path. Admission reads
and authenticates each original receipt with `readOutput` and computes the
install map with `resolveFiles` before starting the assembler. Missing receipts,
SDK members or options fail input preparation and are NOT_RUN, never SKIP/PASS.
The selected runtime pair/archive and complete std/FFI/module set must match the
requested SDK's original bytes, source identity, build ID and receipt digest.
The real SDK's plan/manifest/lock binding is also checked. Normal arms run full
assembly and both verifiers; mixed arms must reach the exact std colour refusal
with the non-target inputs valid. No real SDK is produced to fill missing inputs.
The independent host/colour rulers must match the two explicit SDK entities.
Original std-producer provenance must match the selected compiler before
assembly, including mixed arms; it is never rewritten to manufacture this
precondition. A missing compatible original compiler/std receipt is a NOT_RUN
input blocker, not the expected colour rejection. Selected source SDK entity
types, modes and directory member sets are admitted explicitly as well.

## Bootstrap public contracts

`test_bootstrap.sh` is a thin entry to `bootstrap-consumer-cases.mjs`. Its original
public cases remain. The dry fixture uses real small native producer outputs and
a complete eight-phase bundle. The phase entry's dry results are compared against
the selected complete plan's producer build IDs, directories and dependencies.
The same five reached phases also use the normal bootstrap phase CLI: its
successful installed manifest is compared with the original authenticated
producer receipts, and initial/second std installed module bytes must differ.
Computed dry identities alone are insufficient for this assertion.
The logged bootstrap call order distinguishes stage1-initial from stage1-std,
with separate std generation recipe identities. The release and forensic actual
command arguments, source isolation, O1 transform, declared source changes,
HOME/TMPDIR isolation, compiler selection and five EXIT receipts remain explicit
assertions. Special-path std tests observe original producer bytes at both a
source build root and SDK destination containing spaces and square brackets.

Old runtime directory discovery has been replaced by explicit frozen install
mappings. Flat/nested sources preserve real pair/archive ownership. Ordinary
runtime alias inputs go through the real publisher's authenticated contained
alias materialization, then a native producer consumes those exact dependency
bytes. Dual-layout refusal now observes duplicate declared destinations after
producer receipts, rather than guessing a winning directory. The public old
case names are retained; this semantic mapping needs independent review and
actual target/cut/restoration evidence. The child rc=1 propagation arm proves
only the apparatus's propagation of a real failing child, not SDK correctness.

Every changed/new consumer is NOT_RUN under the current source-only contract.
Syntax parsing and source mapping do not establish equivalence, complete
behavior qualification, an effective causal cut, or any platform/native/std/
stage/SDK/final strict parity acceptance.


# Official source admission (#927 paired candidate)

The tools publisher and this resolver use the same
`build/lib/official-sdk-identity.mjs` contract, backed by the existing platform
release pins and cjc version parser. Original archive bytes, complete logical
payload and actual cjc version are verified before publication/copy and before
accepting any cached or prior successful official receipt. The receipt retains
`execution.officialIdentity` and the original verbatim/read-only
materialization. Embedded installed receipts validate the pinned proof; installed
admission also consumes the actual original official receipt and payload.

An old receipt or lock without that proof stays historical and is rejected.
Regenerate a new identity through the normal private publisher/producer and
propagate dependency IDs; never amend old output/DONE/mtime or swap a label.
The sharedbuild adapter emits an explicit original-archive request and a
trusted verifier policy from its pinned cjcj producer, then includes the policy
in the real build recipe. Supply this paired checkout on the host. Directory
keys, repeated lock labels, and LLVM/LLDB versions cannot establish an official
SDK release. Full SDK, ABI, STD_CJC and loadability qualification remain required
by their existing owners and are not established by the small identity fixture.

The established `nightly-` installation prefix is normalized by the existing
release contract; the exact request is also bound in `requestedVersion`. An
alias for a different release is still rejected.

## Retained real official fixture input

Also supply `SDK_OFFICIAL_PLAN` (or `prepare-sdk-test-inputs.mjs --official-plan`)
with a normally frozen, one-component plan for the real
`1.3.0-alpha.20261009001050` distribution. Its existing source, archive proof,
version and lock binding remain intact. The qualifier exports that plan path
alongside the fixed engine and private roots. It only qualifies the input
metadata; it does not mint a proof or qualify SDK payloads, colour, ABI or stages.
The original distribution and lock are read-only, including when their lock is
outside the distribution root.

`fixtures/sdk-plan-fixture.mjs` retains that source directly and freezes its
native fixture plan through `freezeSdkPlan`. The actual official producer still
performs full source/copy authentication before sealing; sharedbuild publishes
its private host dependency with the product's genuine identity request. The
native compiler, runtime, LLVM, std and AST fixture archive are produced by the
ordinary native recipe, not inserted into an official release. These small
native results do not qualify a complete compiler, native capsule or SDK.
`fixtures/sdk-consumer-fixture.mjs` uses the same official request and version;
its label only names private cache and evidence files. Directory/layout callers
likewise retain the release version rather than invent a publisher tag.

The old `prepareOfficial` callbacks modify the official payload (additional
std/FFI/tuple/runtime members or synthetic runtime aliases). They cannot borrow
1009's proof. Preparation reports `SDK_FIXTURE_NOT_RUN` before invoking those
callbacks or compiling their native inputs. Their original assertions are kept.
A later execution must provide a legal non-target input contract; an early
identity rejection does not exercise any of their original target assertions.
The following other cases also remain NOT_RUN, with their existing assertions:

| Existing target | Missing legal prerequisite |
| --- | --- |
| Consumer swap and input-layout source cases | Replacing official cjc/cjpm or adding bin/linker does not match the original archive. |
| Directory closure and added empty directories | The synthetic tools/empty/leaf layout and its chosen modes are not in the retained archive. |
| Legacy file/directory aliases | Added cjpm aliases and the compiled alias dispatcher are not original archive entities. Real cjdb alias tests are a separate official input domain. |
| Historical unmarked and marked layout consumer controls | A hand-authored historical lock without the real official proof cannot serve as a successful official control. Marker assertions require independent legal input qualification. |
| Stage1 small ELF/domain observer | The original controlled-official cjc/cjpm/HOST library and `DOMAIN=HOST` observations are incompatible with a genuine official release. The observer only forwards genuine version/archive/request inputs; it supplies no replacement proof. Keep the original stage1 assertions pending instead of accepting an identity refusal as their result. |

Source preparation alone does not authorize any of these domains or their
payload copies/builds. In the #942 one-GiB contract only the original official
host selector and small input/plan/source preparation are admitted. Native,
full host/target SDK, alias/payload three-arm production and this qualifier's
causal validation need their corresponding explicit execution/resource scope.

## #942 bounded fixture closure and private source-mode rework

The new rework window supersedes the preceding one-GiB execution scope only for
the explicitly authorized representative chains. It does not qualify the whole
SDK package or authorize any of the other pending input migrations above.

The ordinary small fixture retains the full authenticated official component
as its build dependency. Its installation projection excludes `bin`, `lib`,
`runtime`, `modules`, `third_party`, and now `tools/bin/cjdb`. The first five
roots are replaced by the same genuine small native recipes as before; the
last entry is a newly inherited real-release debugger alias pointing at the
excluded `third_party/llvm/bin/lldb`. The old synthetic fixture had no such
alias and none of its original consumers requests cjdb/LLDB. It still retains
`envsetup.sh`, cjpm, tools support libraries and other unchanged root members.
Its native LLVM recipe produces llc/opt/ld.lld and its LLVM library; it does not
produce LLDB. This projection is exclusive to `sdk-plan-fixture.mjs`. The
separate complete official payload, official alias and real cjdb suites retain
their complete install declarations and strict link verification.

| Installed inputs | Old small fixture / real release migration | Rework and transitive consumers |
| --- | --- | --- |
| envsetup, tools/bin/cjpm, tools support | retained | retained; assembler load/version checks and sdk-consumer nativeChecks |
| official bin/lib/runtime/modules/third_party | excluded | unchanged native compiler/runtime/std/LLVM outputs; sealed recipe dependencies still use the full official component |
| tools/bin/cjdb -> ../../third_party/llvm/bin/lldb | absent in original small fixture; inherited by real release migration with target excluded | excluded only from this small installation; no original small consumer; full official/cjdb tests remain complete |
| lib/tuple/libcangjie-ast-support.a | native AST recipe in migrated fixture | unchanged cc/ar recipe -> sharedbuild receipt -> frozen install -> host assembly -> both verifiers -> bootstrap AST read |

The changed-source-mode case requests `fixture({privateOfficial: true})`.
Before freezing, the fixed sharedbuild publisher authenticates the original
source/archive and creates an owner-local physical read-only copy plus its new
lock. The publisher's ordinary `copytree(..., symlinks=False)` materializes
aliases and creates files independently; no source hard links or directory
symlink surrogate is used. The fixture's new frozen source/root/lock binding
then passes the normal complete assembly before a private cjpm mode change.
The consumer checks physical containment and file identity before mutation,
and observes the retained cjpm content/mode/mtime and retained lock during the
mutation and after restoration. The target requires rc=1 and the precise
`OFFICIAL_IDENTITY official archive payload mismatch: tools/bin/cjpm mode
expected=... actual=...` diagnostic, with no installed output and unchanged
locks. This tests unauthorized release mode changes before success sealing;
it does not bypass full identity to reach the later DISTRIBUTION_FILE check.
The verifier now reports the differing payload attributes without changing
its comparison, accepted identities, archive pins or proof format.

The saved successful component directory and chmod are protected by the same
exception scope. A failed new attempt is preserved under `-mode-rejected`;
the original successful directory is restored at its original identity path.
Restored assembly uses that original binding and cache honestly, rather than
calling the restored output a fresh production. No shared source, original
lock/proof/archive or other lane record is amended by this case. Dynamic normal,
cut and recovery evidence remains required; source and syntax checks alone do
not establish that either verifier or the bootstrap AST consumer ran.
