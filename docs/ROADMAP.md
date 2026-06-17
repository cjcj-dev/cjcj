# Self-Hosting Roadmap

Date: 2026-06-17

This roadmap is based on a source-tree audit of the Cangjie port under
`packages/*/src`, the C++ reference under
`/root/cj_build/cangjie_compiler/src`, and the module reports in
`docs/status/*.md`.

Current headline: the workspace builds and now contains a large amount of real
compiler behavior, but it is not yet a production-grade self-host. The major
remaining work is no longer simple scaffolding removal; it is making the real
packages compose into the same compiler pipeline as the C++ implementation and
then closing semantic, serialization, CHIR, and CodeGen parity gaps.

## Current Aggregate

- Overall behavior-faithful self-host estimate: 50%.
- Remaining source self-host markers: 4 total, all in Sema.
- Cangjie source volume: 526 `.cj` files, about 161.7K lines.
- C++ reference source volume: 728 source-like files, about 282.0K lines.
- C++ reference components without a same-named `.cj` component: 172.
- Required build run: `cjpm build` passes on 2026-06-17.
- Build warnings: 25 total, split as Lex 1, Parse 22, Sema 1, CodeGen 1.

The marker count is now low, but that does not imply self-host readiness. The
status docs still identify non-marker blockers: compatibility models in
Frontend and Macro, production-incompatible serialization formats, incomplete
root Sema orchestration, incomplete AST-to-CHIR lowering, and partial LLVM
CodeGen.

## Top Risks

1. The compiler graph is not yet production-real. Frontend still uses local
   compatibility models for AST, Parse, ConditionalCompilation, Modules, Macro,
   Sema, Mangle, CHIR, and incremental boundaries, so successful package builds
   do not prove end-to-end compiler behavior.
2. Sema remains the largest semantic risk. The port has grown to about 40.4K
   Cangjie lines against 96.9K reference lines, but root type-check/desugar
   scheduling, imported lookup, exact diagnostics, Java/ObjC/native interop,
   mock/test generation, and full overload/inference parity remain below C++.
3. CHIR has a real IR core but not full production lowering. Basename layout
   comparison still finds 74 reference CHIR components without same-named
   `.cj` files, including many AST translation, vtable, const-analysis, inline,
   and optimization components.
4. CodeGen is still a subset. LLVM is correctly external through C FFI, but 21
   reference CodeGen components still lack same-named `.cj` files, including
   CFFI, metadata, incremental generation, overflow, intrinsics, native
   extension metadata, and optimizer components.
5. Modules, Macro, CJO, BCHIR, and incremental artifact formats are not yet
   production-compatible. A self-hosted compiler must read and write the same
   package, macro, bytecode, and cache artifacts the C++ compiler expects.
6. Top-level executable packaging is thin. `packages/cjc/src/Main.cj` is only an
   8-line wrapper; most behavior lives indirectly in Driver and FrontendTool,
   and `main-macrosrv.cpp` / `main-chir-dis.cpp` equivalents are not complete.

## Milestones To First Self-Compile

### M0: Remove Architectural Isolation

Goal: make the workspace a single compiler graph instead of separately
compiling compatibility islands.

- Update package manifests and imports so Frontend, Macro, Modules, CHIR, and
  IncrementalCompilation use the real AST, Parse, Basic, Lex, Option, Sema,
  Mangle, and CHIR types where those packages own the production concepts.
- Delete duplicate compatibility definitions only after all call sites use the
  real package types.
- Add a cross-package smoke path that parses a multi-file package, prunes
  conditional compilation, resolves imports, expands macros, type-checks,
  mangles, lowers to CHIR, and reaches CodeGen through one object graph.
- Keep LLVM and any C++ external native libraries external through Cangjie C FFI
  declarations.

Exit criteria:

- No module-local clone of a sibling package API is used where the real package
  exists.
- A small multi-file Cangjie package flows through real frontend stages without
  converting through summary models.

### M1: Stabilize Front-End Substrate

Goal: make Basic, Utils, Option, Lex, AST, Parse, and ConditionalCompilation
strong enough for production Sema and Modules.

- Run parser and lexer behavior against the C++ parser corpus, especially error
  recovery, macro/quote tokens, annotation lambdas, CJMP, native FFI
  annotations, optional chains, effect handlers, match/try forms, and operator
  declarations.
- Resolve AST/Parse layering for `ScopeKind`, `ExprKind`, diagnostics, and
  source ranges without reintroducing package cycles.
- Finish exact diagnostic/source formatting where downstream tests depend on
  byte-for-byte behavior.
- Clear or justify the current build warnings in Lex and Parse.

Exit criteria:

- The self-host parser can parse the compiler port sources into the real AST
  package graph.
- Dump-token, dump-AST, source ranges, and parser diagnostics match the C++
  compiler on the representative corpus, except for documented intentional
  differences.

### M2: Complete Sema And Desugar

Goal: type-check the compiler port with production Cangjie semantics.

- Replace the four remaining source markers in `TypeChecker.cj` and
  `TestManager.cj` with real logic.
