# Self-Hosting Port Status

Date: 2026-06-17

This is the aggregate status for the Cangjie self-hosting compiler port. It
combines the module narratives in `docs/status/*.md` with a live scan of
`packages/*/src` and the read-only C++ reference tree at
`/root/cj_build/cangjie_compiler/src`.

The estimate is behavior-weighted against the C++ compiler, not a line-count
ratio. The port now contains substantial real Cangjie compiler code, but it is
not yet a self-compiling production compiler: the remaining critical path is
mostly package integration, root Sema/Frontend orchestration, production
serialization, full AST-to-CHIR lowering, and complete CHIR-to-LLVM emission.

## Verified integrated capabilities

The integrated pipeline is currently a literal-spec bridge: the frontend scanner
(`packages/frontend/src/CompileStrategy.cj`) recognizes a small set of literal /
compile-time-foldable constructs, threads them through
`FuncBody -> AST2CHIRFunctionSpec -> CHIR Function` (`packages/chir`) and into
codegen (`packages/codegen/src/EmitPrintIR.cj` emits `puts`/`fputs`; literal
returns lower through `CreateLiteralReturnBody`).

The following programs compile with the self-host `cjc`
(`./target/release/bin/cangjie_compiler::cjc`) and run with the verified behavior
shown. Each was re-verified by real compile-and-run on 2026-06-17 after merging
`opus2/int-arith-return`, `opus2/println-int`, `opus3/real-expr`, and
`opus4/control-flow` (var/assign, relational ops, `if`/`while` via real CHIR
blocks) into `main`:

| Source | Verified behavior |
| --- | --- |
| `main(): Int64 { var sum=0; var i=1; while (i<=5){ sum=sum+i; i=i+1 }; return sum }` | exits with code 15, computed at **runtime** by a genuine CHIR `while` loop (no folding; sum 1..10 separately verified -> 55) |
| `main(): Int64 { var x = 2; x = x + 3; return x }` | exits with code 5 (`var` slot + reassignment Store) |
| `main(): Int64 { let a = 7; if (a > 3) { return 1 } else { return 0 } }` | exits with code 1 (real `if`/`else` CHIR blocks + relational branch condition) |
| `main(): Int64 { let a = 2; let b = 3; return a + b }` | exits with code 5, computed at **runtime** by a real CHIR `Add` (not folded) |
| `main() { println("hello selfhost") }` | prints `hello selfhost` + newline |
| `main() { print("a"); print("b"); println("c") }` | prints `abc` + newline |
| `main(): Int64 { return 7 }` | exits with code 7 |
| `main(): Int64 { let x = 42` ⏎ `return x }` | exits with code 42 |
| `main(): Int64 { return 2 + 3 * 4 }` | exits with code 14 (compile-time integer-arithmetic fold) |
| `main() { println(42)` ⏎ `let n = 7` ⏎ `println(n) }` | prints `42` then `7` |

Capability detail:

- println/print of string literals (one or more calls, with/without trailing
  newline).
- `return <int/float/bool/string/unit literal>` and signed integer/float literals
  lowered to the corresponding exit code or value.
- `let <name> = <literal>` folded into a later `return <name>` at brace depth 0
  (single-assignment, literal-initialized immutable bindings only).
- `return <integer-arithmetic expression>` over integer literals, let-bound
  integer literals, and `+ - * / %` with parentheses and unary minus, folded to
  an `Int64` at compile time (conservative: any unsupported token or
  division-by-zero falls back to the single-literal/let-fold path).
- println/print of an integer literal (optionally signed) or a let-bound integer
  literal, emitted as decimal text.
- **First non-facade body lowering (real-expression milestone):**
  `main(): Int64 { let a = 2; let b = 3; return a + b }` now compiles through the
  real recursive-descent parser (`packages/parse`) rather than the token-summary
  scanner. A new additive adapter (`packages/frontend/src/RealParseBridge.cj`)
  runs `parse.Parser(...).ParseTopLevel()`, recognizes a `let`/`let`/`return a+b`
  body, and lowers it to a real CHIR statement list
  (`AST2CHIRStmtSpec` / `CreateRealBody` in `packages/chir`). The body emits
  Allocate/Constant/Store per `let`, Load/Load/`Add`/Store/Exit for the return, so
  the exit code `5` is produced at **runtime** by a genuine CHIR `Add` over two
  `Load`s (`--dump-chir` shows `%N = Add(%a, %b)`), not by frontend constant
  folding. The path is gated behind a `hasRealBody` flag that defaults `false`:
  bodies the summary path already folds to a single literal (e.g. `return 2+3*4`,
  `let x=<lit>; return x`) stay byte-for-byte on their existing path, so none of
  the already-verified slices regress. This is the seam (per
  `docs/DEISOLATION_PLAN.md` section 4) where the token-summary frontend is
  replaced by the real parser one slice at a time.
