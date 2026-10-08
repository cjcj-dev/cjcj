# Frozen toolchain SDK inputs

`toolchain-sdk.mjs` accepts one complete frozen plan. `sdk_build.sh` delegates to
that entry; the former loose component flags are rejected. All destinations are
private, initially absent directories. A successful SDK is published by rename
only after its installed bytes and the existing semantic checks pass.

This candidate remains under implementation. The matrix below records the
current adapter coverage; it is not a release qualification or an ABI approval.

## Inputs and identities

The three records have different meanings:

| Record | Meaning | Created by |
| --- | --- | --- |
| `toolchain-sdk-plan-v1` | Frozen sources, configurations, tools and dependency graph | Input freezer or caller before building |
| `toolchain-sdk-output-v1` and `DONE` | Actual successful producer execution and complete artifact inventory | Producer adapter after successful execution |
| `toolchain-sdk-resolved-v1` | Exact output receipts and SDK installation mappings | Resolver after every dependency completes |
| `SDK.lock.json` | Installation membership, original digests and semantic identities | Assembly before validation |

Each plan names `lane`, `role`, `platform`, `stage`, absolute `buildRoot`,
`components`, and `verification`. Components name `id`, `roles`, `domain`,
`source`, `config`, `producer`, `dependencies`, and explicit `install` mappings.
The required component roles are compiler, std, runtime, boundscheck,
llvm-tools, llvm-dylib, ast, cjpm, and official-host. They may share a producer,
but no role may be omitted.

Git sources carry repository, full commit and tree. Official distributions
carry their already published distribution version, root, complete lock digest
and retained-file reason. Distribution inputs belong to the host domain;
they never acquire a fabricated Git source identity. Different repositories
may have different source commits. LLVM tools and dylib in each domain must
declare the same LLVM source and paired runtime dependency.

Resolved component records retain the original producer receipt JSON as well
as its digest. The verifier authenticates those exact original bytes, checks
their source/configuration/dependency closure against the frozen plan and
reconstructs the installation file map from their inventories. An internally
consistent rewritten manifest and lock cannot attribute replacement bytes to
an unchanged producer receipt. This consumes small metadata without rescanning
the producer's payload directory, and remains possible after work collection.

Tools carry physical absolute paths and SHA-256 digests. Configuration includes
host/target and adapter-specific options. The plan cannot contain an executable
shell command or choose an unknown adapter. Schema and graph validation happen
before producer execution. `sdk-manifest.mjs::validatePlan` is the authoritative
versioned field and adapter contract.

An optional input convenience uses the same structure with
`schema=toolchain-sdk-intent-v1`: Git `ref` replaces commit/tree, producer
`ref` is resolved in its explicit repository, and tool/verification digests can
be omitted. The freezer reads and records actual inputs; it does not build or
attribute existing loose artifacts to a source commit.

```text
zx ci/bootstrap/freeze-sdk-plan.mjs --intent intent.json --out new-plan.json
zx ci/bootstrap/toolchain-sdk.mjs --plan new-plan.json --dry-run
zx ci/bootstrap/toolchain-sdk.mjs --plan new-plan.json --out /private/new-sdk
```

Freezing must run where the producer/source repositories and tool paths will
actually be used. Local source paths do not authorize a source transport to a
different machine. The separately reviewed repo sync supplies remote source;
this module does not implement source synchronization.

## Producers and directories

