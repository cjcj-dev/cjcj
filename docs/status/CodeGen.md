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
  iteration, deletion APIs, insertion-point clearing, value type/int-width queries through `LLVMTypeOf` and
  `LLVMGetIntTypeWidth`, and intrinsic lookup/declaration/type queries through `LLVMLookupIntrinsicID`,
  `LLVMGetIntrinsicDeclaration`, and `LLVMIntrinsicGetType`. LLVM itself is not reimplemented.
- Added CodeGen-owned LLVM handle wrappers and module/context ownership helpers.
- Added a package-level lowering entry point shaped like the C++ `EmitPackageIR`, including CHIR package splitting,
  per-submodule context/module construction, global and function declaration materialization, function emission
  traversal, verification, and optional bitcode emission.
- Added a C++-shaped `IRGenerator` abstraction with an `IRGeneratorImpl` interface and forwarding wrapper.
  Basic-block, expression, function, and global-variable emission now use concrete generator implementation classes
  matching the reference dispatch structure while preserving their existing public entry points.
- Added a C++-shaped `CGModule` with function/global/local value caches, basic-block mapping, target
  triple/data-layout storage, LLVM module accessors, intrinsic declaration helpers, function-parameter mapping,
  CHIR value materialization, and pass orchestration hooks.
- Added `CGType` interning and concrete type classes for primitive, tuple, function, C string, C pointer, reference,
  array, varray, custom, struct, class, enum, generic, box, and `This` types. The current implementation computes
  LLVM type handles plus conservative size/alignment metadata for the subset exposed by the current CHIR package.
- Added native LLVM named-struct lookup and body emission through C FFI (`LLVMGetTypeByName2` and
  `LLVMStructSetBody`). Fixed runtime metadata and aggregate layouts now receive concrete LLVM struct bodies for
  `ArrayBase`, `BitMap`, `TypeInfo`, `TypeTemplate`, `ExtensionDef`, tuples, raw arrays, varrays, and CHIR
  struct/class instance-variable layouts.
- Added a C++-shaped `CGTypeInfo` component for metadata global handling. Type-info and type-template globals now
  use LLVM get-or-insert behavior through `LLVMGetNamedGlobal`/`LLVMAddGlobal`, cache the result on the owning
  `CGType`, register newly seen static-generic type-info names, and avoid emitting duplicate metadata globals.
- Added `IRBuilder2` wrappers for selected LLVM builder operations, primitive constants, default literal constants,
  call and invoke construction, bitcasts, pointer casts, integer/float extension and truncation, int/float and
  pointer/int conversions, address-space casts, aggregate insertion, GEP construction, unreachable terminators,
  insertion-point inspection/clearing, scoped debug-location restoration, and named LLVM intrinsic declaration/call
  helpers for overloaded and non-overloaded intrinsics.
- Added a C++-shaped `CGUtils` component for pure CodeGen helpers: basic-block naming, class object layout naming,
  compiler-added class mangling, SipHash/`Out64`-style Cangjie string and constant global names through
  `Utils.HashString64`, reference stripping, and generic/class/struct/varray reference predicates. `IRBuilder2`
  string literal globals now use this shared naming path instead of a local decimal `hashCode` conversion.
- Added a C++-shaped `BlockScopeImpl` component using Cangjie `Resource` scopes for block insertion-point
  restoration, function entry-block insertion scopes, and unwind-block stack push/pop. Block scopes restore the
  prior insertion block or clear the insertion point when the builder previously had none.
- Added LLVM debug-info initialization via a CodeGen `DIBuilder` component: module debug/DWARF flags, compile-unit
  metadata, package namespace metadata, debug-location creation, finalization, and builder disposal are now driven
  through LLVM C FFI.
