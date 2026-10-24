# Native AST installation fields

`native-cjdb.mjs` keeps one ordinary `BUILD-INPUTS.json`. Its new
`astInstallation` member describes the AST portion of that same CMake build and
installation. It does not authorize an SDK, replace the LLVM/Python facts, or
claim that the complete installation consists of four files.

The public producer verifies the C++ source before preparing dependencies, using
the existing `verifyNativeSource` Git or fixed Git archive path. `commits.compiler`
must match the observed source. An archive uses the optional existing-format
`compilerArchive: {file, sha256}` input; no remote is invented for an originless
checkout. The full N/AST build uses the explicitly selected C++ source together.

The normal CMake build now explicitly requests `cangjie-ast-support` with the
existing native targets, then builds all and installs. After successful install,
`nativeAstInstallation` checks the actual cache's source/prefix/std-support option,
the successful configure→target-build→install command order, and membership in
the actual `install_manifest.txt`. It reads the installed files at their normal
paths; it does not copy the AST archive to the installation root.

Fields inside the existing `BUILD-INPUTS.json`:

|Field|Actual source|
|---|---|
|`astInstallation.source.commit`|Observed C++ source commit, matched to `commits.compiler` before dependency preparation|
|`astInstallation.source.root`|Producer source location, diagnostic only; the consumer need not reopen it|
|`astInstallation.source.archive`|When supplied, original fixed Git archive path and digest verified by the existing source checker|
|`astInstallation.platform`|Selected native platform|
|`astInstallation.library`|`lib/<platform>_cjnative/libcangjie-ast-support.a`, relative to this install root|
|`astInstallation.files`|Bytes/SHA256 of the installed AST archive, StdAstFormat schema, generated header and native flatc executable|
|`astInstallation.build.target`|Explicitly executed `cangjie-ast-support` target|
|`astInstallation.build.configuration`|Observed CMake build type/generator/std-support value|
|`astInstallation.build.originalLocations`|Original source/build/install locations retained for interpreting the raw records|
|`astInstallation.build`|Source/configuration/actual command indexes recorded once in BUILD-INPUTS; original CMake files stay in the build tree|
|`astInstallation.build.commandIndexes`|Zero-based configure/build/install positions in this same JSON's existing `commands` array|

The other required members are `schema/StdAstFormat.fbs`,
`include/flatbuffers/StdAstFormat_generated.h` and
`third_party/flatbuffers/bin/flatc[.exe]`. They must occur in the real CMake install
manifest and contain nonempty regular-file bytes. The manifest and cache copies
are original observations, not generated PASS status or a separate receipt.

CI owns the shared `configure-gha-inputs` source selection and SDK reader/copy
changes. It must bind the declared AST repository/commit and the original N
`commits.compiler` to this source, consume `library` inside the same artifact,
preserve the four installed files and original record references, and keep newer
Python/sourceSelection fields. The old flattened AST input layout does not
describe this native CMake installation. The producer change alone does not
complete that consumer integration.

Limited verification uses real CMake/Ninja builds of a tiny C archive for Linux
and a Windows cross target, plus actual install and byte records. Schema/header/
flatc are explicit fixture payloads, and flatc is never run. Tests cover retained
bytes, missing install-manifest membership, failed/missing producer command,
wrong prefix/source, and the real record writer's cut/control/restore. They do
not execute the full `native-cjdb` pipeline or compile the real C++ AST/N; those
remain NOT_RUN until the fixed source combination and official native host are
admitted.

## Source materialization before native CMake

The native producer verifies the selected original Git/archive source, then
composes that tree and the explicitly supplied bounds/flatbuffers inputs into
a private sibling of its build directory. The original source is never changed
by dependency installation. CMake and the AST observations use the stable
composed source path; ordinary source facts retain the original root and commit.
Re-entry repeats the original source check and compares the complete composed
input. User edits to the original, the private input, or a supplied dependency
are retained and rejected instead of erased or accepted by refreshing hashes.
This preparation does not execute or qualify the complete native build.