- Wire the root type-checker facade to the real precheck, lookup, type
  synthesis/checking, desugar-before/in/after-typecheck, recursive-type
  elimination, autoboxing, used-import marking, and post-Sema passes.
- Complete imported lookup and package/member access through real Modules types.
- Finish exact overload resolution, generic constraint solving, inheritance
  merging, extension checks, legality checks, FFI/CJMP/plugin checks, mock/test
  generation, Java/ObjC/native interop, and diagnostic emission.
- Add focused regression tests for each formerly marked or compatibility-bodied
  component before marking it complete.

Exit criteria:

- The self-host compiler can type-check all `packages/*/src` files in this
  repository through the same root API the Frontend will call.
- No Sema source markers remain.
- C++ and Cangjie Sema agree on accept/reject behavior for the compiler source
  corpus and targeted language tests.

### M3: Production Modules, Macro, CJO, And Incremental Data

Goal: make imports, macro expansion, and persisted artifacts compatible with
the production compiler.

- Replace module-local and macro-local compatibility AST/decl/file models with
  real package types.
- Implement production-compatible CJO/AST serialization and deserialization,
  including the C++ flatbuffer/schema behavior where applicable.
- Complete package loading, dependency graph behavior, common/specific CJMP
  loading, reference resolution, and import-cache semantics.
- Replace deterministic local macro codecs with the production macro protocol
  and generated schema behavior.
- Make incremental cache artifacts either production-compatible or cleanly
  disabled for first bootstrap.

Exit criteria:

- The self-host frontend loads production CJO dependencies needed by the
  compiler source.
- Macro packages expand through native macro libraries and produce AST changes
  equivalent to the C++ compiler.
- Incremental metadata does not corrupt or hide a full build.

### M4: Complete CHIR And Typed AST Lowering

Goal: lower typed AST to real CHIR for every language feature used by the
compiler and its dependencies.

- Replace CHIR-owned summary input models with real typed AST-to-CHIR
  translation entrypoints.
- Port the missing C++ CHIR translation files, expression classes, vtable and
  metadata generation, checker suite, const analysis, inlining, devirtualization,
  closure conversion, and optimization passes required by the compiler source.
- Replace the versioned textual serializer with production-compatible CHIR/BCHIR
  serialization and deserialization.
- Validate BCHIR/linker/interpreter behavior for compile-time execution,
  constant evaluation, and macro-time execution.

Exit criteria:

- Typed compiler packages lower to CHIR without summary placeholders.
- CHIR checks pass before CodeGen.
- CHIR text/serialization round trips and BCHIR execution match the C++ pipeline
  on representative packages.

### M5: Complete LLVM CodeGen And Driver Integration

Goal: emit production bitcode/object artifacts through external LLVM C FFI and
let Driver continue into the native backend.

- Complete C++ CodeGen parity for C/FFI lowering, native metadata, type info,
  class/object allocation, field and enum layout, closures, generics, checked
  casts, exception handling, GC barriers, array initialization, intrinsics,
  debug metadata, incremental generation, and cleanup/optimization passes.
- Connect Frontend and FrontendTool to real `CodeGen.EmitPackageIR` output
  instead of compatibility summaries.
- Make Driver treat missing requested bitcode/object output as a hard compiler
  error once Frontend/CodeGen claim success.
- Keep LLVM external through Cangjie FFI bindings and mirror the C++ LLVM usage
  rather than reimplementing LLVM.

Exit criteria:

- Normal source compilation produces LLVM bitcode where the C++ compiler would.
- Driver can link a native executable or library through the existing external
  toolchain path.
- The bitcode and native outputs pass compiler smoke tests.

### M6: Complete Executable Packaging

Goal: provide the full set of self-hosted compiler entrypoints, not only the
library packages.

- Expand the `cjc` wrapper and Driver/FrontendTool entries to match
  `main.cpp`, `main-frontend.cpp`, `main-macrosrv.cpp`, and
  `main-chir-dis.cpp` behavior.
- Preserve C++ invocation-name dispatch, frontend subprocess behavior where
  required, macro server behavior, CHIR disassembly, signal/ICE handling, and
  temp-file cleanup semantics.
- Add packaging tests for driver mode, frontend mode, macro server mode, and
  CHIR-dis mode.

Exit criteria:

- The self-hosted binary set exposes every supported C++ compiler entrypoint.
- Entry behavior matches C++ command-line, diagnostics, exit code, and artifact
  behavior on the supported host target.

### M7: Bootstrap And Parity Validation

Goal: produce and trust a first self-hosted compiler.

- Stage 0: use the existing C++ compiler to build the Cangjie compiler port.
- Stage 1: use the produced self-host compiler to rebuild the same source tree.
- Stage 2: rebuild again and compare stable artifacts, allowing only documented
  nondeterministic metadata differences.
- Run the C++ compiler regression corpus and targeted bootstrap tests.
- Add bisectable golden tests for diagnostics, AST dump, CJO, CHIR, bitcode,
  macro expansion, Driver command lines, and executable entrypoints.

Exit criteria:

- Stage1 and Stage2 outputs are stable enough for release engineering.
- The self-host compiler builds its own packages without falling back to the C++
  frontend.
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
