# Self-Hosting Roadmap

Date: 2026-06-16

This roadmap is based on a source-tree audit of the Cangjie port under
`packages/*/src`, the C++ reference under
`/root/cj_build/cangjie_compiler/src`, and the module reports in
`docs/status/*.md`.

Current headline: the workspace builds, but it is not close to a
production-grade self-host. The port has substantial real code in the
foundational packages, yet the critical compiler path still uses local
compatibility models, summary representations, partial Sema, and a frontend
native-backend gate that stops before bitcode output.

## Current Aggregate

- Overall behavior-faithful self-host estimate: 24%.
- Remaining source self-host markers: 69 total, split as Sema 68 and Driver 1.
- Cangjie source volume: 496 `.cj` files, about 119.5K lines.
- C++ reference source volume: 733 source-like files, about 281.9K lines.
- Required build run: `cjpm build` passes on 2026-06-16, with warnings in
  Parse, Sema, and CodeGen.

Line count is only a coarse signal. Several packages have enough code to build
and exercise local behavior, but still duplicate sibling package APIs or emit
summaries instead of production compiler artifacts.

## Top Risks

1. Sema is the largest open blocker. The reference Sema implementation is about
   96.7K lines across 265 source files; the Cangjie port has about 11.9K lines,
   68 source markers, and 61 short placeholder component files. Full type
   inference, overload resolution, generic constraints, inheritance checking,
   initialization legality, desugaring, CJMP, FFI, plugin checks, and
   expression-specific checking are not complete.
2. Frontend is not wired to real sibling packages. The current package builds
   by carrying local AST/source/diagnostic/option models. The production path
   must call the real Parse, ConditionalCompilation, Modules, Macro, Sema,
   Mangle, CHIR, CodeGen, and incremental packages.
3. CHIR lowering is not production AST-to-CHIR. Current frontend CHIR work
   records declaration summaries, and `packages/chir/src/AST2CHIR.cj` lowers a
   small synthetic package spec rather than the real typed AST.
4. CodeGen is incomplete and not connected to the native pipeline. LLVM is
   correctly kept external through C FFI, but the current frontend/driver path
   has a native bitcode-output gate and many C++ CodeGen surfaces remain
   unported.
5. Modules, macro evaluation, CJO, and serialization use local formats or local
   compatibility layers. They must be replaced by production-compatible
   package loading, flatbuffer/CJO behavior, macro protocol handling, and
   import/cache semantics.

## Milestones To First Self-Compile

### M0: Remove Architectural Isolation

Goal: make the workspace a real compiler graph instead of separately compiling
compatibility islands.

- Update package manifests and imports so AST, Parse, Frontend, Macro, Modules,
  IncrementalCompilation, and related packages use the real sibling package
  APIs.
- Delete duplicate local compatibility definitions only after call sites use the
  real package types.
- Add cross-package smoke tests that parse, conditionally compile, type-check,
  mangle, lower to CHIR, and reach CodeGen through the same object graph.
- Keep LLVM and other native libraries external through C FFI declarations.

Exit criteria:

- No module-local clones of Basic, Lex, AST, Parse, Option, or diagnostic types
  are used when the real package exists.
- A small multi-file Cangjie package can flow through the real frontend stages
  without converting through summary models.

### M1: Complete Parse, AST, Basic, Lex, Option, Utils Contracts

Goal: make the front-end substrate stable enough for Sema and Modules.

- Audit parser behavior against the C++ parser tests, especially recovery,
  macro/quote tokens, annotation lambda forms, CJMP, native FFI annotations,
  optional chains, effect handlers, match/try forms, and operator functions.
- Replace remaining local parser-facing AST/token/source abstractions with the
  real packages.
- Align diagnostics and source ranges with C++ behavior closely enough for test
  parity.
- Finish platform-sensitive Utils and Basic gaps where they affect Driver,
  Modules, diagnostics, or serialization.

Exit criteria:

- The self-host parser can parse the Cangjie compiler port sources and produce
  a real AST package graph with no package-local compatibility types.
- Dump-token and dump-AST modes match the C++ compiler on a representative
  corpus except for documented formatting differences.

### M2: Finish Sema

Goal: type-check the compiler port with production Cangjie semantics.

- Replace all 68 remaining Sema markers with real logic.
- Port the 61 placeholder Sema component files, keeping the C++ file split.
- Complete type inference, overload resolution, calls, generics, constraints,
  inheritance merging, extension checking, pattern usefulness, initialization
  legality, access/mutability, FFI/CJMP/plugin checks, mocks/tests, and
  after-typecheck desugaring.