The adapter set is `official`, `sharedbuild-stage1`,
`sharedbuild-runtime-default`, `sharedbuild-runtime-testable`, `bootstrap-std`,
`llvm-tools`, `llvm-dylib`, and `ast-support`. Native adapters reuse the existing
CMake/Ninja, LLVM shim, std `build.py` and `build_ast_support.sh` recipes. The
AST adapter freezes the compiler and nested FlatBuffers source identities and
the official host SDK dependency; it returns the complete archive, headers,
schema and FlatBuffers module inventory needed by the existing std installer.
For compiler revisions whose existing ExternalProject applies the package
mapping patch, declare `flatbuffersTransform: "cangjie-package-mapping-v1"`.
The adapter runs that pinned source script on a private copy before building
and records input, script and expected output digests. Only the exact tracked
`src/idl_gen_cangjie.cpp` result is accepted afterwards; extra changes, different
bytes or mode changes still fail. Both original Git identities remain recorded.
The std build SDK removes the official host LLVM directory before installing
the target tools and dylib; its native binutils remain separate frozen inputs.
The existing LLVM CMake adapter also supports `auxiliaryOnly: true`, producing
the required static `llvm-objcopy` and `llvm-ar` with their own sealed receipt.
Declare that component as `llvm-tools` from the same LLVM commit/tree, map its
`bin` into `third_party/llvm/bin`, and name it in std's
`llvmAuxiliaryDependency` and dependency list. This preserves the strict
ten-payload tuple contract while binding auxiliary tools to their actual source.
Sharedbuild adapters invoke
the existing sharedbuild engine. Their builder is the actual `.mjs` file;
companion shell wrappers cannot substitute an unpinned implementation.

Sharedbuild options declare optimization, parameters, official SDK dependency,
file input bindings, expected outputs, jobs and heap. Each file binding names
a dependency and its sealed relative artifact. The request is emitted inside
the current identity directory. The external `producer.recipe` path is a
retained request hint, not a concurrent mutable input or output authority.

Before any checkout/build, each identity resolves to:

```text
<buildRoot>/<component>/<full source SHA or distribution lock SHA>/<recipe ID>/
  source/ build/ artifacts/ logs/
```

Recipe IDs include configuration, pinned producer and tools, and dependency
build IDs. The physical build root participates until all producers normalize
their path-dependent output. A transported receipt declares its original
`producer.originBuildRoot` and frozen `producer.receiptSha256`; its original
source/build directory record remains byte-identical. The current receipt
directory is a separate entity locator, not a replacement for producer origin.
Sharedbuild also retains its exact native work under
`shared-work/<kind>/<full SHA>/<native recipe ID>`, separately from the sealed
cache. Both the cache key and physical work key use the existing OS lock.
Failed work and original exit codes remain available. Failed components stop
their dependents and do not receive `DONE`. `--resume-failed` is an explicit
same-input recovery request; it never changes the plan or discards failure
evidence. Completed native work can restore a collected success cache.
Ordinary sharedbuild `--copy-to` retains entity integrity validation. Only
`--copy-manifest-to` transfers original digests to the SDK install boundary;
the two modes are mutually exclusive.

Only sealed artifact files are mapped into the SDK. Overlapping destinations,
reserved metadata paths, path escapes and directory links are refused.
Internal file aliases retain the existing compiler alias semantics. Ordinary
installed bytes are hashed once against producer-time digests by `sdk_verify`;
targeted LLVM/runtime/lineage checks remain separate and are not replaced by
the ordinary byte check. Manifest SDK locks cannot be re-created with
`sdk_verify.py --write-lock` after assembly.

## Bootstrap phase handoff

`bootstrap-sdk.mjs` reads either a directory of phase plans or one
`bootstrap-sdk-plans-v1` JSON bundle with `phases`. Current phases are stage0,
stage0-run, std-bootstrap, stage1-initial, stage1-std, and stage3. Every phase
is a complete frozen SDK plan. The bootstrap CLI accepts `--sdk-plans`;
GHA and the kkk2 source-build driver consume `CJCJ_BOOTSTRAP_SDK_PLANS`.
Different std stages use different installation directories. Reuse requires
the same frozen plan, its successful resolved manifest and installed lock to
agree, then runs the same SDK, runtime-pair, LLVM C API and lineage checks as
the initial assembly. Reuse cannot substitute the legacy payload-only check.

`freeze-bootstrap-plans.mjs --intent SIX_PHASE_INTENTS --out NEW_BUNDLE`
resolves every phase's selectors before production. Its intent schema is
`bootstrap-sdk-intents-v1` with exactly the six `phases` keys. All phases must
belong to one lane/platform. The first three use host role, the remaining
three use target role; only stage3 may declare `stage: "final"`.
Both file-bundle and directory consumers require all six valid plans before
selecting a phase. The stage label alone is not final compiler/std qualification;
the pending final adapters must preserve the existing final lineage checks.