## Fixed schema successor and the N-only entry

The 2026-10-18 private successor uses C++ commit
`f07c55738c12c154160c313c630a42a73a51025d` (tree
`1c0bedb4bfb8b3fe3d220b6d31be6b5d7c692daa`), based on
`174db8f40d5efddee63c47a3162bbf676bc227a0` through
`9e26e5a989c9c4b2210a7aff7ad60c1c94bb028d`. The complete source difference
retains the Windows flatc executable suffix, generates all five schema headers
in the default CMake build, and installs those generated headers through CMake.
The f07c successor of cad282 also binds schema commands to the executable name
exported by the actual host ExternalProject, including cross target builds.
The fixed source repository is the platform owner's
`/root/cj_build/agent_scratch/impl_platform_delivery_1018/cpp-source`.
Its incremental bundle requires the 9e26 parent; it is not a standalone source
archive and the private commit is not claimed reachable at an official URL.

After normal fixed-object transfer, select the actual reachable repository in
`CJCJ_NATIVE_SOURCE_SELECTION.ast.repository` and f07c in its `commit`.
The public workflow forwards that selection to configure; configure clones or
checks the same repository/commit on re-entry and sets `astCommit`.
For the explicit descriptor entry, supply the same `sourceSelection.ast`,
`astCommit`, and actual `sources.ast` Git checkout. The N producer must use
that checkout as `compiler` and f07c as `commits.compiler`. Its original
`BUILD-INPUTS.json` and AST installation come from that one N build; the SDK
reader compares the N compiler commit, AST source and selected commit, then
reads the original install manifest and installed bytes. No old installation
may be relabelled by changing the selector.

Omitting the selection still means the historical 174db default, not f07c.
That default has the observed missing generated-header installation defect and
is not the R9 successor production input. The explicit native source path does
not alter the old host pin or claim that a private commit was published.

N-only production uses the existing `node ci/bootstrap/native-cjdb.mjs CONFIG`
entry with the full actual dependency configuration. After successful install,
the existing `node ci/bootstrap/sdk-native-input-check.mjs JSON_REQUEST`
runs with `kind: llvm`, the installed N, its LLVM commit, platform, work,
observed `librarySha256`, actual tool probes, and original Python
root/lldbBuild/record/hash fields. The same checker with `kind: ast` uses
f07c, the same LLVM commit, installation and original `buildResult`.
These requests are actual consumer inputs, not prefilled success records.
The full `prepare-bootstrap-plans.mjs` entry additionally requires the real
runtime installation and all fixed Git inputs; N-only does not bypass it or
create a second scheduler.

The platform's actual five-header CMake install/consumer cut is separate
limited evidence. This CI combination has not built a complete f07c N/AST
or a Windows SDK. Source adoption and interface tests do not grant production,
independent review, or GHA qualification.

## Official source writes and re-entry

The immutable selected Git/archive source is checked on every invocation.
The private compiler input is compared as a complete inventory against fresh
composition and the sequential states derived from that source's root
configure_file(COPYONLY) and Flatbuffer ExternalProject PATCH_COMMAND.
The original commands run only on a fresh comparison copy. This preserves the
live generated files and ExternalProject stamps on normal failure recovery;
it never accepts a marker string or an ignored directory as proof of bytes.
Unknown changes in generated and non-generated files remain rejected and
retained. Unsupported rule graphs do not receive a relaxed comparison.
The replay uses the same configured CMake executable as native-cjdb.

The limited test uses fixed f07c rule originals and the real ExternalProject
patch/configure/build/install graph with a small C consumer. It covers both
source forms, failures after each write, completed re-entry and edited input
rejection. This is not a complete native compiler or Windows execution.

An existing native ExternalProject patch stamp requires the post-patch content
state. Rolling the working bytes back to fresh or bounds-only content is
rejected rather than trusting a stamp that would skip the required patch.
