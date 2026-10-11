# Test execution registry

`node ci/test-manifest.mjs check` compares discovered tests and registrations in
both directions. Default Node contracts live in `GATING`; `DEFERRED` records
their required inputs and actual prior invocation results. Python, shell,
Cangjie and environment-bound manual Node entries live in `test-registry.json`.
Test naming conventions are
`*.test.mjs`, `*.integration.mjs`, `test_*.py`, `test-*.py`, `test_*.sh`, `test-*.sh`, `*_test.sh`,
`*-test.sh`, `*.test.sh`, `*_test.cj`, shell files under `build/test/`, and
Python/shell files directly inside a nested `tests/` directory.
Helpers such as `run.py` and `check.py` are dependencies of test drivers, not
independently discovered test cases. Register new standalone tests using these
names. Untracked files are included; ignored build output and node_modules are not.

Node integration tests with private prerequisites can be registered as `manual`;
name-based discovery does not make them gating or execute them.

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

### Complete SDK integration registration closure

The `*.integration.mjs` entries below belong to the SDK/bootstrap or host
selector contracts named in the table. Each is `manual` because its **actual
private input closure** is absent from existing CI, even where part of the test
is a dry-run or a small native fixture. This is not a failure exemption. The
script runner supports Python/Bash, the package runner supports cjpm, and the
Node gating job does not supply these plans, products or exclusive write domains.
Do not wrap Node in a Bash executor or accept an input-dependent skip as a CI
pass. No existing registration, GATING entry or DEFERRED entry is replaced.

Run `node --test <entry>` from the source root, except
`sdk-cjdb-tuple.integration.mjs`, which is a plain assertion script run with
`node <entry>`. Bind all paths absolutely and retain the source/product/tools
identities and raw command results. These retained fixtures target Linux x86_64;
matching source/tool identities and the complete transitive input closure are
required. All entries remain **NOT_RUN** until separately authorized execution.
Creating private output directories does not authorize downloading publisher
inputs, rebuilding a complete SDK, mutating shared installations or operating
a debugger. CJDB Python installation checks import LLDB and create/destroy an
SBDebugger; execution must also respect the current debugger-owner contract.

