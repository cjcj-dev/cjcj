# Test execution registry

`node ci/test-manifest.mjs check` compares discovered tests and registrations in
both directions. Node contracts retain `GATING` and `DEFERRED`; Python, shell and
Cangjie entries live in `test-registry.json`. Test naming conventions are
`*.test.mjs`, `test_*.py`, `test-*.py`, `test_*.sh`, `test-*.sh`, `*_test.sh`,
`*-test.sh`, `*.test.sh`, `*_test.cj`, shell files under `build/test/`, and
Python/shell files directly inside a nested `tests/` directory.
Helpers such as `run.py` and `check.py` are dependencies of test drivers, not
independently discovered test cases. Register new standalone tests using these
names. Untracked files are included; ignored build output and node_modules are not.

Each non-Node entry names a real interpreter and arguments, a cjpm workspace
member, an existing `workflow` command, or `manual` with a concrete input/isolation reason. `{output}` expands
to a unique, initially absent evidence directory. Manual entries are visible
with `node ci/test-manifest.mjs registered`; they are not counted as CI passes.
The host-identity Python suite includes fixture coverage in CI; its optional
real fixed-release SDK/LLVM arm remains manual and reports a unittest skip.

CI runs `node ci/run-registered-tests.mjs scripts NEW_OUTPUT_DIR` with four
independent workers. The Cangjie job sources the official `host_sdk_pin.env`
SDK, builds the compiler shim, then runs
`node ci/run-registered-tests.mjs cj NEW_OUTPUT_DIR`. It invokes `cjpm test`
over workspace `test-members` with machine-readable reports and records SDK
hashes. Nonzero child exits remain failures; an empty report set cannot pass.
Compile/link failures are recorded as failures to execute, not successful tests.

The first frozen-baseline run exposed existing failures: `test_sdk_cjc_swap.py`
fails four replacement/path assertions (cjcj#783), and workspace tests fail to
link `chir`, `codegen` and `sema.resolver_tests` before test bodies execute.
The CI jobs deliberately retain these nonzero exits. Their baseline evidence
and follow-up issues are recorded in the implementation report; no test has
been reclassified as manual because of an assertion failure.

For baseline comparison use the same runner, registry, SDK, flags and shim on
two isolated source trees, retaining each `results.json`, `run.log` and test
report directory. Compare failure identities, not just exit codes or counts.
Existing failures must stay visible; this registry contains no failure allowlist.
