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

Private tool producers can explicitly pair a candidate LLVM with a runtime
without changing the formal `ci/runtime_pin.env` default. Pass all three values
to both `fetch_sources.sh` and `build_tuple.sh`:

```sh
export CJCJ_LLVM_RUNTIME_MODE=private
export CJCJ_LLVM_RUNTIME_URL=https://github.com/cjcj-dev/cangjie-runtime.git
export CJCJ_LLVM_RUNTIME_SHA=4909b2dec1af7f522133c6401e2ce960b0ef511d
# The approved private pairing for this runtime is LLVM
# 20a76c752153ca2f56b3f65b205653f7f60e8869; set LLVM_SHA explicitly as usual.
bash ci/platform_tuples/fetch_sources.sh
bash ci/platform_tuples/build_tuple.sh
```

Do not combine these with `RUNTIME_REF`/`RUNTIME_SRC_URL`. Missing, malformed,
or unapproved private inputs fail before any tuple fetch. A private checkout
must be clean (including untracked files), and its actual HEAD is checked again
before LLVM configure. Fetch errors never fall back to the formal pin. With
these three variables unset, the existing formal pin behavior is preserved.
The existing source mirror transport policy remains available for isolated
local Git fixtures. No release workflow or release pin opts into private mode.
Consumers must bind the approved LLVM/runtime pair and the reviewed cjcj producer
commit themselves; this interface does not authorize publication or runtime use.

`python3 ci/test_llvm_runtime_input.py --work <new-lane-directory>
--runtime-mirror <local-git-tree>` runs real fetch entries against local transports.
The mirror must contain the formal pin and the explicit private commit above.
The build-entry test records the real first CMake arguments and stops there;
it does not claim to configure/build LLVM or run a native GitHub job.

`bash ci/test-llvm-runtime-chain.sh <new-lane-directory> <runtime-mirror>
<other-source-mirror>` passes the same tuple directly from source fetch
to the build entry and checks the runtime HEAD at the emitted CMake path.
