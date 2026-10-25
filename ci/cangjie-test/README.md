# Official test baseline

The same runner and `inputs.json` must be used for both SDK arms. It runs the
upstream Linux x86_64 Conformance, HLT and LLT recipes without editing tests or
adding exclusions. Runtime product gates are not part of this CI package.

Prepare private, content-hashed input copies from repositories containing the
pinned commits (preparation does not fetch or change shared checkouts):

```sh
python3 ci/cangjie-test/prepare.py /path/to/repositories /path/to/new-inputs
python3 ci/cangjie-test/run.py /path/to/sdk /path/to/new-output 48 --compiler-jobs 1 --inputs /path/to/new-inputs
```

Run on kkk2 through `/root/cj_build/ops/bin/wf_kkk2.sh sh <lane> '<command>'`,
with `ulimit -c 0`. SDK must contain `envsetup.sh` and `bin/cjc`; its environment
is sourced in a child process. A real compilation and execution preflight must
succeed before any suite starts. Install the upstream framework dependencies
(`pexpect`, `fasteners`, native compiler, JDK, LLVM and optional SDK tools) in
the execution environment. Missing tools are recorded as failures or unrun
suites, never treated as passes. Shared SDK directories are never modified.

The worker budget (default 48, range 4 through 48) includes four pools: Conformance compilation
and execution, HLT, and LLT. At 48 this means 12 workers per pool.
`--suites Conformance,HLT,LLT` restricts the run to a subset; selected suites
split the full worker budget (a single suite gets all of it, Conformance split
evenly across its two pools). The runner refuses to start when load1 exceeds
200 or the output filesystem has under 8GiB free, and appends load/disk samples
to `load-monitor.log` once a minute while running.
The runner enters a synchronous systemd scope using the caller's actual process
CPU affinity and the tightest CPU quota across its cgroup ancestors, capped by
that affinity. It checks the requested bounds again before creating the scope
and checks the actual child bounds before any suite starts. Finite parent memory
and swap limits also carry into the new scope. A four-CPU caller
therefore stays within four CPUs; there is no 96-CPU minimum. The scope is stopped
when the caller exits or receives a termination signal. No SDK executable or
explicit test jobs argument is rewritten. CPU selection/validation lives in
`envelope.mjs`; the Python adapter retains its Linux parent-death and signal hooks.
`--compiler-jobs` accepts 1 or 2 for Conformance's compiler flags. Maple uses
the upstream compiler options, including diagnostic and explicit jobs tests.

Verified pinned inputs are copied to `execution-inputs` in each output. Only
three scheduling entries are adapted: Maple `run_commands`, Conformance
`DriverManager.do_compile` and `do_execute`. Each waits while load1 >160,
before starting the upstream timeout clock; `admission.jsonl` records pause
and resume with the case identity and observed load. Active cases drain.
The copied Conformance reporter also deletes each passing executable after
recording its result; Maple already removes passing case work directories.
Failure artifacts and original input files are retained. Adapter hashes are
part of the comparison identity. No test source, assertion or exclusion list
is modified. `verify_admission.py INPUTS SDK NEW_OUTPUT` exercises the actual
upstream entries with controlled load readings in the fixture's Python
processes; it never creates host overload.

Existing
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
* Maple: 180s per-case timeout, default zero retries, all result statuses emitted.
  Omit `--retry`: upstream rejects an explicit zero despite its zero default. Do not
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

Each suite also writes `environment-failures.json`: the failed/unrun cases
whose output matched an environment signature (`No such directory:`,
`can not find package`, missing file/executable, timeout, memory, disk),
each with the matched signatures, the reason (for example a compiler search
path that consumes `CANGJIE_STDX_PATH`, per cangjie_build
`docs/linux.md`), and the original error line as evidence. Cases without a
signature stay only in `failures.json`. `verify_hints.py` exercises the
matcher with one hit (`No such directory: '-lstdx.chir'` plus
`can not find package 'stdx.net.http'`) and one non-hit and checks the
written list; it exits nonzero if either is misclassified.

Compare two repeats with `python3 ci/cangjie-test/compare.py RUN1 RUN2 diff.json
--repeat`. Exit 1 means SDK identity, case sets or counts changed; the JSON lists
all case/status differences. Differences are observations, not automatically
classified as nondeterministic tests. For the bootstrap-versus-official
comparison omit `--repeat`; common and arm-only failure sets are retained.