- **Control-flow milestone (`opus4/control-flow`):** the real body-lowering path
  now compiles, for `Int64` locals, mutable `var`/reassignment, relational
  operators in expressions, and `if`/`while` using genuine CHIR basic blocks plus
  conditional-branch terminators -- still additive and still gated, so any body
  outside the supported real grammar falls back to the summary/fold path with no
  regression. The statement model in `packages/chir/src/AST2CHIR.cj` is now a
  recursive `AST2CHIRExprSpec` (LITERAL / REF / BINARY over arithmetic or
  relational `ExprKind`) and `AST2CHIRStmtSpec` (LET[isVar] / ASSIGN / RETURN /
  IF / WHILE with nested statement lists), replacing the old flat parallel-array
  model. `packages/chir/src/TranslateFuncBody.cj` `CreateRealBody` threads a
  `RealBodyState` (current block, terminated flag, locals map) through a recursive
  lowering: a `var`/`let` is an Allocate slot + Store; reassignment is a Store into
  the existing slot; `if`/`while` emit real CHIR blocks (`if.then`/`if.else`/
  `if.join`, `while.cond`/`while.body`/`while.exit`) with `CreateBranch`/`CreateGoTo`
  terminators; relational ops produce a `Bool`-typed `BinaryExpression` used as the
  branch condition. The real parser adapter (`RealParseBridge.cj`) builds the
  recursive spec tree directly from the parse AST (`VarDecl` let/var, `AssignExpr`,
  `IfExpr` incl. else-if chains, `WhileExpr`, `BinaryExpr`, `ParenExpr`); promotion
  is gated on a body genuinely needing runtime computation (a binary op, var,
  assign, if, or while). Verified at runtime with no folding: while-loop sum 1..5
  -> exit 15 (and 1..10 -> 55); `var x=2; x=x+3` -> 5; `let a=7; if (a>3){1}else{0}`
  -> 1.

These are the only source constructs the integrated pipeline lowers end to end
today; anything else still flows through the compatibility models described
below.

### Remaining de-isolation follow-ups

- **Function calls.** The real body path lowers `let`/`var`/assign/return,
  arithmetic + relational operators, and `if`/`while`, but does not yet lower
  user-defined function calls (call expressions, argument passing, multiple
  function decls in a module). This is the next runtime construct to add.
- **`println` of runtime values.** `println`/`print` still only emit string
  literals or *literal*/let-bound integers through the summary path; printing a
  runtime-computed value (e.g. a loop accumulator or function result) is not yet
  wired through the real body path. Lower `println(<expr>)` to a real call against
  the computed CHIR value.
- **Retire the summary parser.** Once the real parser drives every supported
  construct, remove the frontend token-summary scanner
  (`packages/frontend/src/CompileStrategy.cj` `parseLiteralReturn` /
  `resolveLetLiteral` / `captureFunctionBodyPrints`) and the compile-time
  arithmetic fold, so all bodies flow through `RealParseBridge` ->
  `AST2CHIRStmtSpec` -> `CreateRealBody`.
- Extend the real-body adapter to more statement kinds and types beyond `Int64`
  (other integer/float/bool widths, `for-in`, `match`, early `break`/`continue`).
- Converge `frontend.*` / `parse.*` / `ast.*` (make the bridge consume `ast.*`
  produced from `parse.*`, or have `parse` emit `ast.*` directly) and delete the
  frontend minimal AST (`FrontendModel.cj`).

### De-isolation roadmap pointer

The plan for replacing this literal-spec bridge with a real
`parse -> ast -> CHIR` lowering (starting with a non-folded `let a = 2; let b = 3;
return a + b` slice that exits 5 via a runtime CHIR `Add`) is in
`docs/DEISOLATION_PLAN.md`. Milestone framing is in `docs/ROADMAP.md`.

