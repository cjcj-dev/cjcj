# Source and reference SDK inputs

The native std build/install check follows the ordinary cjnative producer's
target layout: Linux requires the installed core LTO bitcode; Windows and
ordinary Darwin do not produce it. Every target still requires the core CJO,
static core library, shared core library and shared FFI library. This layout
check does not qualify a Windows/Darwin compiler, SDK, or package; native inputs,
runner, byte identities, language consumers and the final archive checks remain.

Native Python source facts travel from the original native producer's
`configuration.pythonInputs` (or its existing dependency input record) through
`verification.python` into `native-llvm.json.pythonSource`. This row carries
the original archive URL/version/hash, producer, the actual interpreter's
`CONFIG_ARGS`, and hashes of the installed interpreter, header and library.
Missing original inputs remain `source.status: unresolved`; a version or a
current selector never supplies the missing source. These facts supplement the
existing Python configuration, library-loading and LLDB consumer checks.

The installed native HLE entry supplies missing `-b`, `-j` and `-r`
arguments from the installed `tools/dtsparser` tree. It preserves explicit
options, relative input/output arguments and the caller's working directory.
Like the component's `std.argopt`, it recognizes complete long names with one
or two dashes before short-option clusters, and consumes required operands
(including values such as `-pthread` or `--help`) without scanning them as flags.
Default C/TS consumption therefore follows the installation after relocation;
the fixed HLE component bytes and parser remain unchanged.

`build/cli.mjs` reads the source defaults from `ci/source_pin.env`. Each fetch
repository uses `--repo-url NAME=URL` before its pinned URL, and
`--repo-tag NAME=REF` before `--tag REF` before its pinned commit. Runtime keeps
its existing unpinned default; production callers supply the runtime tuple
explicitly. Empty explicit values are errors. Compiler's normal source default
is its existing source pin; the bootstrap workflow supplies its own explicit
compiler source as before.

The private tools combination and stdx commits are not release pins deployed to
upstream. The `*_REF_AUTHORITY` private refs refer to the imported private Git
repositories. Supply `CJCJ_SRCBUILD_SOURCE_MIRRORS` to map each canonical URL to
an actual repository containing the fixed objects. The tools repository must
contain both the combined tools commit and the separate cjpm fork commit.
`CJCJ_SRCBUILD_REQUIRE_MIRRORS=1` rejects an absent mapping before network fetch;
there is no fallback to another tools commit. No push is required.

Fetch creates each missing repository through the existing shallow/exact Git
fetch implementation. For existing directories it checks the actual repository
root and HEAD against this invocation, and origin when present. The formal
job-handoff archive excludes `.git/config`; missing origin is accepted without
skipping HEAD or tracked-content checks. No credential config is reconstructed. Symbolic refs are resolved in
that existing checkout; this does not refresh a moving upstream branch. Use a
full commit for immutable production input. An empty directory, wrong origin,
missing ref or wrong HEAD is rejected without reset or cleanup. Prepare a new
workspace when changing identities. Tools and stdx also reject tracked source
changes; tools permits its normal `cjpm/` overlay. Untracked native outputs are
preserved. Direct `build tools` and `build stdx` enforce the same identity
checks, so changing a pin cannot silently continue a previous checkout.

Successful fetch saves only explicit repository URL/tag options (including a
global tag expanded to each selected repository) in the workspace's ordinary
`.source-selection.json`. Later build/config consumers reload those options;
this file travels inside the existing `.srcbuild` handoff. It is configuration,
not an identity receipt: actual HEAD/content checks still run. Omitted defaults
are not stored, so default pin changes cannot silently reuse old source. A new
`fetch` uses its current arguments/defaults, checks existing directories before
saving, and replaces the saved options only after all fetch/patch steps succeed.
Failed fetch does not replace prior options. Credential-bearing URLs, URL query
strings/fragments and empty options are rejected; use Git credential configuration
for authentication. Neither that configuration nor credentials are handed off.