- Wire Sema diagnostics to Basic diagnostic IDs and source locations.
- Add focused regression tests for each previously placeholder component before
  removing its marker.

Exit criteria:

- The self-host compiler can type-check all `packages/*/src` files in this
  repository.
- No Sema source markers remain.
- C++ and Cangjie Sema agree on accept/reject behavior for the compiler source
  corpus and targeted language tests.

### M3: Production Modules, Macro, CJO, And Incremental Data

Goal: make package import/export, macro expansion, and cache artifacts
compatible with the production compiler.

- Replace module-local AST/Basic/Option models with real package types.
- Implement the real CJO/AST serialization format and flatbuffer schema
  behavior used by the C++ compiler.
- Complete package loading, dependency graph behavior, CJMP common/specific
  loading, reference resolution, and incremental cache compatibility.
- Replace deterministic local macro codecs with the production macro protocol
  and generated-schema behavior.
- Validate stdlib and compiler package imports through the same paths the C++
  compiler uses.

Exit criteria:

- The self-host frontend can load production CJO dependencies needed by the
  compiler source.
- Macro packages expand through native macro libraries and produce AST changes
  equivalent to the C++ compiler.
- Incremental metadata is either production-compatible or disabled cleanly for
  the first bootstrap.

### M4: Complete CHIR And AST Lowering

Goal: lower typed AST to real CHIR for every language feature used by the
compiler and stdlib dependencies.

- Replace summary CHIR generation with real AST-to-CHIR translation.
- Port missing CHIR IR nodes, type definitions, expressions, terminators,
  transformations, analyses, optimizations, serializer/deserializer paths, and
  BCHIR/interpreter behavior required by const eval and macros.
- Validate CHIR checker coverage against the C++ pipeline.
- Add CHIR text/serialization round-trip tests for representative packages.

Exit criteria:

- Typed compiler packages lower to CHIR without summary placeholders.
- CHIR checks pass before CodeGen.
- Constant evaluation and macro-time execution use the production CHIR/BCHIR
  surfaces where the C++ compiler does.

### M5: Complete LLVM CodeGen And Driver Integration

Goal: emit production bitcode/object artifacts through external LLVM C FFI and
let Driver continue into the native backend.

- Connect Frontend/FrontendTool to `codegen.GenPackageModules` and bitcode
  writing instead of writing JSON summaries.
- Remove the Driver frontend-output gate after bitcode output is implemented.
- Complete C++ CodeGen parity for object/class allocation, fields, enums,
  closures, generics, RTTI/type info, package metadata, C/FFI lowering,
  checked casts, exception handling, GC barriers, array initialization,
  intrinsics, debug metadata, incremental generation, and cleanup/optimization
  passes.
- Keep LLVM external through FFI bindings and mirror the C++ LLVM usage rather
  than reimplementing it.

Exit criteria:

- A normal source compile produces LLVM bitcode where the C++ compiler would.
- Driver can link a native executable or library through the existing external
  toolchain path.
- The bitcode and native outputs pass compiler smoke tests.

### M6: Bootstrap And Parity Validation

Goal: produce and trust a first self-hosted compiler.

- Stage 0: use the existing C++ compiler to build the Cangjie compiler port.
- Stage 1: use the produced self-host compiler to rebuild the same source tree.
- Stage 2: rebuild again and compare stable artifacts, allowing only documented
  nondeterministic metadata differences.
- Run the C++ compiler regression corpus and targeted bootstrap tests.
- Add bisectable golden tests for diagnostics, AST dump, CJO, CHIR, bitcode,
  macro expansion, and Driver command lines.

Exit criteria:

- Stage1 and Stage2 outputs are stable enough for release engineering.
- The self-host compiler can build its own packages without falling back to the
  C++ frontend.
- All module completion definitions below are satisfied for the first supported
  target.

## Module Completion Definition

A module should not be marked complete until all of the following are true:

- `cjpm build` passes for the workspace.
- The module has zero remaining source self-host markers.
- The Cangjie file decomposition remains comparable to the C++ component split.
- The module uses real sibling package APIs rather than local compatibility
  copies, except where the C++ reference also owns an equivalent local type.
- The behavior is validated against the C++ implementation with focused tests
  and at least one end-to-end compiler-stage test.
- Any external native dependency used by the C++ compiler remains external and
  is bound through Cangjie FFI.