| Entry (`ci/bootstrap/` unless shown otherwise) | Contract owner / required private inputs | Scope and exclusive domain |
|---|---|---|
| `sdk-bitcode-readers.integration.mjs` | SDK bitcode-reader publication. `SDK_READER_PLAN and SDK_READER_EVIDENCE; optional SDK_READER_INVALID_PLAN and SDK_READER_PRODUCT`. Retained actual native producer receipts and sealed llvm-as/llvm-dis executable and semantic identities. Same-tree SDK CLI publishes and inspects the receipt-backed SDK. | Fresh assembled SDKs and per-command logs/results under the private evidence root. NOT_RUN. |
| `sdk-cjdb-python-closure.integration.mjs` | CJDB Python installation closure. `CJDB_CLOSURE_PREVIOUS and CJDB_CLOSURE_OUTPUT; CJDB_CLOSURE_ARM=normal, import or refuse`. Completed prior normal-config qualification with install_manifest.txt, import-artifacts.json, original sealed native receipt, Python 3.11 and actual LLDB installation; readelf and ldconfig. Imports real lldb bindings and creates/destroys SBDebugger. | Entire private output parent including sibling sources.json and normal/install; refusal arms copy/mutate/restore only owner installations. NOT_RUN. |
| `sdk-cjdb-python.integration.mjs` | CJDB Python producer/child configuration. `CJDB_PYTHON_PARTIAL, CJDB_PYTHON_OUTPUT and CJDB_PYTHON_SOURCES; optional CJDB_PYTHON_CONFIGURE_ONLY=1`. Real partial request/native prerequisite build, fixed compiler/LLVM/runtime/boundscheck/flatbuffers Git locators, Python receipt/root, CMake/Ninja/ccache/Clang. Default execution builds and installs LLDB and loads its Python bindings; configure-only still configures the real parent and child. | Owner source clones, identities, parent/child build graphs, installation and evidence; original partial inputs read-only. NOT_RUN. |
| `sdk-cjdb-qualification.integration.mjs` | CJDB generated-input qualification. `CJDB_REQUEST and CJDB_QUALIFICATION_EVIDENCE`. Retained real partial native request, fixed source checkouts, demangler archive, boundscheck library and generated five-byte closure, actual CMake native configure recipe. Invokes real preconfigure/preseal hooks and configures the fixed LLVM project without a full build. | Exclusive input LLVM source domain for temporary extra ignored-file mutation/restoration; isolated clone, configuration and capsule/evidence outputs. NOT_RUN. |
| `sdk-cjdb-shim.integration.mjs` | CJDB schema/shim read surface. `CJDB_SHIM_PARTIAL, CJDB_SHIM_OUTPUT and CJDB_SHIM_CJO`. Retained partial native build with actual flatc, compiler/flatbuffers/LLVM sources and headers, built libLLVM-15.so and a real CJOF package; /usr/bin/clang++, ldd. Compiles and loads the shim and independent surface_probe. | Private generated headers, object/shared library/probe, invalid CJOF copy and identity/command evidence; original partial/CJO read-only. NOT_RUN. |
| `sdk-cjdb-tuple.integration.mjs` | CJDB fixed-tuple qualification. `CJDB_REQUEST and CJDB_QUALIFICATION_EVIDENCE`. Actual fixed-53ce LLVM/174db compiler request with build identity, real generated inputs, demangler/boundscheck products and frozen CMake/Node/Git tools. This is a plain Node assertion script, not a node:test suite; invokes real hooks and certificate/install consumers. | Exclusive request LLVM source domain for securec.h mutation/restoration plus private qualification/capsule/evidence outputs. NOT_RUN. |
| `sdk-official.integration.mjs` | SDK official alias producer/resolver. `SDK_OFFICIAL_PLAN and SDK_OFFICIAL_EVIDENCE`. Privately verified real Linux x86_64 publisher distribution and authenticated lock for 1.3.0-alpha.20261009001050. Invokes actual official producer/resolver and runs the physical compiler -v control. | Private per-test plan/build roots, receipts, resolver outputs and evidence; original distribution read-only. NOT_RUN. |
| `sdk-payload.integration.mjs` | SDK Linux official payload completeness. `SDK_OFFICIAL_PLAN and SDK_OFFICIAL_EVIDENCE`. Actual publisher distribution inventory/lock and source payload. Real resolver first completes official production then rejects a deliberately missing cjdb installation. | Private expected inventory, modified plan, producer build root and resolver evidence; original publisher input read-only. NOT_RUN. |
| `sdk-phase-handoff.integration.mjs` | SDK bootstrap phase identity handoff. `SDK_PHASE_OBSERVATION and SDK_PHASE_WORK_ROOT; optional SDK_PHASE_PRODUCT_ROOT`. Retained complete-plan fixture observation with adjacent bundle.frozen.json and its frozen source/tool/plan identity closure. Runs toolchain-sdk, prepare-bootstrap-plans and bootstrap-sdk real CLIs in dry-run mode; dry-run still requires genuine plan inputs. | Private direct/generated plans, bundle and assembly destinations; retained producer inputs read-only. NOT_RUN. |
| `sdk-runtime-source.integration.mjs` | SDK runtime source admission. `SDK_RUNTIME_SOURCE_SDK, SDK_RUNTIME_SOURCE_ROOT and SDK_RUNTIME_WRONG_SOURCE; optional SDK_RUNTIME_SOURCE_PRODUCT`. Genuine retained SDK.manifest.json/SDK.lock.json and runtime payload, matching fixed runtime Git source plus independent wrong Git source. Imports actual runtime verifier and observes its rejection. | Input SDK/source trees remain read-only; use privately owned inputs and retain invocation evidence. NOT_RUN. |
| `sdk-stage-selection.integration.mjs` | SDK installed stage compiler selection. `SDK_STAGE_PLAN, SDK_SELECTION_WORK_ROOT and SDK_COLLISION_OBSERVATION; optional SDK_SELECTION_PRODUCT_ROOT`. Genuine retained stage compiler plan and native collision apparatus with original receipts/source/tools. Real SDK CLI checks stage1/stage3 dry plans and performs collision production/assembly. | Private modified plans, collision producer builds and SDK/evidence destinations; no mutation/resealing of retained receipts. NOT_RUN. |
| `sdk-stage1-llvm.integration.mjs` | SDK stage1 host/target LLVM domain. `STAGE1_FIXTURE_ROOT and STAGE1_TOOLS_REPO; optional STAGE1_REAL_LLD, STAGE1_FIXTURE_REUSE and STAGE1_ARM_PREFIX`. Clean fixed private tools Git checkout with real sharedbuild main.py/cjcj-stage1.mjs; Linux x86_64 cc, git, Python, readelf and real installed lld. Compiles small native ELF fixtures and invokes actual stage1 adapter through fixtures/sdk-stage1-observer.mjs; never a full Cangjie/native receipt. | Entire private fixture root including source Git, original host lock, host/target bytes, shared cache, adapter work and failure/restoration evidence. NOT_RUN. |
| `sdk-stage1-plan.integration.mjs` | SDK formal stage1 producer recipe. `STAGE1_FROZEN_PLAN and STAGE1_PLAN_EVIDENCE`. Actual frozen production plan with source/tool/host identities and native shim/libLLVM bindings. Calls same-tree SDK CLI --dry-run for normal, wrong-dependency/reserved-host-lock and restored plans. | Private plan copies, CLI logs and result JSON; frozen plan and its inputs read-only. NOT_RUN. |
| `ci/host-toolchain-official.integration.mjs` | Host workflow publisher selection. `SDK_OFFICIAL_PLAN`. Real private Linux publisher distribution with executable bin/cjc to measure -v independently; same-tree host-toolchain-pin.mjs workflow selector. Existing pinned old CI SDK is not this measured publisher input. | Distribution/plan read-only; private invocation evidence; other-platform selector remains an independent control. NOT_RUN. |

The optional product overrides select real CLIs/modules, not substitute models;
record both override and same-tree import identities. Closure normal/import/refuse
arms share their owner's sibling outputs. Qualification and tuple checks mutate
the request's LLVM source before restoration, so evidence-only isolation is
insufficient. The Python producer test's default includes a native LLDB build;
`CJDB_PYTHON_CONFIGURE_ONLY=1` narrows only that invocation and cannot stand for
installation coverage. Stage selection's collision arm performs real production;
its earlier dry-run arms do not qualify that assembly.

Discovery/check integration requires the separate fixed #941 discovery repair.
This registration-only change does not include that product repair. Validate the
complete fixed source plus both changes through `node ci/test-manifest.mjs check`;
`registered` exposes manual entries, while `list` remains the existing automatic
Node set. A successful check proves registry closure, not SDK integration passes.
