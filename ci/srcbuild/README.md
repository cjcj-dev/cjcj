# Source scheduling

`build/lib/targets.mjs` owns native source cells, runner labels and input readiness.
`node ci/srcbuild/target-matrix.mjs --targets all` lists every selected cell in the
job summary and emits separate runnable and blocked matrices. The source workflow
builds runnable cells and fails a separate reporting job for blocked inputs; it
does not silently remove platforms. The direct single-target workflow checks
readiness before scheduling LLVM or stage0. `release.yml` checks all source cells
before starting its ordered package phases, preserving the full release scope.

Current blockers are Linux aarch64's coloured runtime pin/producer (#763) and
Darwin bootstrap support (#473). Their follow-up links are part of each blocked
cell. These are input readiness declarations, not claims that the complete build
will pass. When a producer lands, update its `sourceBuild.reasons` in the same
change, with evidence for the pin or bootstrap capability; update the scheduling
tests to exercise both the newly runnable cell and remaining blocked cells.

Run `node --test build/test/source-matrix.test.mjs` to exercise the CLI and the
actual workflow planning commands, including mixed requests and blocked-only
requests. Workflow dependency assertions cover the scheduling edges; local tests
do not claim to execute GitHub's scheduler or compile the SDKs.

The same registry owns CI build/provision runners and the platform smoke matrix.
`node ci/target-matrix.mjs ci|platform|arm-soak` exports those workflow inputs;
ARM soak explicitly passes its selected source target to `srcbuild.yml`.
`spec.packageHost` identifies the native package machine, separately from
`spec.nodePlatform`/`nodeArch`, which describe the source build host (Windows
packages run on Windows while their source target is cross-built on Linux).
Target-specific archive, runtime, host LLVM and native tool fields are read from
the registry by their consumers. Artifact names remain the producer/consumer
contract; the unused `final_*` reusable-workflow outputs have been removed.

Run `node --test build/test/target-registry.test.mjs` for workflow dispatch
consumers, per-target archive/runtime/host checks and the audited mapping guard.
