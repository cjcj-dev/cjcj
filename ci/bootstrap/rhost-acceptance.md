# R-host production and installed consumers

`CJCJ_NATIVE_INPUTS` -> `sdk-inputs.mjs` -> `prepare-bootstrap-plans.mjs` ->
`sdk_build.sh` / `sdk-build.mjs` -> `sdk-flow.mjs` is the production entry.
A new compiler candidate changes configuration: use a new private work/install
pair; do not copy a previous flow or change its `build-result.json` to resume.
Within the same configuration, `--from` continues to run predecessor gates.

The descriptor can select independent std source with `stdlibCommit` (a full
40-character Git commit) and `sources.stdlib` (the local Git object repository).
Supply both fields together. `gitInput` resolves the tree from that object;
the repository's current HEAD need not be that commit. The build creates its
own checkout and retains the existing HEAD/tree/tracked-dirt checks there.
With neither field, std retains the runtime source identity and the generated
configuration stays unchanged. Explicit `CJCJ_SDK_INPUTS` records use the same
`stdlibCommit` plus the resolved `stdlib.repository/commit/tree` tuple; their
objects are checked again at the build entry, including std's tree.

This source supplies std build targets. It does not replace `runtimeCommit`,
`sources.runtime`, runtime installation/producer facts, or
`installations.stage2.bootstrapStd`. In a C2 reuse configuration only the final
std source checkout remains; C2's original bootstrap std and source checks stay
in place. Native std uses the selected checkout with the separately installed
runtime libraries and writes its actual std source in PROVENANCE.txt. Final
copy, barrier, language, installed consumer and archive gates remain required.

Changing std source also changes the configuration hash. An old work directory
must still reject this with `WORK_INPUT_MISMATCH`; do not rewrite its result or
use `--from stage3-std` with a new hash. Prepare a fresh private work/install and
workspace, retaining the original `installations.stage2` facts to reuse C2
without rebuilding it or runtime. The first `sdk-build.mjs --config ...
--no-package` performs the native and installed-input gates and copies those
inputs before final std. A later same-configuration continuation can use
`--from`. A cached source checkout must already match the selected commit/tree
and be clean; this entry never resets another checkout on the caller's behalf.

The normal production order is H/H1 -> std-bootstrap -> stage1-initial ->
stage1-std -> C2 install -> installed consumers -> stage3-std -> C3 install ->
existing language gate and installed consumers -> final test -> archive ->
unpack -> the same installed consumers. Macro execution is not a predecessor
of C2 production. If an ordinary production command enters the macro loader,
retain the first command and import chain and stop; do not substitute H.

H/H1 and stage1 are transitional ordinary compilation tools. A flow's COMPLETE
means only that its requested traversal completed. It is not full SDK status.
C2/C3 launch the R runtime through the existing public native entry and
`libexec/runtime`; all target CJ std/helper/macro code uses that installation.
The existing InvokeUtil task/loader image checks and RegisterCjPlugin /
InitCJLibrary / ExecutePlugin production path are unchanged.

`sdk-verify-install.mjs` is shared by stage2, stage3, both source-build verify
entries and package installation/relocation. It retains hello/cjpm and calls
`sdk-installed-macros.mjs`: original Keep definition/expansion/42, separately
compiled ordinary CJ leaf/helper called by a macro, deriving ToString, explicit
testmacro, no-import `--test`, and mockmacro `@On` with an actual mock call.
Every compile uses the installed public `cjc` found on the SDK-prefixed PATH.
Inputs/outputs contain spaces; each attempt has a fresh directory. Per-command
logs retain argv, stdout/stderr, actual rc/signal, and produced ELF/SO/archive
identities. An unexpected failure stops subsequent consumers.

Syntax/option sources (fixed C/H1 pair and R input):

- `test/macro_same_runtime/{def,use}.cj` and `ci/smoke/run_smoke.mjs`.
- `packages/option/src/Options.cj`: visible --test, --compile-macro,
  --output-type=staticlib, --import-path; no hidden --typecheck.
- `packages/frontend/src/FrontendModel.cj`: AddImplicitImports.
- R `stdlib/doc/libs/std_en/deriving/deriving_samples/deriving_user_guide.md`.
- R `stdlib/doc/libs/std_en/unittest_mock/unittest_mock_samples/`:
  mock_framework_getting_started.md and mock_framework_basics.md (`--test`).

An optional `installations.h1` descriptor object names `product`, `buildInputs`
(the producer's adjacent bin/build-inputs.json), and `buildResult` (original
native H1 commands). It feeds the existing stage0 reuse branch after checking
source, host, N, producer command/rc and product bytes. Omit it for a native H1
build. It is not a migration of a previous flow's stage output.

## Controlled semantic cut and recovery (prepared, NOT_RUN)

This is a design for a later explicitly authorized isolated R source/install,
not permission to alter the retained R input. Keep the candidate/compiler and
all consumer assertions fixed across normal/cut/recovery arms.

1. Obtain a successful normal run through the formal build/install and public
   installed gate. Preserve build inputs, compiler/runtime/macro SO identities,
   commands, logs and actual rc. Unknown failures stop the dependent arms.
2. In the isolated R std source only, change the empty-case string in
   `stdlib/libs/std/deriving/builtins/tostring.cj` from
   `"${target.declaration.identifier.value}()"` to
   `"${target.declaration.identifier.value}(cut)"`. Save that exact `cut.diff`.
3. Use the original stdlib native build.py build/install path with R-host C2
   and the same R target-lib. Rebuild/install the affected deriving dependency
   closure into the isolated SDK; never edit/copy a test-only macro SO. Preserve
   the producer commands and output identities. Do not run the full flow's
   copy step over an occupied installation or forge its configuration.
4. Invoke `node ci/bootstrap/sdk-verify-install.mjs --sdk ISOLATED_INSTALL
   --work FRESH_ARM --platform linux_x86_64`. Require ordinary/cjpm, Keep/42 and
   helper-chain controls to have succeeded; deriving compile must be rc 0,
   `deriving-run` must reach `DERIVING_ASSERTION_REACHED value=Empty(cut)` and
   exit exactly 42. Loading/parse/link failures or any other nonzero are NOT
   this red. Assertions and the normal gate stay unchanged; the gate fails.
5. Restore the R source, verify zero source diff, repeat the same native
   build/install and public gate in a fresh arm; require every consumer rc 0
   and `DERIVING_ASSERTION_REACHED value=Empty()` / `DERIVING_VALUE_PASS`.
   Archive/unpack the recovered installation and run the same public gate.

The missing-API/foreign-image controls, live loaded-image evidence and actual
CJ plugin consumer remain separate obligations; this semantic cut does not
stand in for them. Do not introduce a second runtime, observer, preload hook,
or return-poll/GC changes. No cut has been applied by this source change.

Linux native is the first execution scope. Windows, Darwin, ARM native and
cross host-macro/target-code obligations remain unverified. Existing cross
packaging reports NOT_RUN for host execution; native macro gates are not
removed for other platforms. Six tools (cjpm/cjfmt/hle/lsp/cjcov/cjtrace-recover),
stdx, final std barriers, native source identity and full package gates remain
required through their existing native build/install paths. Macro consumers
alone never grant full SDK, merge or release qualification.