The tools stage fetches `ci/cjpm_pin.env`'s exact object through the same mirror
resolver, checks FETCH_HEAD, then restores **only** the complete `cjpm/` subtree
in the index and working tree. Restore removes tracked files absent from the
fork, unlike an overlay checkout. The other five tools remain at the combined
source. Native source preparation (including the existing Windows path patch),
build.py, installation and tool consumers follow this step unchanged.

`package` and `verify` select the reference SDK in this order:

1. `--official-sdk-root PATH` (relative paths resolve against the invocation cwd).
2. `CJCJ_OFFICIAL_SDK_ROOT` (the existing release package reference setting).
3. `CJCJ_SRCBUILD_HOST_SDK` (the existing private host SDK setting).
4. The platform host pin under the real home directory's `.cjv/toolchains/`.

An explicit empty value, absent directory or regular file is a configuration
error. An omitted option preserves the existing pinned fallback. No HOME
override or shared SDK write is needed. The CLI passes `officialSdkRoot`
through config, `packageMainSdk`, `packageInstall` and `assertSdkPathParity`;
the parity boundary still rejects a materialized depot reference. The CI
`ci/srcbuild/steps/package-install.mjs` already supplies the official env value
to buildConfig and now inherits the private host fallback when it is absent.
CI `steps/verify.mjs`, config and both parity/lineage consumers use the same
`resolveOfficialSdkRoot` function; CI has env precedence and the same pinned
fallback, without a new descriptor scheduler.

The bootstrap descriptor's `host.install` feeds the bootstrap native stages and
SDK copies through `sdk-targets.mjs`; that descriptor does not call this CLI's
package stage. It is not a new scheduler for tools/stdx or package references.
After bootstrap, the normal CLI invocation must supply the corresponding host
environment or explicit reference option and the installed consumer SDK.

## Limited integration test

Run `build/test/sdk-inputs-cli.integration.mjs` only in an approved private kkk2
domain, with `SDK_INPUT_WORK`, `SDK_INPUT_MIRRORS`, and `SDK_INPUT_H` pointing to
the private test workspace, imported fixed Git repositories and read-only H.
It invokes the real CLI in child processes and retains argv, selected env,
stdout, stderr, status and signal for every call. Compiler/runtime fetches use
small unrelated Git fixtures; tools/cjpm/stdx use the actual fixed objects.
Explicit file-URL fetch is followed by public build in a separate process. Both
default and explicit inputs also pass through the actual `job-handoff.mjs`
pack/restore commands, then build without `.git/config`, with a wrong-HEAD
negative control. These are prepared cases, not execution evidence.

The loader in `sdk-inputs-observer.mjs` observes the real path-parity reference
selection and reads H's real `envsetup.sh`, then stops before inventory,
compilation or packaging. A separate case retains the real depot rejection.
Verify cases observe lineage's actual reference-root selection before content
scanning, with the unrelated runtime/language prerequisites controlled. CI verify
cases run its real entry via the existing `zx/globals`, retaining argv/env/target
and lineage dispatch while the loader skips preflight shell probes. They stop
at the same lineage observation before smoke, compilation or content scanning. It
bypasses the downstream ABI check solely because
the installed tree is a small interface fixture. Tools and stdx stop at their
native build boundary. This grants only CLI/input integration evidence, never
compiler/runtime compatibility, full path parity, SDK build/install, archive,
or relocated consumer qualification.

After a successful candidate suite, `sdk-inputs-cuts.mjs` cuts actual private
product files at CLI H mapping, package/verify H forwarding, default source pin
use, resume identity checking, cjpm restoration and native prerequisite rechecks,
plus handoff missing-origin support, saved fetch options and CI verify H.
Package/verify forwarding cuts supply a wrong root explicitly, because an omitted
root now correctly inherits the shared environment fallback.
Each cut requires its target
assertion, an independent control, exact source restoration and affected-case
recovery. Full compiler/std/runtime/tools builds, bootstrap stage acceptance
and final package production remain separate work.