Timeout failures retain their upstream failed status and are listed in
`timeout-failures.json`. The comparator excludes a case from both failure sets
if either arm has an exact upstream timeout signature; raw failure sets, counts
and status changes remain visible. Older case files must be normalized again
to include the timeout field. This does not turn timeouts into passes.

## Historical runs outside the required execution envelope

These records are not an accepted baseline for #482: runtime load admission
was missing, and nested cjpm compiler parallelism was not bounded. The first
run contains load1 >200 samples. Retain these records as historical evidence;
new runs must establish both controls before their failure sets are used.
The requested settings were jobs=48 and --compiler-jobs=2.

Two consecutive runs of the same SDK (`nightly-1.3.0-alpha.20260925001050`,
`bin/cjc` sha256 `045957a2…`) on a 192-core Linux x86_64 host produced identical
case inventories and these counts:

| suite | pass | fail | skip | not_run | stable failures (both arms) |
|---|---|---|---|---|---|
| Conformance | 26203 / 26206 | 2855 / 2852 | 2 | 0 | 2852 |
| HLT | 43755 / 43758 | 8211 / 8208 | 0 | 26391 | 34598 |
| LLT | 18179 / 18179 | 2080 / 2080 | 0 | 6244 | 8324 |

`not_run` are upstream `UNRESOLVED` records ("No valid command statement was
found"), not executed cases. Six cases changed status between the two runs (three
under `Conformance/Compiler/testsuite/src/tests/08_extension/02_members_of_extension/02_properties/01_modifier/a05/`,
three under `testsuites/HLT/Runtime/Concurrency/Thread/thread003|thread004` and
`testsuites/HLT/Tools/cjtrace-recover/test11`); treat them as nondeterministic and
compare them separately. One HLT case (`testsuites/HLT/regression/testcase_774/test.cj`)
carries the upstream timeout signature and is listed apart from the failure sets.

## Private prerequisites and seven-way triage (#705)

Prepare an independent SDK copy and evidence from the shared official SDK, or
from the qualified bootstrap SDK supplied by #135:

```sh
python3 ci/cangjie-test/environment.py SDK_SOURCE PRIVATE_SDK ENV_EVIDENCE \
  --arm official --jdk PRIVATE_JDK
python3 ci/cangjie-test/run.py PRIVATE_SDK O1 48 --compiler-jobs 1 \
  --inputs INPUTS --scratch O1.work --arm official \
  --environment ENV_EVIDENCE/environment.json
python3 ci/cangjie-test/classify.py O1 official-classification.json
```

For B use `--arm bootstrap` in both commands and pass
`--bootstrap-compiler-sha256 HASH` to `run.py` (see the trust input below).
That runner requires the original pre-seal `compiler-lineage.json` emitted by
the compiler producer. `sdk-stage-producer.mjs` creates it with the compiler
artifact before the output receipt is sealed. `compiler_identity.mjs` authenticates
the complete SDK plan/manifest/payload and resolves the native entry's original
member through `originalToolEntry`; the independent producer hash remains
required. Read-only composition keeps this original record unchanged.
Darwin loader transformations must be in the frozen producer recipe.



The environment preparation copies `modules` into the private SDK's
`tools/bin` as prescribed by the framework README:83–95. `run.py` sets the
LSP server path only in its private execution-input copy. The environment
adds the SDK's `third_party/llvm/lib` to the library path for cjdb and uses
only explicitly supplied JDK/stdx paths. It records file hashes and runs
JDK compile/execute and tool launch probes. Tool logs include loader traces;
`*.dynamic.txt` records ELF dynamic metadata. These probes establish tool
readiness, not correctness. Neither shared SDKs nor upstream input files
are modified.

