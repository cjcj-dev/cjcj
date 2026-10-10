# Frozen SDK consumer inputs

The shell/Python compatibility entries retain their public names and test
registry settings. The SDK consumers execute `sdk_build.sh --plan … --to …`,
and bootstrap phase consumers execute `bootstrap-sdk.mjs --plans … --phase …`.
There is no loose `--from`/`--std`/`--llvm-tuple` assembly route.

All entries require a private `SDK_MANIFEST_TEST_ROOT`, private `TMPDIR` and an
already provisioned `SDK_SHAREDBUILD_ENGINE`. The qualifier
`prepare-sdk-test-inputs.mjs` checks the actual private tools checkout at commit
`629d2f5bf3deb8df90e9c9e155a8f914c7d6c801`, tree
`cebdae8acc5349a285ddc5f0f605aa64b1909ca9`, including HEAD, tree, clean status and
`ts/src/sharedbuild/main.py` path. It qualifies this supplied entity; it does not
supply or download an engine.
The currently retained private checkout is
`/root/cj_build/tools_wt/sym_cjcj_934_implement_r6098289478`; its engine entry is
`ts/src/sharedbuild/main.py`. Local existence does not provision that checkout
or its dependencies on a later execution host.

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

## Bootstrap public contracts

`test_bootstrap.sh` is a thin entry to `bootstrap-consumer-cases.mjs`. Its original
public cases remain. The dry fixture uses real small native producer outputs and
a complete eight-phase bundle. The phase entry's dry results are compared against
the selected complete plan's producer build IDs, directories and dependencies.
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
