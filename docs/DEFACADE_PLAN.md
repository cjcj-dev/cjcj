- Imports/macros/packages are high-risk. Protection: defer their replacement until expression/control-flow coverage is stable; keep facade package handling until real package graph is ready.
- Fallback can mask real regressions. Protection: add path logging/assertions so real-only tests fail if they silently use summary or `RealParseBridge`.

===END===
===DEFACADE-PLAN===

**1. STAGE MAP**

| Stage | Current implementation | Decision point |
|---|---|---|
| Parse | Facade top-level parser. It token-scans into `frontend.File/Decl`; real `parse.Parser` is only used inside `AdaptRealBodies` for supported function bodies. | [CompilerInstance.cj:236](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:236), [CompileStrategy.cj:206](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompileStrategy.cj:206), [CompileStrategy.cj:418](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompileStrategy.cj:418), [RealParseBridge.cj:119](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/RealParseBridge.cj:119) |
| ConditionCompile | Facade local conditional-line filter. No real conditional-compilation package. | [CompilerInstance.cj:252](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:252), [CompileStrategy.cj:46](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompileStrategy.cj:46), [CompileStrategy.cj:1836](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompileStrategy.cj:1836) |
| ImportPackage | Facade import manager and package merge. It builds facade `Package` / `ASTContext`, not real `ast.Package`. | [CompilerInstance.cj:260](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:260), [CompileStrategy.cj:65](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompileStrategy.cj:65), [CompilerInstance.cj:538](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:538), [FrontendModel.cj:1167](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/FrontendModel.cj:1167) |
| MacroExpand | Facade stub/unwrapper. No real macro engine. | [CompilerInstance.cj:268](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:268), [CompileStrategy.cj:71](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompileStrategy.cj:71), [CompileStrategy.cj:1702](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompileStrategy.cj:1702) |
| Sema | Facade semantic checks only. `packages/sema` is not a frontend dependency. | [CompilerInstance.cj:333](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:333), [CompileStrategy.cj:224](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompileStrategy.cj:224), [CompileStrategy.cj:108](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompileStrategy.cj:108), [packages/frontend/cjpm.toml:16](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/cjpm.toml:16) |
| DesugarAfterSema | Facade finalization plus no-op test marking. No real sema desugar. | [CompilerInstance.cj:342](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:342), [CompileStrategy.cj:54](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompileStrategy.cj:54), [FrontendModel.cj:1321](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/FrontendModel.cj:1321) |
| Mangling | Facade `BaseMangler`, simple `_C...` names. | [CompilerInstance.cj:374](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:374), [CompilerInstance.cj:781](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:781), [FrontendModel.cj:1334](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/FrontendModel.cj:1334) |
| CHIR | Real `packages/chir`, but fed by facade `AST2CHIRPackageSpec`, not real AST. | [CompilerInstance.cj:385](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:385), [CodeGenBridge.cj:29](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CodeGenBridge.cj:29), [CodeGenBridge.cj:84](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CodeGenBridge.cj:84), [AST2CHIR.cj:714](/root/cj_build/cangjie_compiler_selfhost/packages/chir/src/AST2CHIR.cj:714) |
| CodeGen | Real `packages/codegen` over real `chir.Package`; facade only activates summary metadata. | [CompilerInstance.cj:480](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:480), [CodeGenBridge.cj:44](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CodeGenBridge.cj:44), [EmitPackageIR.cj:10](/root/cj_build/cangjie_compiler_selfhost/packages/codegen/src/EmitPackageIR.cj:10) |

C++ target shape: parse/sema are real in `CompileStrategy.cpp`, and CHIR is driven from `AST::Package` through `CHIR::ToCHIR`, not a facade spec: [CompileStrategy.cpp:37](/root/cj_build/cangjie_compiler/src/Frontend/CompileStrategy.cpp:37), [CompilerInstance.cpp:945](/root/cj_build/cangjie_compiler/src/Frontend/CompilerInstance.cpp:945), [AST2CHIR.cpp:552](/root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/AST2CHIR.cpp:552).

**2. REAL-PIPELINE COVERAGE**

`parse.Parser` can produce a real `ast.File` for `main(){return 42}`. The parse package re-exports real AST nodes, `Parser.ParseTopLevel()` returns `File`, `ParseTopLevel` constructs a real `File`, and `MAIN` dispatches to `ParseMainDecl`: [ASTCore.cj:22](/root/cj_build/cangjie_compiler_selfhost/packages/parse/src/ASTCore.cj:22), [Parser.cj:21](/root/cj_build/cangjie_compiler_selfhost/packages/parse/src/Parser.cj:21), [ParseDecl.cj:7](/root/cj_build/cangjie_compiler_selfhost/packages/parse/src/ParseDecl.cj:7), [ParseDecl.cj:226](/root/cj_build/cangjie_compiler_selfhost/packages/parse/src/ParseDecl.cj:226), [ParseDecl.cj:446](/root/cj_build/cangjie_compiler_selfhost/packages/parse/src/ParseDecl.cj:446).