## Bootstrap resumption

The native descriptor, explicit sdk-inputs and explicit targets converge through
`prepare-bootstrap-plans.mjs` and `sdk-build.mjs` on `buildFlow`. Their existing
bootstrap target/source validation remains in force. `--from` still requires
the original same-configuration build result and each declared predecessor
output; it now also checks the predecessor's real directory boundary and runs
that stage's existing `test` before publishing the output to dependents. For
bootstrap nativeN/nativeR these are the configured native input checks. It skips
production, not validation. A failed check preserves its real command rc and
stops the dependent stage. Full native checks may require their original
resource/debugger authorization; a script-only allowance does not authorize
running them.

`ci/bootstrap/sdk-resume-inputs.integration.mjs` exercises this branch through
the real sdk-build CLI using script producers and consumers. Its predecessor
records come from the actual first invocation. It covers successful reuse,
changed N/R inputs, no prior result and symlinked predecessor rejection. It
does not qualify the three full bootstrap entry configurations or LLVM/R ABI.

`sdk-native-libraries.integration.test.mjs` now consumes an already completed
installation read-only, requiring its original targets/inputs/build-result
and preserving the native linker, bytes and ownership assertions. It neither
manufactures a WIP predecessor result nor creates aliases into another work
directory, and makes no claim of executing bootstrap recovery. The fixed
rework/flow stage1-initial result is prior historical evidence; candidate
recovery and native checks remain to be run under a suitable later contract.


## Command parity and installed package responsibilities

The registered `source-build-parity.test.mjs` Linux command-order case owns
compiler/runtime/stdlib/stdx commands, all six tool argv (including cjpm jobs),
each clean-before-build edge, and the all-builds-before-shared-install barrier.
Its command-generation fixture does not contain an executable SDK. It no longer
runs installed package/verify consumers before reaching those assertions.

The existing package path/root, relative compiler/pcre/stdx links, missing-path
and external-link cases in that same registered file remain unchanged. Their
opaque fixtures still need migration for the current native package consumers;
they are not qualified by the command-order result.

`build/test/source-build-installed.integration.mjs` is separately registered for
manual real-input execution. Set `SOURCE_PARITY_INSTALLED_CONFIG` to a JSON of
`buildConfig` options for the private prepared native workspace, including
`officialSdkRoot` and `consumerSdk` (the existing `workspace/software/cangjie`).
It invokes public CLI package and verify, checks both archive roots and installed
bytes, and retains each actual child result. Package uses `packageInstall` →
`verifyInstall` (hello/cjpm and macros), then `archiveInstall` parks the original
installation during unpacked verification and restores it. Verify retains the
GC/language-input, runtime, lineage, hello and macro checks. The old expected
bash-hello command is superseded by these real installed consumers; it is not a
second product implementation. Missing prepared inputs fail, not pass/skip.

| Old responsibility | Retained owner | Qualification |
| --- | --- | --- |
| Six Python commands/args and clean/build/install edges | source-build-parity Linux command order | Finite command generation |
| SDK/stdx package paths and archive roots | Original package cases; installed integration | Real-input execution pending |
| Relative links and input-independent bytes | Original link cases; archiveInstall original-path removal and installed integration | Original fixture failures retained; real-input execution pending |
| Public hello/cjpm, macros and relocated compiler consumption | Installed integration via package/verify; sdk-installed-macros replay remains separately registered | Replay is not real production |
| ABI/GC/language/lineage checks | Existing product package/verify callers; no assertion removed | Full installed input still required |

## Installed producer facts

`tools.run` records each completed native producer in
`workspace/build/tools/NAME/build-inputs.json`, alongside the normal build tree.
The source repository/revision is read before that producer starts (cjpm uses
its separately fetched overlay); tracked edits, actual argv, selected build
environment, compiler/target library bytes and the finished output are recorded.
An install-only or partial build reads the old record and checks the bytes; it
does not replace the source with the current default selector. A legacy output
without its original facts remains `source.status=unresolved`.

