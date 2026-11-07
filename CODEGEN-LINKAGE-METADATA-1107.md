PROGRESS=DONE · verdict=43317 rejects ill-formed LinkageType metadata and releases entries before the exception ｜尺=installed public cjc plus product ELF interposition N=15 · LANE=opus_driver_parallel_perf_1104
DELIVERY_REF=/mnt/cjcj-nvme/opus_codegen_cost_1107/source|opus/codegen-metadata-opt-1107|43317cc3ad6f8a2a28120a067dcbe9b7ae4bba95
SIDE_EFFECT: private overlay /mnt/cjcj-nvme/opus_codegen_cost_1107/install-43317 and consumer dirs; previous install ELF unchanged
ROLE=implement
EVIDENCE=/mnt/cjcj-nvme/opus_codegen_cost_1107/consumer-43317-1107/results.json,/mnt/cjcj-nvme/opus_codegen_cost_1107/consumer-e358-control-empty-1107/results.json,/mnt/cjcj-nvme/opus_codegen_cost_1107/consumer-e358-control-unknown-1107/results.json,/mnt/cjcj-nvme/opus_codegen_cost_1107/source/packages/codegen/src/EmitPackageIR.cj

Product commit `43317cc3ad6f8a2a28120a067dcbe9b7ae4bba95` on `opus/codegen-metadata-opt-1107`, parent `e3585f2211739c1284a0cf41e3fbe6f592fff7e5`, baseline `1260c69646b3b3224b7e60d9e1723dc36574ca58`. This report records the acceptance run that the blocked session did not finish. It is not a performance result and not a full SDK release.

## FALSIFIED

- `production-result-codegen-incr.json` status FAILED with wall 0.066s is not the 43317 compiler build. `compiler-product.commands.json` records the cjpm build own rc 0, signal null, wall 2940.871s, child 4185277. The built ELF sha256 is `ccafe8fa23434a93734241395cbd810a0e30faeb105caf6085071df26b8acec2`.
- The installed tree at `install/` is still the rejected e358 compiler (`9a2cbb23614215e224ddc555a1937baa547ac8acee426dc752c6c2ea51c30712`). A later private overlay was required before the new ELF could be executed.
- Reusing the native shim is justified by the object bytes, not by the commit field in `compiler-inputs.json`. Both `install/third_party/llvm/fixed-llc/cjselfhost_llvmshim.o` and `shim-install/.../cjselfhost_llvmshim.o` hash to `b759a0332b081d5141c1928134013501b2d3cfb7322cdeebcb53ddfb4730f56a` (274192 bytes). The Cangjie change does not rebuild that object.

## 产品接线证明

Formal consumer is the installed public launcher `bin/cjc`, which reads `bin/cjcj-stage1.entry` and executes `libexec/compiler/cjcj-stage1`. The interposition cases execute that same ELF directly because the public launcher clears `LD_PRELOAD`. Product weight is `SetSymbolLinkageType` in `packages/codegen/src/EmitPackageIR.cj:353` (global) and `:414` (function): `LLVMDisposeValueMetadataEntries` runs before `ParseLinkageTypeString` (`:356`, `:417`) and before the ill-formed-tag exception (`:358`, `:419`).

The precise red arm is `cut-erase` in `/mnt/cjcj-nvme/opus_codegen_cost_1107/consumer-43317-1107/cut-erase/results.json`. The probe skips `LLVMGlobalEraseMetadata` for the LinkageType kind. Compile own rc 0, program stdout `42`, bitcode verify own rc 0, `cutReached` true, and only `finalLinkageMetadataErased` is false (`expectedRed` true). The following `restored` public case, with no probe, has `finalLinkageMetadataErased` true again. The cut is the existing probe, not a product-source edit; the 43317 tree was not rebuilt.

## 承重面清单

Candidate ELF `ccafe8fa…`, public and product paths, one sample each. Command: `node codegen-test-1107.mjs --sdk install-43317 --work consumer-43317-1107 --probe codegen-linkage-probe.so --arm candidate-43317`. Slot `wf-d04f5797-1fe8-4db6-9224-c7cca6fb03cc` test0, core soft/hard 0 via `ulimit -c 0`. Uptime before `09:48:47 load 1.35 6.55 4.93`, after `09:49:12 load 2.59 6.39 4.93`, host up 58 days. Harness own rc 0.

| case | compile own rc | result |
|---|---|---|
| public | 0 | run stdout 42, final bitcode verified, LinkageType count 0 |
| observe-global | 0 | tag read, same final checks |
| observe-function | 0 | tag read, same final checks |
| empty/null/nonstring/unknown × global/function | 1 | diagnostic present, injected entries released, summary targetLive 0 |
| cut-erase | 0 | only the erased-tag assertion is false |
| restored | 0 | public path, LinkageType count 0 |

Unknown-global stack: `ParseLinkageTypeString` at `EmitPackageIR.cj:321` called from `SetSymbolLinkageType` at `:356`, after dispose. Trace: `inject entries=0x7cc6840e0d00` then `dispose entries=0x7cc6840e0d00 injected=1`, summary `live=0 targetLive=0`. Empty-global throws at `:358` with the same dispose-before-exception order.

Control arm, same probe, old install ELF `9a2cbb23…`, slot `wf-b15e9185-6c50-472d-bc10-76f2727ee024`. Uptime before `09:49:50 load 1.58 5.65 4.74`, after `09:49:54 load 3.22 5.92 4.84`.

## 测试增删

No product test files added or removed. The harness and probe already on the CodeGen domain were executed, not edited. Baseline-to-candidate product diff remains `packages/codegen/src/EmitPackageIR.cj` only (`e3585f22` plus `43317cc3`). Untracked `EmitPackageIR.cj.e358.bak` was not committed.

Inherited failures kept, not rerun: invalid IR flags, loader 127, ArrayList `append` diagnostic, and a pipe exit code reported as a compiler rc. No performance claim. No main-branch merge.

CLAIM: On the 43317 ELF, a present but ill-formed LinkageType tag is rejected and the metadata entry array is released before the exception, for both global and function objects.
  METHOD: test
  EVIDENCE: /mnt/cjcj-nvme/opus_codegen_cost_1107/consumer-43317-1107/results.json
  N: 8

CLAIM: The same probe on the installed e358 ELF still accepts an empty tag and still reaches the unknown-string exception before entry release.
  METHOD: control-arm
  EVIDENCE: /mnt/cjcj-nvme/opus_codegen_cost_1107/consumer-e358-control-empty-1107/results.json,/mnt/cjcj-nvme/opus_codegen_cost_1107/consumer-e358-control-unknown-1107/results.json
  N: 2

CLAIM: Skipping LinkageType erase turns only finalLinkageMetadataErased false; compile, run, and bitcode verify stay successful, and the next public run erases the tag again.
  METHOD: test
  EVIDENCE: /mnt/cjcj-nvme/opus_codegen_cost_1107/consumer-43317-1107/cut-erase/results.json,/mnt/cjcj-nvme/opus_codegen_cost_1107/consumer-43317-1107/restored/results.json
  N: 2

CLAIM: Dispose of the entry array is ordered before string parsing and before the ill-formed-tag exception in both loops.
  METHOD: read
  EVIDENCE: /mnt/cjcj-nvme/opus_codegen_cost_1107/source/packages/codegen/src/EmitPackageIR.cj:353,/mnt/cjcj-nvme/opus_codegen_cost_1107/source/packages/codegen/src/EmitPackageIR.cj:414
  N: 0