But `chir.AST2CHIR` cannot lower that real `ast.File` today. The self-host CHIR entry accepts `AST2CHIRPackageSpec`; there is no `ast.Package` lowering entry and no `cangjie_compiler::ast` import in `packages/chir/src`. Current CHIR construction starts by converting facade `frontend.Package` into specs: [AST2CHIR.cj:645](/root/cj_build/cangjie_compiler_selfhost/packages/chir/src/AST2CHIR.cj:645), [AST2CHIR.cj:714](/root/cj_build/cangjie_compiler_selfhost/packages/chir/src/AST2CHIR.cj:714), [CodeGenBridge.cj:84](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CodeGenBridge.cj:84).

So if the facade were removed today, no program goes fully real end-to-end. First break is between real parse and CHIR: `CompilerInstance.srcPkgs` is facade packages, and `GenerateCHIRForPkg` calls the facade-spec bridge. Codegen itself can lower real CHIR once produced; current passing probes prove that path through `GenPackageModules` works.

Also note: even current `AdaptRealBodies` does not promote pure `return 42` to the real-body path because it returns when `scope.needsRuntime` is false: [RealParseBridge.cj:1313](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/RealParseBridge.cj:1313). Today `return42` is summary/literal lowering, not real AST lowering.

**3. SEMA GAP**

There is no real type checking in the active pipeline. `packages/sema` exists, but frontend does not depend on it, and `FullCompileStrategy.Sema()` calls facade `TypeCheck()`.

The sema entry is `public class TypeChecker`, with `TypeCheckForPackages(pkgs: ArrayList<Package>)`: [TypeChecker.cj:7](/root/cj_build/cangjie_compiler_selfhost/packages/sema/src/TypeChecker.cj:7), [TypeChecker.cj:18](/root/cj_build/cangjie_compiler_selfhost/packages/sema/src/TypeChecker.cj:18). Its current implementation only prepares declaration types; it does not do full expression checking. It synthesizes function types from already-typed params and return types: [TypeChecker.cj:100](/root/cj_build/cangjie_compiler_selfhost/packages/sema/src/TypeChecker.cj:100), [TypeChecker.cj:116](/root/cj_build/cangjie_compiler_selfhost/packages/sema/src/TypeChecker.cj:116). Helpers to map AST type nodes to semantic types exist, but are not wired as a full checker: [TypeCheck.cj:447](/root/cj_build/cangjie_compiler_selfhost/packages/sema/src/TypeCheck.cj:447).

Smallest useful real sema: resolve primitive type nodes, set param/return `Ty`, set `FuncTy` for `MainDecl`/`FuncDecl`, and type literal return bodies for `Int64`, `Bool`, `String`, and `Unit`. That is enough for `main(): Int64 { return 42 }` to flow into a real AST2CHIR cut.

**4. SWITCHOVER POINT**

The current function-level “summary vs real” decision is in `adaptParsedFunc`: unsupported bodies return fallback, supported runtime bodies set `funcDecl.funcBody.hasRealBody = true`: [RealParseBridge.cj:1254](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/RealParseBridge.cj:1254), [RealParseBridge.cj:1313](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/RealParseBridge.cj:1313), [RealParseBridge.cj:1319](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/RealParseBridge.cj:1319). `CodeGenBridge` then chooses `applyRealBody` vs literal/summary lowering: [CodeGenBridge.cj:153](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CodeGenBridge.cj:153), [CodeGenBridge.cj:180](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CodeGenBridge.cj:180), [CodeGenBridge.cj:455](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CodeGenBridge.cj:455).

The real switchover point should be one level higher: `CompilerInstance.GenerateCHIRForPkg`. That is where a stored real `ast.Package` should bypass `BuildRealCHIRForFrontendPackage` and call a new real AST-to-CHIR lowering entry, then append the returned real `chir.Package`: [CompilerInstance.cj:385](/root/cj_build/cangjie_compiler_selfhost/packages/frontend/src/CompilerInstance.cj:385).

Smallest fully real program with least work: `main(): Int64 { return 42 }`. The exact `main(){return 42}` also parses, but needs return-type inference or a default-main-return rule. No existing program is fully real today without adding an AST-to-CHIR entry.

**5. ORDERED CUTS**

