# Fused interface mtable/outer-TypeInfo lookup

Run `zx tests/typeinfo_fused_lookup/run.mjs COMPILER SDK OUTPUT` with the candidate public compiler and the SDK
installed from the same paired runtime/LLVM. The runner compiles `main.cj` at `-O0` and `-O2` with `--save-temps`,
runs both executables (`typeinfo_fused_lookup OK`) and checks the backend input IR per function:

- `fusedSite` (generic interface, outer TypeInfo needed): exactly one `llvm.cj.get.mtable.func.outertype` and no
  separate `llvm.cj.get.method.outertype` or `llvm.cj.get.mtable.func`.
- `plainSite` (non-generic interface, no outer TypeInfo): unchanged single `llvm.cj.get.mtable.func`.
- `classSite`: unchanged `llvm.cj.get.vtable.func`.
- `loopSite` (for-in, also run zero-trip), `optionLoop` (`None` with 0 and 5 iterations, `Some`) and `throwingSite`
  (`TryInvoke`, callee throws every second call): the fused lookup stays at the dispatch inside the loop, never in
  the entry block, so every iteration performs its own runtime lookup.

The fused intrinsic has no memory/speculation attributes, so LLVM does not hoist or merge it; the LLVM lit test
`CJRuntimeLowering/mtable-outertype-fused.ll` checks that directly. Runtime equality and unload/reload/stable-guard
behaviour of `CJ_MCC_GetMTableAndOuterTI` are covered by the runtime `mtable_api_lifecycle_harness.cpp`.