`TOOLS-INPUTS.json` retains the existing `files`, `commands` and `buildSelection`
fields. Each file now carries `producer.source/build`, `artifact` for retained
bytes, and `entry`/recipe hashes for the actual public launcher. Configuration
payload hashes travel in `payloadFiles`. The native bootstrap target copies
actual runtime/native-check records alongside compiler/std facts. Compiler
payload copies exclude `share/cjcj/build-inputs`, which belongs to the selected
native inputs even when a previous C2 is reused.

`packageInstall` reads those records from the same install it verifies and
archives. `BUILD-MANIFEST.components` separates fixed source objects, build
configuration, retained artifacts and entry bytes; `inputs` identifies the
original installed records. It never derives an old installation's source from
the packaging checkout. Missing HLE/full stdx/cross or old producer facts are not
filled from a new selector, nor does this inventory grant complete SDK status.
Python/cjdb's existing native configuration/import checks remain required; their
observed records travel with the native input, without fabricating Python's
source archive from its version string.

For a runtime archive, `source.commit` stays the fixed Git revision while
`embedded_stamp` is the actual `CJRT-COMMIT:src-<sha256>`. The existing native
producer records its selected fixed repository/revision and configuration,
then observes the installed SO/static pair's actual common stamp. Its ordinary
`RUNTIME-INPUTS.json` travels with the native installation into the SDK. Native
checks and relocated consumers verify source/configuration and the actual pair;
the historical sourceRoot need not remain accessible. No source inventory or
provenance generator is rerun by this recording/receiving step. `CJRT-DECLARED` remains a declaration and never supplies product identity.

The installed Python reader consumes `native-llvm.json.pythonSource` directly.
Its archive URL/version/hash remain archive facts, separate from Git identities.
The reader checks the original producer/configure fields against the native
check's selected Python and verifies all three installed interpreter/header/library
bytes. Missing original facts stay unresolved; malformed facts and changed bytes
are errors. Historical producer paths are diagnostic, not relocation prerequisites.
The same facts pass through BUILD-MANIFEST and RELEASE-MANIFEST without a synthetic
repository, commit, approval or compatibility stamp. Actual native LLVM/LLDB
checks and full SDK validation remain separate obligations.

Runtime records carry the fixed source revision, actual build configuration and
installed SO/archive stamps and bytes. Archive `src-*` stamps remain distinct
from Git revisions. SDK receipt does not walk the tracked source tree, rerun
GenerateRuntimeProvenance or require a synthetic source_materialization command.
Release and toolchain consumers preserve the source and pair checks without a
second materialization-record digest. Existing normal build/publication facts
are consumed as recorded; missing historical commands are not reconstructed.

The registered `runtime-archive-source.integration.mjs` uses the fixed runtime
generator to make a small real native SO/ar pair and exercise the public native
checker; it is not a complete runtime build. `tool-build-facts.integration.mjs`
uses the public source-build CLI with a small native producer and the actual
installer/archive path. Other tool/SDK inputs in that fixture are controlled
boundaries; it does not replace six-tool, Python/cjdb, ABI or full-package gates.

### Native tool source dependencies and installed readiness

`--tools-dependencies /absolute/native-dependencies.json` (or
`CJCJ_NATIVE_TOOL_DEPENDENCIES`) selects the cjlint/cjprof native inputs. The
ordinary JSON maps `json`, `httplib`, `runtime`, `bounds` to
`{repo, commit, path}` with full commits and independent checkout paths. The SDK
prepares missing checkouts once before parallel producers, preserves mismatched
existing trees, and then passes the same file through `build --dependencies`.
First, partial-fetch and warm source selection do not borrow floating branches.
`--jobs` stays the producer's allocated share and JNI consumes that share in the
same producer. `JAVA_HOME` is an actual recorded build environment input.

