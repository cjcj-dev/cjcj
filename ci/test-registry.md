# Test execution registry

`node ci/test-manifest.mjs check` compares discovered tests and registrations in
both directions. Default Node contracts live in `GATING`; `DEFERRED` records
their required inputs and actual prior invocation results. Python, shell,
Cangjie and environment-bound manual Node entries live in `test-registry.json`.
Test naming conventions are
`*.test.mjs`, `test_*.py`, `test-*.py`, `test_*.sh`, `test-*.sh`, `*_test.sh`,
`*-test.sh`, `*.test.sh`, `*_test.cj`, shell files under `build/test/`, and
Python/shell files directly inside a nested `tests/` directory.
Helpers such as `run.py` and `check.py` are dependencies of test drivers, not
independently discovered test cases. Register new standalone tests using these
names. Untracked files are included; ignored build output and node_modules are not.

Each registry entry names a real interpreter and arguments, a cjpm workspace
member, an existing `workflow` command, or `manual` with a concrete input/isolation reason. `{output}` expands
to a unique, initially absent evidence directory. Manual entries are visible
with `node ci/test-manifest.mjs registered`; they are not counted as CI passes.
The host-identity Python suite includes fixture coverage in CI; its optional
real fixed-release SDK/LLVM arm remains manual and reports a unittest skip.

### Private SDK integration inputs

These three Node tests were previously unregistered, rather than part of the
automatic execution set. They use the existing `manual` executor because the
workflow supplies neither their private inputs nor exclusive mutation domains.
Registration leaves `GATING` and `DEFERRED` unchanged. `list` still emits only
`GATING`; `registered` exposes these entries, and the script/cjpm runners exclude
`manual`. Their execution status is **NOT_RUN** until a separate execution
contract provides the inputs and records actual results; manifest success
proves registration coverage, not that these SDK tests passed.

Run each entry from the source-tree root with the command below after binding
absolute input paths and creating its private evidence/test parent. Current
fixtures require Linux x86_64. Keep source/engine, plan, receipts and product
identities with results. All transitive build/cache/artifact paths must belong
to the isolated execution owner; a private evidence directory alone is
insufficient. Never point them at shared SDK installations or another active
lane's inputs.

| Entry | Required inputs and execution conditions | Exclusive write domain |
|---|---|---|
| `node --test ci/bootstrap/sdk-boundary.test.mjs` | `SDK_BOUNDARY_PLAN`: retained successful fixture plan with original producer `output.json`, seals, shared cache and compiled `core.Int64.ti`; `SDK_BOUNDARY_ROOT`: existing evidence parent. Calls same-tree `toolchain-sdk.mjs`; no CLI override. | Entire plan build/cache/artifact closure and assembly/evidence outputs. Producer and consumer arms replace original bytes, rename a component directory and restore both. |
| `node --test ci/bootstrap/sdk-real-boundary.test.mjs` | `SDK_REAL_PLAN`, `SDK_REAL_SDK`: genuine complete SDK with `SDK.manifest.json`, cross-repository receipts, runtime `bin/cjfilt`/`RuntimeAPI.h`, AST headers, original `std.core.cjo`, `libLLVM-15.so` and official distribution payloads; `SDK_REAL_EVIDENCE`: existing evidence parent. A small C fixture cannot replace these products. | Original producer artifacts plus temporary/reassembled SDK and evidence outputs. Arms move/replace ordinary and LLVM payloads, restore them and remove duplicate assemblies. |
| `node --test ci/bootstrap/toolchain-sdk.test.mjs` | `SDK_SHAREDBUILD_ENGINE`: engine in an independently owned clean Git checkout, whose HEAD and engine digest are captured; `SDK_MANIFEST_TEST_ROOT`: existing writable private parent. Requires `python3`, `node`, `git`, `bash`, `tar`, `cmake`, `clang`, `clang++`, `cc`, `ar`, and verification `nm`/native loading. Even its dry-run case first compiles fixture ELF/shared libraries/archives. | Fixture source Git repositories, plans, receipts, seed/shared caches, native builds, SDKs and evidence under the private root; concurrent requests and failure/recovery arms mutate that closure. |

`ci/bootstrap/sdk-export.test.mjs` is a separate manual producer/export check.
It requires `SDK_EXPORT_PLAN` (a private sealed supplemental Linux plan with
fixed compiler `174db8f40d5efddee63c47a3162bbf676bc227a0` schema source, securec and LLVM release receipts), `SDK_EXPORT_RUNTIME_SOURCE`
(a retained clean Git checkout matching the runtime commit/tree), `SDK_EXPORT_ROOT` (an existing private evidence parent),
at least 64 available CPUs and the plan's frozen Node/Git tools. It invokes the
same-tree producer through the real SDK resolver CLI. Existing receipts and
sources remain read-only; fresh schema/native resolver directories and isolated
product cut checkouts are its write domain. CI does not provide these inputs;
registration is NOT_RUN and does not qualify the complete SDK.

The real-boundary and toolchain tests allow `SDK_MANIFEST_PRODUCT` to select
the assembler CLI. Their direct verification imports remain same-tree modules;
record both identities. The boundary test always invokes the same-tree CLI.
Missing required inputs fail rather than skip. Manual registration is based on
these dependencies, not an assertion failure, and does not qualify full SDK
production or authorize a new engine/SDK build.

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

SDK export tests also bind compiler XML2 2.14.0 to its pinned GNOME source archive and actual compiler CMake dependency recipe, then check its installation through a real SDK assembly. Input-only reader ownership is checked through the same CLI. The private Python dependency preparer is a production entry, not a test; its source receipt does not certify an LLDB consumer.
