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
`opus2/int-arith-return`, `opus2/println-int`, `opus3/real-expr`,
`opus4/control-flow` (var/assign, relational ops, `if`/`while` via real CHIR
blocks), `opus5/func-calls` (user-defined function calls + recursion via
real CHIR `Apply`), and `opus6/print-runtime` (`println`/`print` of a
runtime-computed value) into `main`:

| Source | Verified behavior |
| --- | --- |
| `func add(a: Int64, b: Int64): Int64 { return a + b }` ⏎ `main(): Int64 { return add(2, 3) }` | exits with code 5, computed at **runtime** by a real CHIR `Apply` to the user function `add` |
| `func fact(n: Int64): Int64 { if (n<=1){return 1} else {return n*fact(n-1)} }` ⏎ `main(): Int64 { return fact(5) }` | exits with code 120 via **recursion** (CHIR dump shows recursive `Apply(_Cdefault_fact, ...)` self-calls) |
| `main(): Int64 { var sum=0; var i=1; while (i<=5){ sum=sum+i; i=i+1 }; return sum }` | exits with code 15, computed at **runtime** by a genuine CHIR `while` loop (no folding; sum 1..10 separately verified -> 55) |
| `main() { var s=0; var i=1; while (i<=10){ s=s+i; i=i+1 }; println(s) }` | prints `55` -- the **runtime** loop accumulator, lowered through a real-body PRINT (`printf("%ld\n", <CHIR value>)`), not a folded literal |
| `func fact(n: Int64): Int64 { ... }` ⏎ `main() { println(fact(10)) }` | prints `3628800` -- the **runtime** result of a recursive CHIR `Apply` (value exceeds the 0..255 exit-code clamp, so the printed text is the real evidence) |
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
  literal, emitted as decimal text (summary path).
- println/print of a **runtime-computed `Int64` value** (loop accumulator,
  function-call result, arithmetic over locals/params), emitted via a real
  `printf("%ld"/"%ld\n", <CHIR value>)` at the value's computation point (real-body
  PRINT path; see the runtime-print milestone below).
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
- **Function-calls milestone (`opus5/func-calls`):** the real body-lowering path
  now compiles calls to user-defined top-level functions for `Int64`: value
  arguments, using a call's return value in expressions / `let` / `var` / `return`
  / nested call args (e.g. `add(2, mul(3,4))`), multiple top-level functions in any
  source order, and self-recursion (`fact`, `fib`). It is still additive and gated:
  any construct outside the supported grammar falls back to the summary/fold path
  with no regression. The CHIR spec model (`packages/chir/src/AST2CHIR.cj`) gains a
  `CALL` `AST2CHIRExprSpec` kind carrying a callee source identifier and an ordered
  list of argument expr specs. `TranslateFuncBody.cj` `BindParameterSlots` copies
  each `Int64` parameter into a fresh local slot at entry (so parameter REF /
  reassignment lowers uniformly through the locals map), and `EvalCall` resolves the
  callee `Function` by name and emits a genuine CHIR `Apply` over the evaluated
  argument `Value`s, typed by the callee's return type. `TranslateFuncDecl.cj` splits
  lowering into a body-free `DeclareFunctionShell` plus `EmitFunctionBody` with a
  `PredeclareFunction` step; `LowerPackage` pre-declares every top-level function
  before emitting any body, so a call site resolves its callee regardless of source
  order and for self-recursion. Each parameter now gets a unique `%`-prefixed value
  identifier (fixing a prior bug where every parameter stripped to the same empty
  codegen key, aliasing all arguments to the last one). The real parser adapter
  (`RealParseBridge.cj`) collects top-level function names, recognizes a
  `parse.CallExpr` whose callee is a bare `RefExpr` naming a known function with
  positional `Int64` args (`adaptCall`), and seeds parameters as in-scope locals so
  even a body like `return x` is promoted to the real typed path. Verified at runtime
  (no folding): `add(2,3)` -> 5; `sq(7)` -> 49; `fact(5)` -> 120 (recursion);
  `fib(10)` -> 55; `add(2, mul(3,4))` -> 14; callee declared after `main` -> 10.
- **Runtime-print milestone (`opus6/print-runtime`):** `println(<expr>)` /
  `print(<expr>)` now print a genuinely runtime-computed `Int64` value (a loop
  accumulator, a function-call result, an arithmetic expression over locals/params),
  not just a string literal or a foldable integer. It is additive and gated like the
  prior milestones: a pure string / bare-int-literal print argument still flows through
  the already-verified summary print side-channel (byte-for-byte unchanged), and only a
  print of a value that needs real computation promotes the body to the real path. The
  spec model (`packages/chir/src/AST2CHIR.cj`) gains a `PRINT` `AST2CHIRStmtSpec` kind
  carrying the argument expr and a newline flag. `TranslateFuncBody.cj` `LowerPrint`
  evaluates that expr to a real CHIR `Value` in body flow and records its result
  identifier plus the newline flag on the `Function` (`runtimePrintValueIds` /
  `runtimePrintNewlines` in `Value.cj`). Codegen does not invent a new CHIR expression:
  in `EmitExpressionIR.cj` `MaybeEmitRuntimePrint`, right after each CHIR result Value is
  materialized to an LLVM value, a matching directive triggers a real
  `printf("%ld"/"%ld\n", <that value>)` (`EmitRuntimeIntPrint` in `EmitPrintIR.cj`,
  reusing the proven format-string-global + libc-`printf` machinery), inserted at the
  value's computation point so ordering relative to the surrounding loop/branch is
  correct. A directive is consumed once to avoid double-printing on a repeated value id.
  This milestone also fixed a latent real-body return-type bug: a `main() { ... }` with no
  declared return type previously defaulted to `Int64` on the real path (mismatching its
  `Exit(None)` -> `ret void` terminator, a broken LLVM module). `CodeGenBridge.cj` now
  infers Unit vs `Int64` from the body itself (`realBodyReturnsValue`: does any nested
  `return` carry an expression?) when the frontend summary did not record a return type.
  Verified at runtime (no folding): while-loop sum 1..10 -> prints `55`;
  `println(fact(10))` -> prints `3628800`; `println(sq(7))` -> `49`;
  `print(s); println(s)` after a loop -> `1515` (15 with no newline, then 15 + newline).

These are the only source constructs the integrated pipeline lowers end to end
today; anything else still flows through the compatibility models described
below.

### Remaining de-isolation follow-ups

- **Non-`Int64` print values and `Bool`/`String` runtime values.** The runtime print
  path lowers an `Int64` value to `printf("%ld")`; printing a runtime `Bool`,
  `String`, or other-width integer/float value is not yet wired. Extend
  `EmitRuntimeIntPrint` / the PRINT lowering (format selection + a real `Bool`/string
  runtime representation) once those value types flow through the real body.
- **More operators and statement kinds on the real path.** `for-in`, `match`, early
  `break`/`continue`, logical `&&`/`||`, and compound assignment are still
  unsupported (the body falls back to the summary path). Extend `RealParseBridge` ->
  `AST2CHIRStmtSpec`/`AST2CHIRExprSpec` -> `CreateRealBody`.
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
| Build notes | clean `cjpm build` (0 warnings on a full rebuild) |

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