For an artifact-based source job, `locations.json.nativeToolDependencies` names
a descriptor within that artifact. Its source paths are relative to the
descriptor and must point inside the artifact to the actual fixed Git checkouts.
`configure-gha-inputs` resolves ordinary absolute options into the workspace;
job-handoff carries that file and its source roots under `.srcbuild`. The source
job restores only the explicitly selected Git origin omitted from the handoff's
credential-free Git config. Missing tool inputs do not block N-only preparation,
but the tools stage rejects them rather than inventing repositories or commits.

All normal producer installs precede shared SDK publication. `TOOLS-INPUTS`
records every retained/public executable plus shared libraries/configuration/JNI
payloads and their actual producer. Native shared libraries, JNI and source
configuration are captured at successful build completion and compared again
before/after normal install, so stale dist contents cannot inherit the new
main executable's source. The native and JNI CMake configurations travel with
these build facts. cjprof's body-relative static resources are
also installed beside `.target-tools/tools/bin`, because its HTTP consumer uses
the actual executable location. The known historical cjcompat path remains a required producer; selecting a
tools object without that actual producer fails before shared installation.
The current private integration selects tools
`ec1ab36140ca20d8c181a6d52241ad124db8e8ff` with the existing source override,
while cjpm keeps its independent `3b67c4cc714222cd7f5bea254802e4b37f470087`
selector. This is a new source choice, not the provenance of the nightly host
ELF. Default publication pins remain unchanged until the complete combination
is qualified. cjcompat receives explicit `--sdk` equal to the selected consumer
SDK on native and cross paths; its normal build/install paths are
`cjcompat/build/build/bin/cjcompat` and `cjcompat/dist/bin/cjcompat` (plus the
platform executable suffix). Its AST library/headers remain SDK inputs, not
new cjcompat outputs, and the producer does not rebuild the compiler implicitly.

Native build and install artifacts are recorded separately: normal CMake RPATH
or install-name changes are not falsely rejected as a source change. Source
configuration and the copied JNI output must stay byte-identical; each native
installed payload retains its actual successful build input.

For native Linux cjlint, `--tools-gcc-toolchain /absolute/prefix` (or
`CJCJ_TOOLS_GCC_TOOLCHAIN`) selects Clang's GCC headers/libraries through the
producer's ordinary `build.py --gcc-toolchain`. Choose it to match the selected
SDK's native AST ABI; it is independent of stdx's option and is rejected for
cross/non-Linux targets. Clean and incremental invocations pass the same option;
withdrawing it lets the producer clear its cached selection. Build facts capture
and check `GCC_TOOLCHAIN_FLAG`; install-only reuse retains the original build
configuration. This requires a tools source with the normal cjlint option and
cache reconfiguration support. A passed configuration test is not AST ABI proof.

Official host archives do not have a bootstrap `STAGE-INPUTS.json`. Tool builds
record their actual `bin/cjc`, std-core/runtime and available native AST library
inputs without creating a stage record or modifying that SDK. If bootstrap
stage facts exist, they still select and describe that stage's compiler. Invalid
existing records and missing actual compiler/library files remain failures.

Support libraries use the complete upstream ncurses 6.6 and libedit
20260512-3.1 archives. `install-static-libs` and `run-all` pass their admitted
`--jobs` to each native make. Source extraction and versioned installations are
separate: `sources/<archive-root>`, `ncurses-6.6/usr`, and
`libedit-20260512-3.1`. The old undated `libedit-3.1` prefix is not selected.
Restored caches go through the normal entry again: complete headers/libraries
skip that component, while an incomplete component is configured and installed
normally without rebuilding its complete peer. Libedit's configure consumes
that ncurses prefix. Compiler environment construction uses these same prefixes;
standalone native-CJDB descriptors must select the actual new installation and
run their own affected native link/install gates before claiming that input.
