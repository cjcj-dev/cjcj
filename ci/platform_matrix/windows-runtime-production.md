# Fixed native Windows runtime production

One `windows-2025` job, 45 minute timeout, four build jobs, MINGW64/MSVCRT
clang and LLD, Unix Makefiles, the existing sccache action (2G cache). This is
runtime-only production: compiler/std/LLVM SDK targets are not built.

Publication is currently held. The first source-only phase used runtime
`65ab0659d0e657c92a9ddabe8a10f8bc22dd2eef`; its proposed publication ref is
superseded by the runtime owner's pending generator/registration successor.
Do not publish or dispatch that old input. Obtain the owner's frozen successor
and review boundary, then update the explicit runtime input after any active
experiment ends. The independently reviewed CI candidate and runtime source
must be published by an authorized role through normal Git refs in
`cjcj-dev/cjcj` and `cjcj-dev/cangjie-runtime`. Verify both remote commits before
explicit dispatch at the candidate ref. Neither publication nor dispatch is
authorized by this document. The old successful run is not this run's evidence.

`actions/checkout` obtains the runtime's tracked sources, including boundscheck
and CJThread. MSYS2 installs the declared MINGW64 packages. Actual package/tool
versions are recorded. The declared `mingw-w64-x86_64-llvm-tools` package
provides the `llvm-readobj` used by the runtime successor's normal CMake
`WINDOWS_EXPORT_READOBJ` lookup and complete COFF export check; this is a host
package tool, not our stopped N candidate. Both objdump and readobj output/rc
are retained. Actual versions are recorded rather than treating the rolling package indexes as a
fixed compiler version. C8ba3/Nde7f are source-only caller-audit coordinates for
the runtime owner, not fetched or executed by this native producer. Their
source qualification does not authorize any compiler/std/SDK production.

The existing `build_runtime.mjs` selects MINGW64 clang, configures LLD through
`windows_runtime_toolchain.cmake`, then runs normal `build.py build/install`.
The linker launcher runs the original linker command, preserves its own rc,
stdout/stderr, response files and immediate output snapshots before unchanged
POST_BUILD publication/export checks. A successful link followed by a failed
contract remains a failed build; install and package are not executed.
The always collector retains raw definitions without rewriting ordinals or DATA,
DLL/import libraries, link inputs, registered definition/references, identities,
complete PE tables, actual dependency images and system dependency identities.
No collector output grants qualification to an input or changes the runtime's
registered JSON/definition.

Once a normal link produced raw/DLL, the always collector runs the runtime
owner's `capture_windows_runtime_definitions.mjs` over the existing CMake
objects and compile database. It retains that reader's own rc/logs and complete
COFF definitions even after a post-link registration rejection. No second build
is performed. Missing capture input or reader failure remains an error; an
earlier failure that never reached link is recorded as NOT_RUN. The runtime
owner receives these inputs for normal collect/write/check. The frozen 4ff248
interface supplies this capture; it is not adopted as a qualified final runtime
while its C03f2 reflection pairing remains open.

After successful normal installation, the public installed verifier keeps the
historical contract and additionally requires all five Reference services.
Packaging archives this installation, extracts into a new directory and invokes
the same verifier with the extracted definition. A failed earlier gate does not
produce a fake successful install/package. A job-level timeout can prevent final
artifact upload; absence of artifacts is not a successful link observation.

The runtime owner consumes actual returned raw/DLL with fixed C/N source callers
through its normal collect/write/check. It owns registration, history (including the explicitly retired, non-reusable NewFinalizer ordinal
277 in the pending successor) and source corrections. Known source errors stop affected production;
this workflow does not split the runtime into alternate libraries or bypass a
post-link gate to create a qualified SDK. No additional matrix is scheduled here.