- Added Cangjie string-literal global creation and checked arithmetic exception lowering: overflow/arithmetic helper
  functions are resolved from implicit CHIR declarations when available, otherwise inserted as external LLVM runtime
  declarations; the generated literal is passed as a Cangjie string reference, the returned exception object is sent
  through the patched LLVM `llvm.cj.throw.exception` intrinsic when available with a `CJ_MCC_ThrowException`
  fallback, and the block is terminated with `unreachable`, using `invoke` when an unwind block is active. Added
  `llvm.cj.get.exception.wrapper`/`llvm.cj.post.throw.exception` helpers for catch and rethrow-related lowering.
- Added expression dispatch structure for constants, unary, binary, memory, terminator, and other expression
  families. The current implementation lowers typed constants, unary integer/float operations, signed/unsigned
  and floating binary operations through C++-shaped `ArithmeticOpImpl` and `LogicalOpImpl` components, including
  right-hand shift operand normalization and constant `Unit`/`Nothing` equality, allocation/load/store/GEP memory
  expressions through C++-named `AllocateImpl` and `ArrayImpl` components, `GOTO`/`BRANCH`/`EXIT`
  terminators, `RAISE_EXCEPTION` through the LLVM exception intrinsic path, with-exception call-like/typecast/
  allocation/raw-array-allocation terminators through unwind-block scoped invoke emission and normal-successor
  branching, call-like expressions through a C++-shaped `ApplyImpl` component using call-or-invoke emission,
  `GET_EXCEPTION` through the patched LLVM exception-wrapper intrinsic, raw-array allocation through
  `llvm.cj.malloc.array`/`llvm.cj.malloc.array.generic` with signed negative-size branching to the runtime
  negative-array-size helper, tuple/aggregate and varray construction through C++-named component files, and
  scalar/pointer typecast lowering through a C++-shaped `TypeCastImpl` component with real LLVM numeric conversion
  op selection.
- Added a C++-shaped `EmitExpressionIR` component that emits expression sequences through a local `IRBuilder2`,
  sets the insertion function from the top-level CHIR function, dispatches each expression by major kind, and maps
  non-null results back into `CGModule` with sret result tagging.
- Added entry-reachable two-phase function body emission matching the C++ basic-block generator shape: LLVM basic
  blocks are DFS-created and mapped from the CHIR entry block before expression emission, expressions are emitted in
  a second DFS pass under `CodeGenBlockScope`, and CHIR function parameters are mapped to LLVM arguments before the
  body is lowered.
- Added global initializer emission for initializer values representable by the current CHIR value materializer.
- Added LLVM enum-attribute attachment helpers for function/call attributes.
- Added a C++-shaped `EraseUselessIRs` component for generated module cleanup: declarations are skipped, reachable
  blocks are marked from the entry block through LLVM terminator successors, unreachable basic blocks are erased,
  unused load instructions are removed from all blocks, unused entry-block allocas are removed, unused declarations
  are pruned, stale builder insertion points are cleared, and at `-O2` or above non-coverage builds unused
  local/declaration globals and functions are pruned while preserving compile-unit globals, metadata-linked names,
  and explicit LLVM-used symbols.

Known gaps:

- This is not a complete faithful port of C++ CodeGen. The remaining full CHIR-to-LLVM surface still includes
  object/class allocation, precise field and enum layout access, closures, generics, RTTI/type info, package and
  native metadata, full debug metadata attachment, broad exception handling, most checked overflow arithmetic,
  intrinsics, complete
  array literal/init-by-value content initialization, object construction, full checked casts, C/FFI lowering,
  incremental generation, native backend-specific
  metadata, and post-generation optimization/cleanup passes.
- Only 54 `.cj` files are present in this pass, compared with 118 reference CodeGen source/header files. Additional
  C++-named component files still need to be split out for `LICMOptimizer`, LLVM-specific `CGUtils`,
  incremental generation, Cangjie-native metadata, CFFI, and the detailed base
  expression implementation files.
- The package manifest now depends on the existing self-hosted `basic`, `chir`, `mangle`, `option`, and `utils`
  packages so the CodeGen package can compile against the current CHIR model.

Remaining CodeGen selfhost markers: 0.

Current CodeGen package size: 54 `.cj` files, approximately 5077 total lines.
