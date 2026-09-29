# G10 runner and crashsweep corpus

Run on Linux x86-64 with Node 20.19+ and two complete SDKs. Each SDK must already
have the compiler, standard library and runtime appropriate to its arm. This
runner does not assemble SDKs or substitute runtime libraries.

```sh
ulimit -c 0
node ci/g10/run.mjs \
  --official-sdk /absolute/official-sdk \
  --selfhost-sdk /absolute/final-selfhost-sdk \
  --head "$(git rev-parse HEAD)" \
  --out /absolute/new-evidence-directory
```

`--jobs N` controls concurrent subprocesses (default: available CPUs).
`--timeout MS` bounds each invocation (default: 120000); a timeout kills its
process group and is a failure, with no retry. Each invocation has its own work
directory. Both arms use the same cases and command recipe: 20 `--version`
invocations, 20 compilations and executions of `minimal.cj`, then 50 distinct
crashsweep compilations and executions. Successful executables are removed after
hashing and execution; failed artifacts and all logs remain. Outputs must not
already exist. Set the core limit to zero before invoking the runner.

The 50 checked-in programs are newly authored valid-program negative controls,
not a reconstruction of the unavailable 0809 temporary corpus. They cover scalar
operations, branches/loops, calls/recursion, tuples/arrays, strings, numeric
conversions, closures, generics, classes, structs, enums and options. Each returns
zero only when its result assertion holds. `controls/panic.cj` is an unhandled
exception control, excluded from the normal corpus. `--inject 17_recursion`
replaces exactly that case in **both** available arms; its compiled program must
fail and the report must name its arm, phase, ID and failing step.

For explicitly unavailable infrastructure, use `--selfhost-not-run REASON`
instead of `--selfhost-sdk`. It writes `arms.selfhost.status=NOT_RUN` and cannot
produce MET. This supports the #135 dependency; it is not a release exemption.

## Producer/consumer contract for #722 (D1)

`G10_RESULTS.json` has `schema: 1`, `gate: G10`, `head`, `arms`, `corpus`,
`records`, `skipped_who`, `measurement`, `status`, `failures` and `not_run`.
`arms.official` and `arms.selfhost` contain SDK/compiler paths, compiler SHA256,
runtime and boundscheck SHA256, or a NOT_RUN reason. Each record identifies
`arm`, `phase` (`version`, `compile`, `crashsweep`), `id` and relative `directory`.
Version records have `invoke`; other records have `compile`, and `run` only if a
real ELF was produced. Source/ELF SHA256 values are captured before execution.
Each step records argv, rc (null for a signal or launch error), signal, launch
error, timeout flag, signature, SKIPPED_WHO count, wall time and log filename
(relative to the record directory). Aggregate SKIPPED_WHO sums all step counts.
Both `SKIPPED_WHO=N`/`SKIPPED_WHO: N` aggregates and bare diagnostic markers are
recognized; `SKIPPED_WHO=0` is zero. A bare marker is one skipped operation.

`evaluate()` requires every expected record exactly once and every required step
successfully executed with rc=0, no signal/error/timeout, no skipped WHO and a
produced ELF for compilation. Any observed failure yields NOT_MET with the
specific arm/phase/id/step. Otherwise missing infrastructure yields UNKNOWN;
only complete successful two-arm execution yields MET. CLI exit codes are
0=MET, 1=NOT_MET, 2=UNKNOWN/setup error. NOT_RUN is never counted as success.

The evidence directory includes `recipe.json`, `producer.txt` and the existing
release-gates `EVIDENCE_BINDING.json` schema: gate/head, recipe hash, producer
HEAD, measurement interval, and exact payload SHA256 inventory. Keep the archive
unchanged. `--head` is the caller's frozen checkout coordinate; binary identities
are independently recorded and **not** inferred from that SHA. D1 owns the
release-gates evidence consumption and final apparatus qualification. This
runner's status alone does not certify that an arbitrary SDK is the final SDK.

## Verification

`node --test ci/g10/run.test.mjs` tests record evaluation, missing execution and
precise error localization. These are classifier unit tests, not compiler
acceptance. Compiler acceptance must run the command above with real SDKs and
check the full per-case records. Injection and restoration must use the same
runner and SDK bytes, with a separate fresh output directory for each arm.