`--stdx` must refer to an arm-specific build: official stdx is not a valid
bootstrap input. Without qualified stdx (owned by #522), the manifest marks
it unavailable. Managed tools on the bootstrap arm remain unqualified
under #521. All underlying test verdicts remain in `cases.json`.

Once both arms and their repetitions exist:

```sh
python3 ci/cangjie-test/classify.py O1 classified.json --bootstrap B1 \
  --repeat-official O2 --repeat-bootstrap B2
```

The seven disjoint categories are `B_only`, `O_only`, `common`, `timeout`,
`nondeterministic`, `tool_not_ready`, and `environment`. Status changes in
repetitions take precedence, followed by timeouts, unavailable dependencies,
and environment **hints**. The last two are triage evidence, not proven
causes. A one-sided failure requires the other arm to pass; missing, skipped,
or unresolved peers are retained as `unpaired_failures`, not successes.
`UNRESOLVED` records also remain in `unexecuted`. The classifier rejects
missing suites and differing input/runner recipes through `compare.py`.
With only O, `comparison_available=false`: no B/O comparison or repeated-run
stability is asserted. Raw failures, sources, and statuses are preserved in
every classified record. Repetition evidence availability is explicit.

Device regression entries are `verify_classify.py` and
`../bootstrap/test_compiler_identity.py`. The retired compose installation
fixture is replaced by `ci/bootstrap/sdk-compose-stage3.integration.test.mjs`, which
requires genuine C3/S1 inputs and checks the original producer and immutable
SDK. Its registration alone does not certify compiler semantics.

### Bootstrap compiler trust input

`--arm bootstrap` requires `--bootstrap-compiler-sha256 HASH`. Obtain HASH from
our independent compiler build output (for srcbuild, `compilerSha256` in
`software/stage3-compiler.json`, emitted by `build-stage3.mjs`). For a shared
stage1 build, use the verified build manifest's compiler artifact hash. Keep
that build's source commit, recipe and artifact hash with the run evidence.
Never derive this argument from the SDK being tested or its
`compiler-lineage.json`: the installer's record proves copy consistency and
can legitimately describe an official host compiler.

The Linux runner checks this independent hash against both producer/installed
records and all installed compiler bytes before admitting suite inputs. A
missing or mismatching hash fails admission. Official host assembly and
`--arm official` remain supported. A supplied hash is a trusted caller input,
not a claim that a self-written JSON record authenticates a producer. The
runner records the independent hash in `identity.json` for later comparison.

`verify_bootstrap_identity.py --compiler BUILD_ARTIFACT --official-frontend
OFFICIAL_COMPILER` rehearses the real installer and B entry with real bytes:
our compiler passes identity admission; installing the official compiler with
its genuine installer-generated record is rejected. Input admission deliberately
stops these tests before any compiler executes; this proves SDK identity
admission only, not compiler correctness or suite completion.

Target tool readiness consumes the ordinary `TOOLS-INPUTS.json` emitted by
`build/cli.mjs ... build tools`. Every one of cjpm, cjfmt, HLE, LSPServer,
cjcov, cjtrace-recover, cjlint, cjprof and cjcompat keeps its own source,
configuration, build/install status, retained executable, public entry, and
payload facts. Native cjlint/cjprof additionally install their shared libraries,
JSON/static configuration and JNI library. A missing, inherited-host, unresolved
or mismatched member stays `ready=false`; a successful help probe alone cannot
clear it. Readiness is a prerequisite observation, not tool semantics or full
SDK qualification. The independent cjdb prerequisite remains unchanged.

`available` is the prerequisite for executing the current SDK's business tests.
It retains native configuration/AST/payload checks and CJ compiler/std/runtime
pairing. The normal installer records its destination once in
`TOOLS-INPUTS.json.installationInputs`; original `producer.build.inputs` stays
unchanged. Lint/LSP runtime inputs may be selected at installation, but changed
inputs return `ready=false`, `applicability.status=NOT_CONSUMED` until a real
consumer is run. Installing, reading these facts, or a successful help command
does not run that consumer. Execute the existing `testInstall` commands after
availability admission and keep their actual results by scope; do not write
back a global ready receipt or import an earlier PASS. Compiler macro tests and
LSP source/CJO protocol tests do not imply lint/LSP macro coverage. Release
keeps that missing coverage explicit after its independent installed tests.

`environment.py` calls the adjacent `tool-readiness.mjs` reader for bootstrap
inputs and `apply_environment` checks previously ready entries again before
using the manifest. Keep these repository modules together when transferring
the runner. `verify-target-tools.integration.mjs REAL_TARGET_SDK NEW_WORK` is the
registered actual environment CLI check, requiring a real complete target SDK
and separate capacity for its private SDK copy. It does not start or relax the
96-CPU/8GiB language-suite entry. No target-tool or suite result is implied by
source preparation.