CI wiring for phase bundle generation from producer receipts, final compose/handoff
migration and stage2/stage3 producer adapters are still incomplete. Existing
bootstrap source orchestration has not yet all moved into the fixed producer
directories. Do not run the old bootstrap flow with loose artifacts and assume
this candidate has completed those migrations.

## Coverage and remaining qualification

| Platform/caller | Current implementation | Qualification |
| --- | --- | --- |
| Linux x86_64 standalone manifest entry | Sharedbuild seed/runtime/compiler, native LLVM tools/dylib/auxiliary, AST/std, install and existing checks | Genuine host seed and eight-component target SDK assembled and compiled/ran a Cangjie program. Target ordinary-module substitution and LLVM mixing were precisely refused; restoring original producer bytes passed. Native installation ownership was tested against authenticated producer receipts |
| Linux aarch64 | Native LLVM/std adapters; sharedbuild compiler/runtime remain x86_64 | Adapter coverage incomplete |
| Darwin x86_64 / aarch64 | Native LLVM recipe shape exists | Native colour/load verifier and caller migration incomplete; assembly explicitly refuses |
| Windows x86_64 | Declared platform and unknown/unimplemented adapter refusal | Native tuple/static archive adapter and verifier incomplete; assembly explicitly refuses |
| Bootstrap / GHA / kkk2 driver | Frozen phase-plan argument and assembly call routing | Bundle generation and end-to-end execution incomplete |
| Final SDK compose / bootstrap handoff | Existing stage3 install/seal consumers located | Full manifest migration incomplete |
| Existing release target matrix | Existing native/cross target declarations remain | Target adaptations not complete; no Linux result may be extrapolated |

The integration tests use small independently committed C sources with the
real sharedbuild and SDK CLI. They can prove the assembly apparatus and its
identity refusal, not Cangjie compiler or runtime GC behavior.
`sdk-boundary.test.mjs` consumes a retained successful fixture using explicit
`SDK_BOUNDARY_PLAN` and `SDK_BOUNDARY_ROOT` paths. Its producer and consumer
cases preserve the exact frozen plan and original compiled payloads while
substituting one ordinary module. Removing the producer's original-inventory
handoff or the consumer's ordinary digest check changes the actual SDK CLI
result and fails the corresponding target assertion. Both cuts leave the
normal-input control successful and restore the original inputs afterward.
The separate required genuine toolchain validation, legacy assembly caller
migration and native runner matrix remain required. Shared SDKs,
in-flight #863, release/latest approvals and paired ABI holds are unchanged.

The first complete target installation exposed an `installLock()` classification
defect: source-built AST/runtime headers, schema and `cjfilt` fell through to
`official-retain`, whose justification is only present on distribution inputs.
The existing verifier refused that installation with `UNDECLARED`. Classification
now uses the authenticated producer's roles for native files outside the legacy
prefixes. `cjfilt` and the top-level runtime headers belong to the runtime
producer, and AST headers/schema belong to the AST producer. Only distribution
inputs can fall back to official retention; unknown source roles are refused.
The successful original receipts were reused without changing their source
commits or producer identities.

`sdk-real-boundary.test.mjs` consumes a retained genuine target SDK. It
substitutes an ordinary native module and an official LLVM dylib separately,
checks precise refusal and absence of publication, restores original producer
bytes, and invokes the same assembler again. Both cases passed on the genuine
Linux x86_64 SDK. A native-owner case independently reads the frozen runtime
plan and authenticated receipt before assembling a new SDK and observing its
lock. Changing the installer to label native runtime files as AST files fails
that case at the `bin/cjfilt` owner assertion; restoration passes. Disabling the
ordinary digest check similarly fails the genuine substituted-module assertion.
These results qualify those SDK assembly boundaries; the incomplete stage
adapters, legacy assembly callers and other platform rows above still require
implementation and their own execution evidence.
