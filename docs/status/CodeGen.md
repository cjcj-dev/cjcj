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
  modules, builders, primitive/composite/function types, constants, basic arithmetic instructions, calls,
  branches, returns, verification, and bitcode writing. LLVM itself is not reimplemented.
- Added CodeGen-owned LLVM handle wrappers and module/context ownership helpers.
- Added a package-level lowering entry point shaped like the C++ `EmitPackageIR`, including CHIR package splitting,
  per-submodule context/module construction, global and function declaration materialization, function emission
  traversal, verification, and optional bitcode emission.
- Added a C++-shaped `CGModule` with function/global value caches, target triple/data-layout storage, LLVM module
  accessors, intrinsic declaration helpers, and placeholder pass orchestration hooks.
- Added `CGType` interning and concrete type classes for primitive, tuple, function, C string, C pointer, reference,
  array, varray, custom, struct, class, enum, generic, box, and `This` types. The current implementation computes
  LLVM type handles plus conservative size/alignment metadata for the subset exposed by the current CHIR package.
- Added `IRBuilder2` wrappers for selected LLVM builder operations and primitive constants.
- Added expression dispatch structure for constants, unary, binary, memory, terminator, and other expression
  families. Literal constants and basic unary/binary builder operations have concrete lowering; the full CHIR
  expression taxonomy remains marked.

Known gaps:

- This is not a complete faithful port of C++ CodeGen. The full CHIR-to-LLVM lowering surface is still missing:
  allocation, loads/stores, GEPs, calls/invokes, closures, generics, RTTI/type info, metadata, debug info,
  exception paths, overflow/runtime helpers, intrinsics, array/tuple/object construction, casts, C/FFI lowering,
  incremental generation, native backend-specific metadata, and post-generation optimization/cleanup passes.
- Only 39 `.cj` files are present in this pass, compared with 118 reference CodeGen source/header files. Additional
  C++-named component files still need to be split out for `DIBuilder`, `EmitExpressionIR`, `EraseUselessIRs`,
  `LICMOptimizer`, `IRGenerator`, `CGUtils`, `BlockScopeImpl`, incremental generation, Cangjie-native metadata,
  type info, CFFI, and the detailed base expression implementation files.
- The package manifest now depends on the existing self-hosted `basic`, `chir`, `mangle`, `option`, and `utils`
  packages so the CodeGen package can compile against the current CHIR model.
- Remaining CodeGen self-host TODO markers are intentionally compiling stop-points, not completed behavior.

Remaining CodeGen selfhost markers: 20.
