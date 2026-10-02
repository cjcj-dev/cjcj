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

### ObjC preamble declaration inputs (Linux official host)

Workspace tests require same-tree declaration modules, not a Darwin runtime.
Build the release compiler with the pinned official host and prepared LLVM shim.
CI builds into an explicit private target directory and requires exactly one of
`release/bin/cjcj::cjc` or `release/bin/cjc@cjcj`, then physically copies it as
`cjcj-stage1`. Set `OBJC_PREAMBLE_PRODUCER` to that absolute product path before
running `node ci/run-registered-tests.mjs cj NEW_OUTPUT_DIR`. The runner prepares
internal then lang with that producer, verifies `fixture.json` hashes, and passes
its private imports and temporary directory to the official host's `cjpm test`.
Preparation failure stops before cjpm and writes `prerequisite.json`.

For direct workspace invocation (W=source tree, H=pinned official SDK,
P=private absolute output, producer=the same-tree release product):

```bash
python3 scripts/objc_preamble_unit.py --prepare-only --build-tree "$W" \
  --sdk "$H" --producer "$producer" --out "$P/objc-fixture"
PATH="$H/bin:$H/tools/bin:$PATH" OBJC_PREAMBLE_IMPORTS="$P/objc-fixture/imports" TMPDIR="$P/tmp" \
  CANGJIE_HOME="$H" "$H/tools/bin/cjpm" test -j"$(nproc)" --no-color \
  --report-format=xml --report-path="$P/reports" --target-dir "$P/test-target"
```

Create `$P/tmp` before the direct invocation. Keep `fixture.json`, producer logs,
and the modules together. The import root is `imports`, containing
`objc/objc.internal.cjo` and `objc/objc.lang.cjo`; source directories, SDK modules,
and `imports/objc` are not substitutes. The static archives are recorded inputs,
not additional workspace link options. Bare tests without this prerequisite fail
with an explicit fixture error; neither original test nor assertion is skipped.

Directed reuse is limited to the registered ObjCPreamble suite. Capture the
SHA256 of the already built `release/unittest_bin/compiler_unittest@cjcj` ELF,
then use the same official SDK and workspace source:

```bash
node ci/run-registered-tests.mjs cj NEW_OUTPUT_DIR \
  --member packages/compiler_unittest --filter '*ObjCPreambleTest*' \
  --skip-build --target-dir "$BUILT_TARGET" --elf-sha256 "$ELF_SHA256"
```

All five selection fields are required. The runner verifies the registered
source cases, regular x86-64 ELF and expected hash before preparing imports;
then it uses cjpm's actual member/filter/skip-build options and checks that XML
contains exactly the source-declared executed cases. Missing, skipped, duplicate
or unrelated execution records fail. The default invocation still tests the
whole workspace. Directed success does not represent a whole-workspace pass.