## Aggregate Totals

| Metric | Value |
| --- | ---: |
| Overall behavior-faithful self-host estimate | 50% |
| Remaining source `TODO(selfhost:*)` markers | 4 |
| Modules with remaining source markers | Sema |
| Cangjie `.cj` files under `packages/*/src` | 526 |
| Cangjie source lines | about 161.7K |
| C++ reference source-like files under `src` | 728 |
| C++ reference source lines | about 282.0K |
| C++ reference components with no same-named `.cj` component | 172 |
| Required build command | `cjpm build` |
| Build result | pass |
| Build notes | 25 warnings: Lex 1, Parse 22, Sema 1, CodeGen 1 |

Only source markers are counted as remaining work markers. Historical mentions
inside `docs/status/*.md` are documentation references, not live source TODOs.

## Module Aggregate

Reference counts exclude `CMakeLists.txt` and include source-like C++ files
with `.cpp`, `.h`, `.hpp`, `.inc`, or `.def` extensions. Cangjie counts include
`.cj` files under each package's `src` directory. "Missing ref components" is a
basename comparison after removing language extensions, so it is a layout
signal rather than a behavior score.

| Module | Package path | Ref files | Ref lines | Cangjie files | Cangjie lines | Missing ref components | Markers | Estimate | Status |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Basic | `packages/basic` | 15 | 5.3K | 19 | 11.8K | 1 | 0 | 80% | Diagnostic/source primitives are substantial and real; path-helper ownership and exact formatting edge cases remain. |
| Utils | `packages/utils` | 26 | 11.6K | 31 | 8.0K | 5 | 0 | 74% | File, Unicode, profiling, signal, hashing, and platform helpers are broad; generated table and non-Linux parity gaps remain. |
| Option | `packages/option` | 3 | 3.2K | 8 | 3.9K | 0 | 0 | 78% | Option parsing/tables/global options are mature; some diagnostics and filesystem-permission behavior remain approximate. |
| Lex | `packages/lex` | 4 | 3.0K | 6 | 3.5K | 0 | 0 | 70% | Real lexer/token implementation builds; warning and corpus-level parser/frontend parity validation remain. |
| AST | `packages/ast` | 19 | 12.0K | 32 | 14.4K | 1 | 0 | 75% | Broad node/type/context/walker/clone/search coverage uses real sibling packages; validation diagnostics and Parse layering remain. |
| Parse | `packages/parse` | 30 | 18.3K | 35 | 8.0K | 1 | 0 | 50% | Real grammar work exists, but several parser functions still show unused parameters and full C++ recovery/corpus parity is not proven. |
| ConditionalCompilation | `packages/conditional_compilation` | 2 | 1.0K | 6 | 1.1K | 0 | 0 | 65% | Conditional pruning/config support is real; exact frontend integration and all directive diagnostics still need validation. |
| Modules | `packages/modules` | 20 | 9.8K | 20 | 4.9K | 0 | 0 | 47% | Import/CJO manager structure exists; production CJO/AST serialization and full package loading are still incomplete. |
| Macro | `packages/macro` | 17 | 7.9K | 19 | 6.9K | 0 | 0 | 46% | Macro flow, native invocation, and codecs are represented; local AST compatibility and non-production serialization remain blockers. |
| MetaTransformation | `packages/meta_transformation` | 2 | 0.0K | 3 | 0.2K | 0 | 0 | 30% | Tiny package with narrow implementation; behavior is CHIR/plugin dependent and not yet production complete. |
| Mangle | `packages/mangle` | 7 | 4.2K | 10 | 5.5K | 0 | 0 | 62% | Broad AST/CHIR mangling support exists; descriptor/generic/CHIR parity depends on downstream completion. |
| Sema | `packages/sema` | 261 | 96.9K | 137 | 40.4K | 68 | 4 | 45% | Many scoped algorithms are now real, but root type-check/desugar orchestration, imported lookup, diagnostics, interop, and mock/test paths remain incomplete. |
| CHIR | `packages/chir` | 147 | 62.8K | 85 | 27.1K | 74 | 0 | 48% | Real IR/checker/analysis/serializer/BCHIR core exists; full AST lowering, expression taxonomy, binary serialization, and many transforms are missing. |
| CodeGen | `packages/codegen` | 118 | 30.8K | 58 | 7.1K | 21 | 0 | 40% | LLVM stays external through C FFI and a real subset lowers to LLVM; CFFI, metadata, closures, generics, exceptions, and optimization coverage remain. |
| IncrementalCompilation | `packages/incremental_compilation` | 11 | 4.6K | 12 | 5.3K | 0 | 0 | 52% | Cache/diff/serialization surfaces are useful; production AST/CJO/CHIR integration and stable artifact semantics remain. |
| Frontend | `packages/frontend` | 8 | 3.0K | 10 | 6.2K | 0 | 0 | 42% | Source/options/lexing and stage structure are real, but AST/Parse/Macro/Sema/Mangle/CHIR/incremental boundaries still use compatibility models. |
| FrontendTool | `packages/frontend_tool` | 3 | 1.2K | 4 | 1.4K | 0 | 0 | 48% | Compiler-instance bridge and result saving exist; CJO/incremental output still follows compatibility summaries. |
| Driver | `packages/driver` | 31 | 5.6K | 30 | 6.0K | 1 | 0 | 70% | Native tool orchestration and platform command builders are substantial; full in-process frontend/codegen handoff and cross-target validation remain. |
| CJC entry wrappers | `packages/cjc` | 4 | 0.6K | 1 | 0.0K | n/a | 0 | 20% | Top-level entrypoints are only lightly represented by the wrapper plus Driver/FrontendTool entry paths. |

