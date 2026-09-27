# Official test baseline

The same runner and `inputs.json` must be used for both SDK arms. It runs the
upstream Linux x86_64 Conformance, HLT and LLT recipes without editing tests or
adding exclusions. Runtime product gates are not part of this CI package.

Prepare private, content-hashed input copies from repositories containing the
pinned commits (preparation does not fetch or change shared checkouts):

```sh
python3 ci/cangjie-test/prepare.py /path/to/repositories /path/to/new-inputs
python3 ci/cangjie-test/run.py /path/to/sdk /path/to/new-output 192 --inputs /path/to/new-inputs
```

Run on kkk2 through `/root/cj_build/ops/bin/wf_kkk2.sh sh <lane> '<command>'`,
with `ulimit -c 0`. SDK must contain `envsetup.sh` and `bin/cjc`; its environment
is sourced in a child process. A real compilation and execution preflight must
succeed before any suite starts. Install the upstream framework dependencies
(`pexpect`, `fasteners`, native compiler, JDK, LLVM and optional SDK tools) in
the execution environment. Missing tools are recorded as failures or unrun
suites, never treated as passes. Shared SDK directories are never modified.

The worker budget is divided among three concurrent suite processes. Existing
output directories are rejected, preventing stale results from being reused.
Keep raw logs and JSON together with the normalized `cases.json`,
`failures.json`, `summary.json` and `identity.json`. Each suite records its
actual subprocess exit code and elapsed wall time. Identity includes compiler,
runtime and smoke executable hashes, source pins, CPU affinity and both uptimes.

Recipes (all from the commits in `inputs.json`):

* Conformance: `Conformance/Compiler/harness/README.md`, harness default mixed
  mode, all `test*.cj` under `Conformance/Compiler/testsuite`, 30s base timeout.
* HLT: `testsuites/HLT/configs/cjnative/linux_x64-linux_x64/basic.cfg` and
  `testsuites/HLT/testlist`. The framework README's old flat cfg path no longer
  exists in the pinned test tree.
* LLT: `testsuites/LLT/configs/cjnative/cjnative_test.cfg` and
  `testsuites/LLT/cjnative_testlist` (there is no LLT `testlist`).
* Maple: 180s per-case timeout, no retries, all result statuses emitted. Do not
  add `-pFAIL`: upstream filters JSON case records by that option too.

`PASS/PASSED` map to pass; `FAIL/FAILED/ERRORED/XPASS` to fail;
`SKIPPED/UNSUPPORTED/XFAIL` to skip; `NOT_RUN/UNRESOLVED/PENDING/INCOMPLETE`
to not_run. Original statuses are retained. Upstream list exclusions remain
part of the pinned recipe; they are not counted as executed or passing tests.
Missing or empty results produce `NOT_RUN`, unknown counts and exit 1, not a
zero-test pass. Invalid SDK/input/preflight produces exit 2. Any failed or
incomplete suite produces exit 1. Environment hints in failures are only text
matches for triage; they do not reclassify or exempt failures. Full errors and
commands remain in the raw upstream result files.

Compare two repeats with `python3 ci/cangjie-test/compare.py RUN1 RUN2 diff.json
--repeat`. Exit 1 means SDK identity, case sets or counts changed; the JSON lists
all case/status differences. Differences are observations, not automatically
classified as nondeterministic tests. For the bootstrap-versus-official
comparison omit `--repeat`; common and arm-only failure sets are retained.
