# Source-built language tuple (schema 2)

This producer consumes the `final-compiler-linux-x64` stage3 handoff and its
same-build `final-std-linux-x64`, plus the composed SDK and the source-built
compiler runtime manifest. It does not upgrade or relabel H48 schema 1 bytes.

Three runtime roles are explicit:

| Role | Location | Consumer |
|---|---|---|
| Frozen coloured compiler runtime | `compiler-runtime/linux_x86_64_cjnative` | stage3 compiler, through `GC_UNIT_CJC_RUNTIME_LIB_DIR` |
| Official host runtime | `official-host/linux_x86_64_cjnative` | official host tools, through `CJCJ_OFFICIAL_HOST_RUNTIME_LIB_DIR` |
| Runtime under test | supplied at activation, outside the tuple | compiled language tests, through `GCV2_RUNTIME_LIB_DIR` |

A compiler process failure belongs to the frozen compiler-runtime identity.
A generated program failure belongs to the independently selected target
runtime. Record both digests when reporting a gate failure.

The stage3 executable is installed under the basename `cjcj-stage1` solely for
the compiler entry dispatch contract, with the two same-directory aliases
`cjc` and `cjc-frontend`. Its manifest records `production.stage=stage3`; the
filename does not identify its build generation.

`pack` invokes the existing final-compiler consumer before copying files. That
checks the source commit, compiler digest, producer run/attempt and full std
identity. `SOURCE-BUILD.json`, captured before the std build, records its actual
source checkout and compiler/backend/runtime inputs. The final compiler's std
identity includes this receipt.

`verify` needs an externally pinned manifest and compiler digest. `unpack`
additionally needs the archive digest. `activate` verifies the tuple and the
external target pair, copies a private SDK, and emits the separated environment.
No target pair is included in the published archive.

The shipped std is rebuilt with the exact shipped stage3 executable. Its
`compilerSource` and compiler digest must match the final compiler, while
`production.bootstrap.parentSource` explicitly identifies the older bootstrap.
`CJCJ_STAGE3_PHASE=compiler` retains a compiler checkpoint;
`CJCJ_STAGE3_PHASE=std` validates that checkpoint and resumes the std build.
The default `all` completes both in that order. Language-tuple builds retain
the source compiler version without editing its source declaration.

`.github/workflows/source-language-tuple.yml` runs on master pushes, a six-hour
schedule, and manual dispatch. It resolves runtime main once, builds the frozen
compiler runtime, calls srcbuild, stages a draft prerelease, downloads its exact
asset IDs, and runs the unchanged runtime language gate with an independently
built target runtime. Finalization requires both source heads still to match,
the gate exit code and the generated ELF digests. A moving source head leaves
the draft unpublished. Neither publication step marks a release as latest.

For a retained local compiler checkpoint, use the same source checkout,
bootstrap work, runtime manifest pin and LLVM inputs with
`CJCJ_STAGE3_PHASE=std`. The producer checks their identities before using the
retained executable. The checkpoint lives in `software/stage3-bootstrap.json`;
`software/stage3-compiler.json` is written only after the shipped std completes.
A completed packaging run exposes a release pin with numeric release/asset IDs
and digests; consumers use `publish_source_language_tuple.py fetch --pin ...`
before activation.

Implementation and real-artifact qualification are in progress. This document
is not a claim that a source tuple has been published or passed its language gate.
