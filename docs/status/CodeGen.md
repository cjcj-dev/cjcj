# CodeGen Port Status

Date: 2026-06-16

Build: `cjpm build` passes.

Reference inspected:

- Public `EmitPackageIR` API under `/root/cj_build/cangjie_compiler/include/cangjie/CodeGen`.
- CodeGen implementation files under `/root/cj_build/cangjie_compiler/src/CodeGen`, including the package,
  context, module, function, IR builder, type hierarchy, expression dispatchers, Cangjie-native type info,
  debug metadata, incremental generation, and cleanup/optimization components.
- The reference inventory is 118 CodeGen source/header files plus CMake metadata, roughly 31K lines.

Implemented:

- Replaced the single CodeGen scaffold with a multi-file Cangjie package covering the main C++ components:
  `EmitPackageIR`, package/function/global emission, `CGPkgContext`, `CGContext`, `CGContextImpl`, `CGModule`,
  `CGFunction`, `IRBuilder`, `IRAttribute`, CHIR expression wrappers, expression dispatchers, constants/common
  definitions, CHIR splitting, and the `CGType` family.
- Added LLVM as an external dependency boundary through Cangjie C FFI declarations for LLVM C handles, contexts,
  modules, builders, primitive/composite/function types, constants, integer and floating arithmetic instructions,
  comparisons, casts, GEPs, calls, branches, returns, attributes, debug locations, global initializers,
  verification, bitcode writing, basic-block/instruction iteration, use-list checks, declaration/global/function
  iteration, deletion APIs, and insertion-point clearing. LLVM itself is not reimplemented.
- Added CodeGen-owned LLVM handle wrappers and module/context ownership helpers.
- Added a package-level lowering entry point shaped like the C++ `EmitPackageIR`, including CHIR package splitting,
  per-submodule context/module construction, global and function declaration materialization, function emission
  traversal, verification, and optional bitcode emission.
- Added a C++-shaped `CGModule` with function/global/local value caches, basic-block mapping, target
  triple/data-layout storage, LLVM module accessors, intrinsic declaration helpers, function-parameter mapping,
  CHIR value materialization, and pass orchestration hooks.
- Added `CGType` interning and concrete type classes for primitive, tuple, function, C string, C pointer, reference,
  array, varray, custom, struct, class, enum, generic, box, and `This` types. The current implementation computes
  LLVM type handles plus conservative size/alignment metadata for the subset exposed by the current CHIR package.
- Added `IRBuilder2` wrappers for selected LLVM builder operations, primitive constants, default literal constants,
  call and invoke construction, bitcasts, address-space casts, aggregate insertion, GEP construction, unreachable
  terminators, and scoped debug-location restoration.
- Added LLVM debug-info initialization via a CodeGen `DIBuilder` component: module debug/DWARF flags, compile-unit
  metadata, package namespace metadata, debug-location creation, finalization, and builder disposal are now driven
  through LLVM C FFI.
- Added Cangjie string-literal global creation and checked arithmetic exception lowering: overflow/arithmetic helper
  functions are resolved from implicit CHIR declarations when available, otherwise inserted as external LLVM runtime
  declarations; the generated literal is passed as a Cangjie string reference, the returned exception object is sent
  to `CJ_MCC_ThrowException`, and the block is terminated with `unreachable`, using `invoke` when an unwind block is
  active.
- Added expression dispatch structure for constants, unary, binary, memory, terminator, and other expression
  families. The current implementation lowers typed constants, unary integer/float operations, signed/unsigned
  and floating binary operations, allocation/load/store/GEP memory expressions, `GOTO`/`BRANCH`/`EXIT`
  terminators, simple call-like expressions, simple aggregate construction, and basic cast/box/unbox forwarding.
- Added two-phase function body emission: all LLVM basic blocks are created and mapped before expression emission,
  and CHIR function parameters are mapped to LLVM arguments before the body is lowered.
- Added global initializer emission for initializer values representable by the current CHIR value materializer.
- Added LLVM enum-attribute attachment helpers for function/call attributes.
- Added a real LLVM CFG cleanup path for generated functions: declarations are skipped, reachable blocks are marked
  from the entry block through LLVM terminator successors, unreachable basic blocks are erased, unused load
  instructions are removed from all blocks, and unused entry-block allocas are removed.
- Added module cleanup/pruning hooks mirroring the C++ phase shape: metadata link-name bookkeeping is cleared,
  unused declarations are removed, stale builder insertion points are cleared, and at `-O2` or above non-coverage
  builds prune unused local/declaration globals and functions while preserving compile-unit globals, metadata-linked
  names, and explicit LLVM-used symbols.

Known gaps:

- This is not a complete faithful port of C++ CodeGen. The remaining full CHIR-to-LLVM surface still includes
  object/class allocation, precise field and enum layout access, closures, generics, RTTI/type info, package and
  native metadata, full debug metadata attachment, broad exception handling, most checked overflow arithmetic,
  intrinsics, complete
  array/tuple/object construction, precise casts, C/FFI lowering, incremental generation, native backend-specific
  metadata, and post-generation optimization/cleanup passes.
- Only 40 `.cj` files are present in this pass, compared with 118 reference CodeGen source/header files. Additional
  C++-named component files still need to be split out for `EmitExpressionIR`, `EraseUselessIRs`,
  `LICMOptimizer`, `IRGenerator`, `CGUtils`, `BlockScopeImpl`, incremental generation, Cangjie-native metadata,
  type info, CFFI, and the detailed base expression implementation files.
- The package manifest now depends on the existing self-hosted `basic`, `chir`, `mangle`, `option`, and `utils`
  packages so the CodeGen package can compile against the current CHIR model.

Remaining CodeGen selfhost markers: 0.

Current CodeGen package size: 40 `.cj` files, approximately 3750 total lines.
