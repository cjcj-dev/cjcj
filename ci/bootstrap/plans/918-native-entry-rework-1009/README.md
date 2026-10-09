# Native executable entry and alias rework (2026-10-09)

This is the retained local #918 / PR919 rework. It is an implementation
candidate awaiting an independent review. It grants no genuine native,
stage1/std/SDK production, main merge, push, formal pin, release or latest.

The actual tested/refrozen producer pair is cjcj
`1364346577da93410908a14a0be0b26bac3c2f49` and tools
`f62511611cde90f5ab4e63b894cccc58afa2ffec`. The cjcj delivery additionally
contains these frozen inputs and documentation; its final delivery identity
is in REPORT-sym_cjcj_918_implement_r6087361232.md. The old cjcj delivery
fb318, producer5d7 and tools b497 remain untouched, with their historical
failures and evidence. The current changes do not authorize merging the
whole original 081486-to-candidate package.

The tools adapter derives executable roles from the native capsule inventory,
resolves executable aliases before wrapping any member, and wraps each actual
authenticated executable once. It preserves relative symlink targets, including
chains and aliases outside bin. The generated wrapper passes the invoked entry
path as native argv[0]; parameters and native exit status remain unchanged.
It uses the target loader, while official cjc/cjc-frontend/cjpm retain the
original official host executable and host loader. No tool/flavor whitelist
selects adapter roles. Original capsule byte/source/recipe, original host lock
and publisher payload guards are unchanged.

The real entry test goes through produceComponent and the actual adapter.
Controlled ELF probes observe argv/exit and actual HOST/TARGET library values;
they do not implement a substitute lld dispatcher. A real installed system
LLD14 observes lld explicit-flavor plus the ELF/Mach-O/COFF/Wasm aliases.
Its provenance is recorded separately: it is not fixed53ce qualification.
The specified old53ce qualification input has no successful native receipt
or lld artifact at the checked producer/output paths. Fixed53ce dispatch,
genuine product and final SDK loading are NOT_RUN. No missing tool was built.

Two new apparatus knives cover the native argv0 consumer and inventory-derived
alias role producer. Each has green/cut/restored rc0/1/0, one target case and
seven explicit skips, eleven native observations and two actual domain controls.
The original b497 comparison retains a passing old domain case while failing
the new entry case. The affected old normal case passes on the new candidate.
The first new qualification failure was a fixture absolute-help-path mismatch;
its original rc/log is retained and its raw real-lld control now uses the same
invoked argv0. Assertions are not normalized or weakened. Unaffected prior
qualification arms are reused with their original identities and limitations.

`stage1.plan.json` is the actual formal freeze output; freeze and dry-run each
returned0. Its identical retained copy is at
`/root/sym_cjcj_918_implement_r6087361232/retained-inputs/native-entry.plan.json`;
the original commands remain in the evidence. It binds the new adapter digest and new producer/dependency build IDs.
The product source4d05592c, LLVM53ce, runtime/std9733 and official compiler174db
identities, original nightly1009 distribution lock and payload remain unchanged.
All seven new genuine receipts are MISSING; no success receipt is synthesized.
Original immutable source/SDK inputs are still referenced under the previous
lane retained-inputs and must remain until an authorized successor materializes
them. Current code/qualification evidence is under the new lane retained/keep.

`acceptance-contract.json` retains the previous exclusive-create transparent
tar, fresh independent unpack, original plan/manifest/lock comparison and
verifyManifestSdk stage1 endpoint. It only rebinds the new plan digest and
private output/code paths. Every production/archive/full-std/CJDB/Python/native
consumer step remains NOT_RUN. Original endpoint and immutable original host
inputs retain their existing paths. ABI/1454/STD_CJC/stage33/release holds remain.

See the lane report and evidence for exact commands, own rc, hashes, checker
limitations, consumer enumeration and the complete candidate span. A fixed53ce
qualified lld input and a reviewed genuine production/resource contract remain
required before real native/stage1/std/SDK production can proceed.
