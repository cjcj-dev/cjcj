# Fixed LLVM artifacts

`build-llvm-tools.yml` owns the only `fixed-llvm-tools-<platform>` upload job.
`platform-tuples.yml` forwards its subset to that workflow, including calls from
`platform-matrix.yml`, `release.yml`, and `release-matrix.yml`. Both paths use the
same pin, cache key, payload recipe and upload definition for a given platform.
Separate workflow runs still receive distinct GitHub artifact IDs.

`build/lib/targets.mjs` owns the tool runner, LLVM targets, runner glibc version
and portability cache tag. `ci/llvm-tools-matrix.mjs` writes this selection to
`GITHUB_OUTPUT`; workflows do not maintain another runner table.

The native `platforms` input keeps its existing meaning: empty or `all` selects
four native tuples; an explicit comma-separated list can also select Windows.
The `platform_set` input accepts `all` (five tuples), `windows-only`, or
`darwin-windows`. Static tuple publication additionally selects Linux x64 once.
Unknown selections fail before emitting a matrix.

Both Linux tuples use Ubuntu 22.04 (glibc 2.35), retaining the lower of the former
22.04 and 24.04 ARM builder baselines. This records the builder environment, not
an ELF symbol-version measurement or a claim that the #518 portability floor has
been reached. #518 retains ownership of the old sysroot/container and per-file
official SDK comparisons. The upstream environment reference is
`cangjie_build/docs/linux.md:49` (Ubuntu 22.04 example) and `:55-61` (optional
Ubuntu 18.04 images).

All platforms emit the same strict fifteen-field `tuple` manifest, binding the
platform, three source pins, three tools' source/version/hash, linker name and
shim hash. Partial legacy manifests are rejected. Windows can compute every
field from the same pinned sources and its built shim; no field is exempt.
Native dependency and shim checks remain. Windows uses `fetch_sources.sh` and
`build_tuple.sh` under MSYS2, including its LLVM static archives. The unified
cache identity includes both recipes and the target registry, preventing reuse
of the former split recipes.

Contract tests live in `ci/srcbuild/tests/platform-contract.test.mjs`: they execute
the workflow plan command and assert the emitted matrix, caller subsets, and
single upload definition. They do not claim to execute GitHub's scheduler or
rebuild LLVM on every target.
