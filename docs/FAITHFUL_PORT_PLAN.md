# Faithful 1:1 C++ Port Plan (supersedes the incremental "real pipeline")

## Directive (2026-06-19)
Faithfully mirror the C++ compiler. NO lazy shortcuts: no hand-special-casing per
construct, no facade, no fallback, no "keep a working subset" crutch. The whole
compiler being unable to build/run for a LONG period is ACCEPTABLE — fidelity to C++
is the only priority. The old gate (build-green + probes every step) is RETIRED; it
is what forced the `RealAST2CHIR` shortcut.

## C++ target shape (recon-confirmed)
- Sema: `TypeChecker::TypeCheckForPackages(pkgs)` → PreCheck → DoTypeCheck → PostTypeCheck.
  Dual-mode `Synthesize`/`Check` dispatch; per-node handlers; mutates AST via `SetTy`.
  Files: src/Sema/{TypeChecker,PreCheck,Collector,LookUpImpl,TypeCheckExpr/*,TypeCheckDecl,
  TypeCheckCall,TypeCheckReference,TypeCheckPattern,TypeCheckMatchExpr,TypeManager}.cpp.
- AST2CHIR: `AST2CHIR::ToCHIRPackage(Package&)`; `Translator::TranslateASTNode` = macro
  switch over `ASTKind` → overloaded `Visit(const AST::XxxExpr&)`; `TranslateType(AST::Ty&)`
  → CHIR `Type`; `globalCache` maps Decl* → CHIR Value*.
  Files: src/CHIR/AST2CHIR/{AST2CHIR,ASTPackage2CHIR,TranslateASTNode/*}.cpp.

## Selfhost current state (recon-confirmed)
- `ast.Ty` (packages/ast/src/Types.cj, 23 subclasses) = faithful, SHARED. Keep.
- Faithful generic Sema EXISTS but is UNWIRED: packages/sema/src/{TypeCheck.cj,
  TypeCheckDecl.cj, TypeCheckExpr/*.cj, TypeCheckCall/Reference/Pattern/Generic/Type/
  MatchExpr.cj, TypeManager...}. The WIRED sema is the shortcut `RealSemaTypeChecker`
  (packages/sema/src/TypeChecker.cj, Int64/Bool/String only), called from
  CompilerInstance.RunRealSema (line ~410-424).
- CHIR is the big gap: NO faithful `TranslateType(ast.Ty)→chir.Type`; the faithful
  `AST2CHIR.cj` is a SPEC shortcut (AST2CHIRExprSpec…), not C++ Visit-dispatch. The
  wired lowering is the hand-rolled `RealAST2CHIR.cj` (3177) + `TranslateFuncBody.cj`
  (1078) using string type-keys. `chir.Type` (packages/chir/src/Type.cj) diverges from
  ast.Ty with no bridge (Island #1).
- CodeGen (packages/codegen) consumes chir.* via LLVM C-FFI; real.

## Phases (dependency order; build may be RED across phases)
- **A — Faithful Sema wired & sole.** Make CompilerInstance.RunRealSema call the faithful
  generic `TypeCheckForPackages` (TypeCheck.cj family), mirroring C++ PreCheck→DoTypeCheck→
  PostTypeCheck. Complete it to faithfully type-check the full language on shared ast.Ty.
  DELETE the `RealSemaTypeChecker` shortcut.
- **B — Faithful `TranslateType(ast.Ty) → chir.Type`.** Port C++ CHIRType::TranslateType;
  the linchpin that collapses Island #1.
- **C — Faithful AST2CHIR.** Port `ToCHIRPackage` + ASTKind dispatch + per-node `Visit`
  handlers consuming ast.Ty via (B), with Decl→Value globalCache. Wire GenerateCHIRForPkg/
  CodeGenBridge to it. DELETE RealAST2CHIR/TranslateFuncBody + spec types.
- **D — Integrate to green.** Rebuild + run; old probes (return42/println/arith/factorial/
  string/while/struct/FizzBuzz/enums/Float64/arrays/xpkg) are the FINAL acceptance targets,
  not per-step gates. Then keep widening faithfully toward self-compile.

## Verification per cut (no end-to-end gate)
Structural fidelity to the corresponding C++ files; composes on the ONE shared rep (no new
islands); the targeted package compiles in isolation where possible; the shortcut it
replaces is deleted (not kept as fallback). Never trust the implementer's self-report —
independently check grep/build/structure.