1. **Flagged real parse → minimal real AST2CHIR → codegen for `main(): Int64 { return 42 }`.**  
   Scope: add a feature flag and shadow real `ast.Package` storage while still running the facade.  
   Wire/complete: parse source with `parse.Parser.ParseTopLevel`, build a real package, add a tiny `chir` AST lowering entry for `MainDecl`, `ReturnExpr`, and integer literal.  
   Gate: `return42` must run through the real path and return 42; all existing probes still pass through fallback.  
   Size: S/M.

2. **Minimal real sema for primitive function signatures and literal returns.**  
   Scope: wire `packages/sema.TypeChecker` under the real flag for real packages only.  
   Wire/complete: resolve primitive return/param types, set `FuncTy`, type `LitConstExpr` and `ReturnExpr`.  
   Gate: `main(): Int64 { return 42 }` still passes real; `main(): Bool { return 42 }` reports a real sema error, not fallback.  
   Size: M.

3. **Real AST2CHIR for top-level functions and Unit/int returns.**  
   Scope: support `FuncDecl`, `MainDecl`, params, explicit primitive return types, empty/Unit return bodies.  
   Wire/complete: predeclare functions from real AST and emit CHIR function bodies without facade specs.  
   Gate: new real-only function declaration probes pass; old println/arith/factorial/string/while probes remain protected by fallback.  
   Size: M.

4. **Real locals and arithmetic expressions.**  
   Scope: `let`/`var`, refs, assignments, `+ - * / %`, return refs.  
   Wire/complete: expression sema and AST2CHIR lowering for local bindings and primitive binary ops.  
   Gate: real-only `let x = 6 * 7; return x`; existing `println(6*7)` keeps passing even if still fallback.  
   Size: M/L.

5. **Real calls and minimal builtin print/println bridge.**  
   Scope: user function calls, recursion, and `print/println` for `Int64`, `Bool`, `String`.  
   Wire/complete: name resolution for top-level funcs, CHIR call emission, and either real std binding or the current runtime-print ABI as a temporary real lowering target.  
   Gate: `println(string)`, arithmetic println, and factorial must pass; real-path assertions must show calls are not using `RealParseBridge`.  
   Size: L.

6. **Real control flow.**  
   Scope: `if/else`, `while`, `break/continue`, nested conditionals, modulo conditions.  
   Wire/complete: bool condition sema and AST2CHIR basic-block lowering matching existing CHIR/codegen.  
   Gate: while-sum continues passing; FizzBuzz becomes a real-path gate and must no longer produce empty output.  
   Size: L.

7. **Real strings and concat.**  
   Scope: string literals, concat, string println, basic interpolation if needed by probes.  
   Wire/complete: String sema, concat lowering, runtime string ABI alignment with current codegen.  
   Gate: current string concat and println probes pass; add real-only string concat probe.  
   Size: M/L.

8. **Real structs/classes and methods.**  
   Scope: struct fields, constructors, methods, `this`, field read/write.  
   Wire/complete: nominal type sema, member lookup, CHIR nominal layout, method ABI, constructor lowering. Replace the synthetic struct-method path in `RealParseBridge`.  
   Gate: current struct-method empty-output case becomes a real-path passing probe; scalar probes remain unchanged.  
   Size: XL.

9. **Real condition/import/macro/mangle stages.**  
   Scope: replace facade condition compilation, import manager, macro expansion, and mangling with real sibling packages/ports matching C++.  
   Wire/complete: real package graph, `.cj.d` import handling, macro engine, real mangled names.  
   Gate: package/import/macro tests plus all existing probes; fallback stays for source constructs not yet claimed by real path.  
   Size: XL.

10. **Delete facade only after fallback usage is zero on the gated suite.**  
   Scope: remove `FrontendModel` AST duplication, `RealParseBridge`, and spec-only `CodeGenBridge` conversion.  
   Wire/complete: `CompilerInstance` owns real `ast.Package` throughout; CHIR always starts from real AST.  
   Gate: all probes pass with fallback disabled; path logging proves no facade body/spec lowering remains.  
   Size: XL.

**6. RISKS AND PROTECTION**

- False real-path claims can recreate today’s empty-output bugs. Protection: every cut needs a shape detector; unsupported syntax falls back before partial CHIR emission.
- Semantic errors must not be hidden by fallback. Protection: once a construct is claimed by real parse+sema, sema errors are reported instead of retrying facade.
- Type metadata may be missing for AST2CHIR. Protection: sema cut lands before broad AST2CHIR expansion; CHIR checker/dump gates run on each real-path probe.
- Main ABI and return handling can regress. Protection: first gate is exit-code `return42`, matching codegen’s `CreateCJEntryFunction` behavior.
- Imports/macros/packages are high-risk. Protection: defer their replacement until expression/control-flow coverage is stable; keep facade package handling until real package graph is ready.
- Fallback can mask real regressions. Protection: add path logging/assertions so real-only tests fail if they silently use summary or `RealParseBridge`.

===END===