## Remaining Source Markers

The live source scan reports four remaining self-host markers, all in Sema:

- `packages/sema/src/TypeChecker.cj`: enum recursive type elimination and autoboxing after instantiation.
- `packages/sema/src/TypeChecker.cj`: post-Sema desugar passes that depend on complete annotations.
- `packages/sema/src/TestManager.cj`: mock support dependency synthesis and accessor generation.
- `packages/sema/src/TestManager.cj`: `createMock` validation and mock class generation.

## Top Gaps

1. Frontend still does not drive the real compiler object graph end to end.
   It uses real Basic/Lex/Option/Utils, but still carries compatibility models
   for AST, Parse, ConditionalCompilation, Modules, Macro, Sema, Mangle, CHIR,
   and incremental boundaries.
2. Sema is the largest semantic blocker. The remaining source TODOs are only
   four, but imported lookup, root type-check/desugar scheduling, exact
   diagnostics, Java/ObjC/native interop checks, mock/test generation, and full
   overload/inference parity are still not production-complete.
3. CHIR needs production typed AST-to-CHIR lowering. The current IR, checker,
   analyses, textual serializer, and BCHIR subset are real, but many C++ named
   translation and optimization components are still absent.
4. CodeGen needs the rest of the CHIR-to-LLVM surface. LLVM is correctly kept
   external through Cangjie FFI, but native metadata, C/FFI lowering, closures,
   generics, exceptions, checked casts, debug metadata, incremental generation,
   and optimization passes remain incomplete.
5. Modules, Macro, CJO, BCHIR, and incremental artifacts are not yet
   production-compatible. Textual or deterministic local formats must be
   replaced by the C++ compiler's real serialization/protocol behavior before a
   self-hosted compiler can consume and produce release artifacts.

## Current Critical Path

1. Remove compatibility islands by wiring packages to real sibling APIs.
2. Make Frontend call the real Parse, ConditionalCompilation, Modules, Macro,
   Sema, Mangle, CHIR, CodeGen, and incremental packages without summary
   conversion layers.
3. Complete root Sema orchestration, imported lookup, diagnostics, interop, and
   the four remaining source TODOs.
4. Replace summary/text CJO, macro, CHIR, BCHIR, and incremental formats with
   production-compatible formats and protocols.
5. Complete typed AST-to-CHIR lowering and CHIR checking for the compiler source
   corpus.
6. Complete LLVM CodeGen and Driver handoff so source compilation always
   materializes the expected bitcode/object artifacts.
7. Bootstrap with Stage0 C++ compiler, rebuild with Stage1 self-host output,
   rebuild again as Stage2, and compare stable outputs against the C++ test
   corpus.

See `docs/ROADMAP.md` for milestone detail.
