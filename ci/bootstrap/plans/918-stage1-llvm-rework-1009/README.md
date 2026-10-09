# Stage1 same-native LLVM wiring input (2026-10-09)

This is the retained #918 / PR919 local candidate. Genuine native production,
stage1/std assembly, SDK archive and actual consumers are **NOT_RUN**. These
files do not authorize those steps, waive the independent full-span review, or
qualify the new SDK for a formal pin/release/latest.

The product compiler source remains `4d05592c3b0a05b3ab4d554a379e3885faf25cf2`,
LLVM remains `53ce96a7b9d243dc7fa05ff6a9b56ea0ef94c057`, runtime/std remains
`9733dfc09d29eca27d19cc3937a149838b4e3322`, and official compiler source remains
`174db8f40d5efddee63c47a3162bbf676bc227a0`. Official nightly1009 and its original
lock bytes are unchanged. Producer code is independently pinned:

- cjcj `5d7eef2bc2150b315db0df71d72298ca201591a0`, tree
  `820a20c13624ea4a331b81bda60a818f4c0e4818`;
- tools `b497dffaaf9f20c3c71b6911eaf6d854b43caeeb`, tree
  `fd733320dc20cd904c1164bf637446384cc3c878`, based on original d6, only
  `ts/src/sharedbuild/cjcj-stage1.mjs` changed. Original d6 is preserved.

`stage1.plan.json` is the actual formal `freeze-sdk-plan.mjs` result after
retaining real dependencies under this lane's `retained-*` paths. The formal
freeze and dry-run each returned 0. `nonbuild-commands.json` gives original
commands/rc, and `component-matrix.json` gives new actual expected directory and
recipe/dependency IDs. All seven successful receipts are **MISSING**. The old
seven identity rows in `../918-complete-intent-1009/receipt-reuse.json`, old 5e29
input and original failed input/rc have not been rewritten or relabeled.

`targetLlvmDependency` selects one target `llvm-cjdb` producer. The formal
producer derives a deterministic capsule from that producer's original sealed
inventory, including shim, libLLVM, tools, headers, dependencies, metadata and
relative aliases. It authenticates the original official distribution lock,
uses existing sharedbuild `sdk-publish` to make its regular host copy, compares
that publication with the original lock, and keeps the original lock as an
independent input. A publisher lock outside the source root is never forged
into a sharedbuild seal.

The actual stage1 adapter makes its full private link SDK before any compile.
It validates capsule bytes and same-source/recipe metadata, copies the native
shim into the unchanged product's shim path, and makes the unchanged
`packages/codegen/cjpm.toml:13` consume the same native libLLVM through its
`CANGJIE_HOME` expansion. Official cjc/cjc-frontend/cjpm processes use original
host executables and original host loader dependencies. LLVM target tool
wrappers use the target loader. No shared SDK or product compiler/runtime/LLVM
semantics changed. The private link view is not a certified installation and
carries no copied official lock/seal.

Small ELF fixtures went through `produceComponent` and this actual adapter;
only the execution endpoint is a controlled observer. It runs the existing
host publisher, observes actual link argv / ELF dependency / dladdr origin,
and stops with rc73 before completion/sealing. Its projections have no success
output schema/status/rc/DONE and do not claim a 53ce native receipt. Seven
integration cases and two formal-plan cases were exercised in directed
batches. Ten apparatus guards have precise green/cut/restored rc0/1/0. This
qualifies the wiring apparatus; actual product link and actual product loading
remain NOT_RUN. Report and raw evidence provide the per-cut test/source hashes.

`acceptance-contract.json` freezes the existing archive -> new-directory unpack
-> same-plan/manifest/lock `verifyManifestSdk` -> genuine stage1/std/tools/CJDB
consumers. The archive is exclusive-create, preserving file bytes/modes and
contained relative aliases. No package component, schema relaxation,
`package_sdk.mjs`, or release verifier is used for stage1 layout. Successful
manifest/lock bindings cannot be filled until the genuine SDK exists; native
Python path must be uniquely bound from its actual successful inventory before
launch. All archive and consumer steps are explicitly NOT_RUN.

The historical package-description SCHEMA rc1 is correct strict rejection, not
an adapter defect. Existing Linux aarch64, Darwin and Windows adapter/production
limitations remain in scope. Paired ABI/1454, STD_CJC, stage33, formal pin and
release/latest holds remain. Independent review and a separate genuine product
and resource contract are required before production.
