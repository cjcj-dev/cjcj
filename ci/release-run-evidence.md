# Release campaign evidence (G3/G6/G7/G9/G10)

`node ci/release-gates.mjs G3 --evidence DIR --json` consumes an archive; it
never starts a build or dispatches a workflow. Without `--evidence`, register
`{"schema":1,"gates":{"G3":"gates/G3"}}` in `GATE_EVIDENCE.json` under the
runbook's `RELEASE_EVIDENCE_ROOT`. Each gate has its own directory and binding.
The existing `EVIDENCE_BINDING.json` schema=1 applies unchanged: current checkout
head, producer repository/head plus head file, recipe file/hash, measurement
interval, and exhaustive payload SHA256 inventory. See
`ci/evidence-binding-fixture.mjs` for a small binding example. Freeze the checkout
before collecting evidence. Stale/unbound/modified evidence is UNKNOWN, not MET.

This is an evidence-consumption protocol, not a new producer or artifact verifier.
Campaign owners archive the **actual verifier exit codes and logs**, and must not
manufacture success records. Hash binding detects changed archives; it is not a
signature or a proof that a producer told the truth. Binary artifacts may remain
in the artifact store: their name, size and SHA256 are recorded here, and the
bound verifier logs attest their checks. The consumer does not rerun verifiers
against remote binaries. Fixture MET only certifies this consumer, not a release.

## Platform results

Each directory contains `G3_RESULTS.json`, `G6_RESULTS.json`, `G7_RESULTS.json`,
or `G9_RESULTS.json`, respectively:

```json
{"schema":1,"gate":"G3","records":[{
  "id":"linux-x64/linux_x86_64_cjnative",
  "checks":{
    "producer":{"rc":0,"log":"logs/source.log"},
    "assertFinalStd":{"rc":0,"log":"logs/final-std.log"}
  },
  "artifacts":{"final_std":{"name":"final-std.tar.gz","bytes":1234,"sha256":"<64 lowercase hex>"}}
}]}
```

Log paths are payload inventory keys. Each check requires an integer rc and a
bound log. Artifact descriptions require a nonempty name, positive integer byte
size and SHA256. Records must be unique and exactly cover these axes:

| Gate | Record id | Required checks | Required artifacts |
|---|---|---|---|
| G3 | `<release key>/<std tuple>` | producer, assertFinalStd | final_std |
| G6 | LLVM platform | producer, manifest_pin, llc_sha, opt_sha, llc_version, opt_version, shim | llc.gz, opt.gz, manifest, shim |
| G7 | release key | archive_manifest, clean_stamp, artifact_sha | archive, manifest |
| G9 | release key | package, smoke, checksums; darwin_lto on Darwin hosts | archive, manifest, checksums |

The axes come from **every** `allReleasePlatforms()` row in `build/lib/targets.mjs`:
G3 uses each host runtime tuple plus cross tuples; G6 deduplicates LLVM platforms.
Blocked and excluded rows remain required by the full-platform release policy;
readiness is diagnostic and cannot exempt evidence. Existing workflow job checks
still validate exactly the buildable jobs. With no result file, ordinary missing
evidence is UNKNOWN; if any platform is blocked it is NOT_MET. In a result file,
a missing/duplicate/unexpected platform or tuple is NOT_MET. Missing check,
artifact metadata or log is UNKNOWN with `missing=` naming it. A nonzero verifier
rc is NOT_MET and names the record/check. Known failures take precedence over
incomplete evidence. MET requires all records, checks and artifact metadata.

A `smoke` record means the **entire** `ci/smoke/run_smoke.mjs` batch finished;
`checksums` means all outward files passed `ci/release/package_checksums.mjs`;
`artifact_sha` means all artifacts in the archive manifest were checked, not a
sample. `clean_stamp` means one clean lineage stamp across the packaged set.
`manifest_pin` and SHA/version checks use `ci/llvm-tools-manifest.mjs` and the
frozen LLVM pin. `assertFinalStd` is the existing source final-std verifier.
The recipe and logs must identify these actual commands and full inputs.

## G10 (producer #725)

Consume `ci/g10/run.mjs`'s `G10_RESULTS.json` schema=1 without translating it.
The top level contains `gate`, `head`, `arms`, `corpus`, `records`, `status`,
`failures`, `not_run`, `injection`, `skipped_who`. Both official/selfhost arms
must be `ran` with compiler SHA256 and runtime/boundscheck SHA256. The corpus
must contain at least 50 unique ids, source SHA256 and expected_rc=0. Per arm:
20 version records (`invoke`), 20 compile records (`compile` and `run`), and one
crashsweep record per corpus id (`compile` and `run`). Non-version records need
source and ELF hashes; crashsweep source must match its corpus entry.

Every step must explicitly report rc=0, signal=null, error=null, timed_out=false,
skipped_who=0, signature=OK. Missing fields/records/identity or NOT_RUN are UNKNOWN;
failed steps, duplicate/unexpected records, nonzero skip or injected corpus are
NOT_MET. Raw records override an incorrectly green summary. Nonempty summary
failures or NOT_MET also reject; UNKNOWN cannot be upgraded to MET. All missing
and failed points identify arm/phase/id/step. G10 remains unqualified when the
selfhost arm has not run; these fixture tests make no claim about compiler health.

G11's #482 two-arm protocol and evaluator belong to #726 (`ci/release-g11.md`);
this change does not define a second G11 interpretation.
