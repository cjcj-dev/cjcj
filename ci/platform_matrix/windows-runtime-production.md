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
versions are recorded, rather than treating the rolling package indexes as a
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
