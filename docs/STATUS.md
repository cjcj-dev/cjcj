# Self-Hosting Port Status

Date: 2026-06-18

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
shown. Each was re-verified by real compile-and-run on 2026-06-18 (latest: the
`match`-on-`Int64` milestone) after merging
`opus2/int-arith-return`, `opus2/println-int`, `opus3/real-expr`,
`opus4/control-flow` (var/assign, relational ops, `if`/`while` via real CHIR
blocks), `opus5/func-calls` (user-defined function calls + recursion via
real CHIR `Apply`), `opus6/print-runtime` (`println`/`print` of a
runtime-computed value), `opus8/bool` (first-class `Bool` values: literals,
`Bool` locals/params/returns, `&&`/`||`/`!`, relational results as values,
`println(<Bool>)`), `opus9/loops` (`for-in` over `..`/`..=` integer ranges,
`break`, `continue`), `opus11/string` (first-class `String` values:
literals, locals/params/returns, `+` concatenation, `println`/`print` of a
runtime `String`), `opus12/interp` (string interpolation
`"...${expr}..."` of `Int64`/`Bool`/`String` interpolated expressions), and
`opus13/arrays` (first-class `Array<Int64>`: array literals, indexing,
`.size`, element writes, `for-in` over an array, and the sized constructor
`Array<Int64>(n, repeat:/item: v)`), and `opus14/match` (`match` on an `Int64`
selector: literal patterns, wildcard `_`, and a variable-binding pattern, as
both a statement and a value-producing expression) into `main`:

| Source | Verified behavior |
| --- | --- |
| `main(): Int64 { let b = 3 > 2; if (b) { return 1 } else { return 0 } }` | exits with code 1 (relational result stored in a real `Bool` local, then used as a branch condition) |
| `main(): Int64 { let a = true; let b = false; if (a && !b) { return 7 } else { return 0 } }` | exits with code 7 (`Bool` locals + logical `&&` + unary `!` on i1) |
| `func isEven(n: Int64): Bool { return n % 2 == 0 } ` ⏎ `main(): Int64 { if (isEven(10)) {return 1} else {return 0} }` | exits with code 1 (user function with a `Bool` return type, call result used as a branch condition) |
| `main() { println(5 > 3); println(2 > 4) }` | prints `true` then `false` (runtime `Bool` print, selected on the i1) |
| `func add(a: Int64, b: Int64): Int64 { return a + b }` ⏎ `main(): Int64 { return add(2, 3) }` | exits with code 5, computed at **runtime** by a real CHIR `Apply` to the user function `add` |
| `func fact(n: Int64): Int64 { if (n<=1){return 1} else {return n*fact(n-1)} }` ⏎ `main(): Int64 { return fact(5) }` | exits with code 120 via **recursion** (CHIR dump shows recursive `Apply(_Cdefault_fact, ...)` self-calls) |
| `main(): Int64 { var sum=0; var i=1; while (i<=5){ sum=sum+i; i=i+1 }; return sum }` | exits with code 15, computed at **runtime** by a genuine CHIR `while` loop (no folding; sum 1..10 separately verified -> 55) |
| `main(): Int64 { var s=0; for (i in 0..5) { s=s+i }; return s }` | exits with code 10 -- a genuine CHIR `for-in` over the half-open range `[0,5)` (cond/body/inc/exit blocks; `i < end` guard) |
| `main(): Int64 { var s=0; for (i in 1..=5) { s=s+i }; return s }` | exits with code 15 -- inclusive range `[1,5]` (`i <= end` guard) |
| `main(): Int64 { var s=0; for (i in 0..100) { if (i==5){break}; s=s+i }; return s }` | exits with code 10 -- `break` jumps to the loop exit block |
| `main(): Int64 { var s=0; for (i in 0..6) { if (i==3){continue}; s=s+i }; return s }` | exits with code 12 -- `continue` jumps to the increment block (i still advances) |
| `main() { for (i in 0..3) { println(i) } }` | prints `0`/`1`/`2` -- the runtime loop variable printed each iteration |
| `main() { var s=0; var i=1; while (i<=10){ s=s+i; i=i+1 }; println(s) }` | prints `55` -- the **runtime** loop accumulator, lowered through a real-body PRINT (`printf("%ld\n", <CHIR value>)`), not a folded literal |
| `func fact(n: Int64): Int64 { ... }` ⏎ `main() { println(fact(10)) }` | prints `3628800` -- the **runtime** result of a recursive CHIR `Apply` (value exceeds the 0..255 exit-code clamp, so the printed text is the real evidence) |
| `main(): Int64 { var x = 2; x = x + 3; return x }` | exits with code 5 (`var` slot + reassignment Store) |
| `main(): Int64 { let a = 7; if (a > 3) { return 1 } else { return 0 } }` | exits with code 1 (real `if`/`else` CHIR blocks + relational branch condition) |
| `main(): Int64 { let a = 2; let b = 3; return a + b }` | exits with code 5, computed at **runtime** by a real CHIR `Add` (not folded) |
| `main() { let s = "hello"; println(s) }` | prints `hello` -- a `String` local bound from a literal, then printed at runtime (CUT 1) |
| `main() { let a = "foo"; let b = "bar"; println(a + b) }` | prints `foobar` -- runtime `String` concatenation via `+` (CUT 2) |
| `func greet(name: String): String { return "hi " + name }` ⏎ `main() { println(greet("cj")) }` | prints `hi cj` -- a `String` parameter + `String` return + concat across a real CHIR `Apply` (CUT 3) |
| `main() { let x = 42; println("x=${x}") }` | prints `x=42` -- a runtime `Int64` interpolated into a `String` literal (`Int64`->String via `snprintf`, concatenated with the literal parts) |
| `main() { let a=3; let b=4; println("${a} + ${b} = ${a + b}") }` | prints `3 + 4 = 7` -- multiple interpolations including an arithmetic expression, each stringified and concatenated in order |
| `main() { let name="cj"; println("hi ${name}") }` | prints `hi cj` -- a `String`-typed interpolated expression passes through the conversion unchanged |
| `main() { let a = [10,20,30]; println(a[1]) }` | prints `20` -- an `Array<Int64>` literal local, indexed at runtime (CUT 1) |
| `main() { let a = [10,20,30]; println(a.size) }` | prints `3` -- the array length via `.size` (CUT 1) |
| `main(): Int64 { let a=[0,0,0]; a[1]=7; return a[1] }` | exits with code 7 -- an array element write, then read back (CUT 2) |
| `main(): Int64 { let a=[1,2,3,4]; var s=0; for (x in a){ s=s+x }; return s }` | exits with code 10 -- `for-in` iteration over an `Array<Int64>` (CUT 3) |
| `main(): Int64 { let a = Array<Int64>(3, repeat: 7); return a[0]+a[1]+a[2] }` | exits with code 21 -- the sized array constructor fills `n` copies of the literal value (CUT 4) |
| `main() { let a = Array<Int64>(4, item: 5); println(a.size); println(a[2]) }` | prints `4` then `5` -- sized constructor with the `item:` label (CUT 4) |
| `main() { let d=3; match (d) { case 1 => println("one"); case 2 => println("two"); case _ => println("many") } }` | prints `many` -- `match` as a statement with `Int64` literal patterns + wildcard (CUT 1) |
| `main(): Int64 { let x=2; let r = match (x) { case 1 => 100; case _ => 200 }; return r }` | exits with code 200 -- `match` as a value-producing expression bound to a `let` (CUT 2) |
| `main(): Int64 { let x=2; match (x) { case 1 => return 10; case 2 => return 20; case _ => return 0 } }` | exits with code 20 -- `match` arms that `return` directly (CUT 2) |
| `main(): Int64 { let x=7; match (x) { case 0 => return -1; case n => return n + 1 } }` | exits with code 8 -- a variable-binding pattern (`case n =>` binds the selector) (CUT 3) |
| `main() { let ok = 5 > 3; println("ok=${ok}") }` | prints `ok=true` -- a `Bool` interpolated expression stringified to `true`/`false` |
| `main() { println("hello selfhost") }` | prints `hello selfhost` + newline |
| `main() { print("a"); print("b"); println("c") }` | prints `abc` + newline |
| `main(): Int64 { return 7 }` | exits with code 7 |
| `main(): Int64 { let x = 42` ⏎ `return x }` | exits with code 42 |
| `main(): Int64 { return 2 + 3 * 4 }` | exits with code 14 (compile-time integer-arithmetic fold) |
| `main() { println(42)` ⏎ `let n = 7` ⏎ `println(n) }` | prints `42` then `7` |
| `main() { print(1)` ⏎ `print(2)` ⏎ `let y = 1 + 2` ⏎ `println(y) }` | prints `123` + newline -- a body MIXING literal-int prints with a runtime print now fully promotes to the real path (the runtime print is no longer dropped) |
| `main() { println("start")` ⏎ `let n = 6 * 7` ⏎ `println(n) }` | prints `start` then `42` (literal-string print interleaved with a runtime print, in source order) |
| `main() { print("x=")` ⏎ `let v = 5` ⏎ `println(v) }` | prints `x=5` |

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
- **Mixed-print milestone:** a body that MIXES literal prints (integer or plain string)
  with a genuine runtime construct now fully promotes to the real path instead of falling
  back to the summary path and silently dropping the runtime print. Previously
  `RealParseBridge.tryAdaptFunction` bailed whenever the summary scanner had captured any
  `printStrings`, and `adaptPrint` rejected pure-literal arguments -- so
  `main() { print(1); print(2); let y = 1 + 2; println(y) }` fell back and printed `12`
  (the runtime `println(y)` was lost). The adapter now lowers a literal-int print as
  `Print(Literal(v))` and a plain (escape-free) string-literal print as a new
  `PrintStr(text)` `AST2CHIRStmtSpec` kind; neither sets `needsRuntime`, so a body whose
  only statements are literal prints still stays on the byte-for-byte summary path, but
  once any sibling statement is genuinely runtime the whole body promotes and ALL its
  prints lower as ordered in-body calls. `TranslateFuncBody.LowerPrintStr` materializes a
  throwaway anchor `Constant` and records a string directive (`runtimePrintIsStr` /
  `runtimePrintStrings` in `Value.cj`); codegen's `MaybeEmitRuntimePrint` emits a
  `puts`/`fputs` for string directives and the existing `printf("%ld")` for int ones, at
  the anchor's point in body flow. To prevent double-printing, `CodeGenBridge` suppresses
  the entry-block string side-channel entirely when `hasRealBody` is set. Verified:
  `print(1); print(2); let y=1+2; println(y)` -> `123`+newline;
  `println("start"); let n=6*7; println(n)` -> `start` then `42`;
  `print("x="); let v=5; println(v)` -> `x=5`; fully-mixed
  `print("a"); print(1); print("b"); let z=3+4; println(z)` -> `a1b7`.
- **Bool milestone (`opus8/bool`):** the real body-lowering path now models `Bool` as a
  first-class value, not just an inline relational branch condition. Supported: `Bool`
  literals (`true`/`false`), `Bool`-typed `let`/`var` locals, `Bool` function parameters
  and a `Bool` return type, a `Bool` var/param/expr used directly as an `if`/`while`
  condition, logical `&&`/`||` (non-short-circuit `And`/`Or` on i1) and unary `!`,
  relational results used as `Bool` values (stored in a local, returned, passed as an
  argument), and `println`/`print` of a `Bool` (prints `true`/`false`). It is additive and
  gated like the prior milestones: any construct outside the supported real grammar leaves
  `hasRealBody == false` and falls back to the summary path, so the already-verified
  Int64/loop/func/print slices stay byte-for-byte. The spec model
  (`packages/chir/src/AST2CHIR.cj`) gains `BOOL_LITERAL` and `UNARY` `AST2CHIRExprSpec`
  kinds (the existing relational/`AND`/`OR` binary ops already produce `Bool` results).
  `TranslateFuncBody.cj` `CreateRealBody` now infers each value's CHIR type (`Int64` vs
  `Bool`) from the materialized CHIR `Value` and records a per-slot element type
  (`RealBodyState.localTypes`), so slot allocation, `Load`s, and prints stay correctly
  typed and `Bool` locals/params round-trip as i1 (rather than being widened to i64);
  `BindParameterSlots` allocates each parameter slot at the param's declared CHIR type, and
  the generic `AllocateSlot(elemTy)` replaces the old Int64-only allocator. The runtime
  print directive carries a parallel `runtimePrintIsBool` flag (`Value.cj`); codegen's
  `MaybeEmitRuntimePrint` (`EmitExpressionIR.cj`) routes a `Bool` value to a new
  `EmitRuntimeBoolPrint` (`EmitPrintIR.cj`) that emits `printf("%s")` over `"true"`/`"false"`
  string globals selected on the i1. The real parser adapter (`RealParseBridge.cj`)
  recognizes bool literals, `!`, `-`, `&&`, `||`, and `Bool` parameter/return types, and
  promotes such bodies to the real path. Verified at runtime (no folding): `let b = 3 > 2;
  if (b)...` -> exit 1; `let a=true; let b=false; if (a && !b)...` -> exit 7; `let a=false;
  let b=true; if (a || b)...` -> exit 9; `var b=true; b=false; if (b)...` -> exit 0;
  `isEven(10)` (`Bool`-returning function) -> exit 1; `gt(5,2)` returned `Bool` -> exit 4;
  `println(true); println(false)` -> `true`/`false`; `println(5 > 3); println(2 > 4)` ->
  `true`/`false`.
- **Richer-loops milestone (`opus9/loops`):** the real body-lowering path now compiles
  `for-in` loops over integer ranges plus `break`/`continue`. Supported: `for (name in
  start..end)` (half-open `[start,end)`) and `for (name in start..=end)` (inclusive
  `[start,end]`) where the bounds are any supported `Int64` expression (literal, local,
  param, arithmetic, call); `break` and `continue` inside any `for`/`while` loop; and
  arbitrary nesting (a `for` inside a `for`/`while` and vice versa). It is additive and
  gated like the prior milestones: a body using any unsupported construct leaves
  `hasRealBody == false` and falls back to the summary path, so the already-verified
  slices stay byte-for-byte. The spec model (`packages/chir/src/AST2CHIR.cj`) gains `FOR`
  (loop variable name, start/end bound exprs, an inclusive flag, body), `BREAK`, and
  `CONTINUE` `AST2CHIRStmtSpec` kinds. `TranslateFuncBody.cj` desugars a `for-in` to
  genuine CHIR blocks `for.cond` / `for.body` / `for.inc` / `for.exit`: the loop variable
  and the (once-evaluated) end bound get their own slots; `for.cond` loads `i` and the end
  and branches on `i < end` (or `i <= end` for `..=`); `for.body` runs the body and falls
  to `for.inc`, which does `i = i + 1` and back-edges to `for.cond`. A `RealBodyState`
  loop-target stack (`loopBreakTargets` / `loopContinueTargets`, pushed on loop entry and
  popped on exit) resolves `break` to the innermost loop's exit block and `continue` to its
  continue target (a `while`'s cond block, or a `for`'s increment block so `i` still
  advances). The real parser adapter (`RealParseBridge.cj`) recognizes a `parse.ForInExpr`
  with a simple `VarPattern` loop variable iterating a `parse.RangeExpr` (`..` / `..=`,
  via `RANGEOP` / `CLOSEDRANGEOP` tokens) and a `parse.JumpExpr` (`break` / `continue`),
  tracking loop depth so a `break`/`continue` is only promoted inside a loop. Verified at
  runtime (no folding): `for (i in 0..5){s=s+i}` -> exit 10; `for (i in 1..=5){s=s+i}` ->
  exit 15; `for (i in 0..100){if(i==5){break}; s=s+i}` -> exit 10; `for (i in 0..6)
  {if(i==3){continue}; s=s+i}` -> exit 12; `for (i in 0..3){println(i)}` -> `0`/`1`/`2`;
  `while(true){if(i==4){break};...}` -> exit 6; nested `for (i in 0..3){for (j in 0..3)
  {s=s+1}}` -> exit 9.
- **String milestone (`opus11/string`):** the real body-lowering path now models `String`
  as a first-class value, represented end to end as a CString (`i8*`). Three cuts landed,
  all verified by real compile+run: **CUT 1** -- a `String` literal bound to a `let`/`var`
  local and `println`/`print` of that `String` value (`let s = "hello"; println(s)` ->
  `hello`); **CUT 2** -- runtime `String` concatenation with `+`
  (`let a="foo"; let b="bar"; println(a + b)` -> `foobar`, and a `var` reassigned to a
  concat -> `abc`); **CUT 3** -- `String` function parameters and a `String` return type
  across a real CHIR `Apply` (`func greet(name: String): String { return "hi " + name }`
  -> `hi cj`). It is additive and gated like the prior milestones: a body using any
  unsupported construct leaves `hasRealBody == false` and falls back to the summary path,
  so the already-verified Int64/Bool/loop/func/print slices stay byte-for-byte. The spec
  model (`packages/chir/src/AST2CHIR.cj`) gains a `STR_LITERAL` `AST2CHIRExprSpec` kind
  (text -> CString `Constant`); a binary `ADD` whose operands are CString lowers to a
  CString-result concat, and CString values round-trip through CString-typed local slots.
  `TranslateFuncBody.cj` infers the CString element type for `String` slots and records a
  runtime String-value print directive (`runtimePrintIsStr`/value-id machinery extended in
  `Value.cj`). Codegen (`packages/codegen/src/EmitStringIR.cj`, new) materializes a CString
  `StringLiteral` as an `i8*` pointer into a private constant global
  (`EmitCStringLiteralPointer`), lowers a CString-result `ADD` to a runtime concat via libc
  `strlen`/`malloc`/`strcpy`/`strcat` (`EmitCStringConcat`), and prints a runtime `i8*`
  String value via `puts`/`fputs` (`EmitRuntimeStringValuePrint`); `EmitExpressionIR.cj`
  routes a runtime String print to that emitter and `IRBuilder.cj` gains the supporting
  global/cstring helpers. The real parser adapter (`RealParseBridge.cj`) recognizes
  `String` literals, `String`-typed locals/params, `String`-returning calls, and `+`
  concat, mapping the `String` source type to CString so real-body String signatures stay
  consistent; a `String`-valued return promotes the body to the real path. Verified at
  runtime (no folding): `let s="hello"; println(s)` -> `hello`; `let a="foo"; let b="bar";
  println(a + b)` -> `foobar`; `var`-reassigned concat -> `abc`; `greet("cj")` -> `hi cj`;
  bare `String`-literal return -> `hello` (previously crashed in LLVM verify).
- **String-interpolation milestone (`opus12/interp`):** the real body-lowering path now
  lowers a string-interpolation literal (e.g. `"a=${x} b=${y+1}"`) to a `String` built by
  concatenating the literal text parts with the stringified interpolated expressions, in
  source order. Interpolated `Int64` and `Bool` expressions are converted to their textual
  form at runtime (`42` -> `"42"`, `true` -> `"true"`); a `String` interpolated expression
  passes through unchanged. It is additive and gated like the prior milestones: an
  unsupported interpolation shape (escapes in a literal part, a multi-statement
  interpolation block) leaves `hasRealBody == false` and falls back to the summary path, so
  plain `String` literals and the already-verified slices stay byte-for-byte. The spec model
  (`packages/chir/src/AST2CHIR.cj`) gains a `TO_STRING` `AST2CHIRExprSpec` kind wrapping an
  `Int64`/`Bool` sub-expression; `TranslateFuncBody.cj` materializes the operand and, unless
  it is already a CString (a `String` value, which passes through), emits a `UnaryExpression`
  carrying a CString result type as the conversion marker. Codegen
  (`packages/codegen/src/UnaryExprDispatcher.cj`) threads the unary result type through; a
  unary whose result is a CString is the int/bool -> String conversion, emitting a runtime
  `Int64` -> C-string via `malloc` + `snprintf("%ld")` (`EmitIntToCString`) and a `Bool` ->
  C-string by selecting between the `"true"`/`"false"` constant globals (`EmitBoolToCString`,
  in `packages/codegen/src/EmitStringIR.cj`); the resulting `i8*` feeds the existing CString
  concat. The real parser adapter (`RealParseBridge.cj`) maps the parser's
  `StrInterpolationExpr` parts into a left-folded concat of (literal-part `StrLit`,
  `ToStringConv` interpolated expr); an interpolation literal classifies as a `String` value
  so `let`/`var`/`return` and `println`/`print` promote correctly, and
  `plainStringLiteralValue` now excludes interpolated literals so they no longer mis-lower as
  raw text. Verified at runtime (no folding): `let x=42; println("x=${x}")` -> `x=42`;
  `let a=3; let b=4; println("${a} + ${b} = ${a + b}")` -> `3 + 4 = 7`;
  `let name="cj"; println("hi ${name}")` -> `hi cj`; `let ok=5>3; println("ok=${ok}")` ->
  `ok=true`.
- **`Array<Int64>` milestone (`opus13/arrays`):** the real body-lowering path now models a
  first-class `Array<Int64>` as a `VArray<Int64, len>` slot, supporting (CUT 1) array
  literals `[e0, e1, ...]` of `Int64` elements, runtime indexing `a[i]`, and `.size`;
  (CUT 2) element writes `a[i] = e`; (CUT 3) `for-in` iteration over an array
  (`for (x in a) { ... }`, lowered to an index-counted loop bounded by the array length);
  and (CUT 4) the sized constructor `Array<Int64>(n, repeat: v)` / `Array<Int64>(n, item: v)`
  with a literal length and a (pure) `Int64` fill expression. It is additive and gated like
  the prior milestones: a non-`Int64` element type, a non-literal length on the sized
  constructor, or any other array shape leaves `hasRealBody == false` and falls back to the
  summary path, so the already-verified slices stay byte-for-byte. The spec model
  (`packages/chir/src/AST2CHIR.cj`) gains array-literal / index-read / index-write / `.size`
  expr kinds and an `ARRAY_LET` statement; `TranslateFuncBody.cj` allocates the `VArray`
  slot, fills it element-by-element, and lowers index/size/write/for-in against it via the
  CHIR array primitives; the parser adapter (`RealParseBridge.cj`) maps the real parser's
  `ArrayLit` / `SubscriptExpr` (and the `Array<Int64>(...)` call) into these specs. Verified
  at runtime (no folding): `let a=[10,20,30]; println(a[1])` -> `20`; `println(a.size)` ->
  `3`; `let a=[0,0,0]; a[1]=7; return a[1]` -> exit `7`; `let a=[1,2,3,4]; var s=0; for (x in
  a){s=s+x}; return s` -> exit `10`; `Array<Int64>(3, repeat: 7)` summed -> exit `21`;
  `Array<Int64>(4, item: 5)` -> `.size` `4`, `a[2]` `5`.
- **`match`-on-`Int64` milestone (`opus14/match`):** the real body-lowering path now compiles a
  `match` over an `Int64` selector. Three cuts landed, all verified by real compile+run:
  **CUT 1** -- `match` as a STATEMENT with `Int64` literal patterns (`case 1 =>`), a wildcard
  catch-all (`case _ =>`), and each arm an arbitrary block of statements
  (`let d=3; match (d){ case 1 => ...; case 2 => ...; case _ => ... }` -> `many`); **CUT 2** --
  `match` as a value-producing EXPRESSION whose arms each yield a value, usable in `let`/`var`/`return`
  (`let r = match (x){ case 1 => 100; case _ => 200 }; return r` -> exit `200`), including arms that
  `return` directly (`match (x){ case 1 => return 10; case 2 => return 20; case _ => return 0 }` ->
  exit `20`); **CUT 3** -- a variable-binding pattern (`case n =>` binds the selector value to `n`
  in that arm) (`let x=7; match (x){ case 0 => return -1; case n => return n + 1 }` -> exit `8`). It
  is additive and gated like the prior milestones: any unsupported `match` shape (enum / tuple / range
  patterns, a `case L1 | L2` alternation, a `where` pattern guard, a non-`Int64` selector, the
  selector-less `match { case <expr> => }` form, or a catch-all that is not the last arm) leaves
  `hasRealBody == false` and falls back to the summary path, so the already-verified slices stay
  byte-for-byte. The whole milestone is implemented in the real parser adapter
  (`packages/frontend/src/RealParseBridge.cj`) by **desugaring**, so no new CHIR/codegen surface was
  needed: a statement-position `match` lowers to a fresh selector temp (`let $sel = <selector>`,
  evaluating the selector exactly once) followed by an `if`/else-if chain comparing the temp to each
  literal pattern (the wildcard / variable-binding arm becomes the trailing `else`); a value-position
  `match` adds a result `var` that each arm assigns, then the surrounding `let`/`var`/`return` reads the
  result temp. A variable-binding `case n =>` desugars by seeding `n` as an in-scope alias of the
  selector temp inside that arm. `normalizeMatchArms` validates every arm and bails to fallback on any
  out-of-grammar shape (a synthesized `$`-prefixed temp name -- illegal in source -- guarantees no
  collision with user identifiers). Verified at runtime (no folding): CUT 1 -> `many`; CUT 2 -> exit
  `200` and exit `20`; CUT 3 -> exit `8`.

These are the only source constructs the integrated pipeline lowers end to end
today; anything else still flows through the compatibility models described
below.

### Known gaps (still unsupported -- silently fall back to the summary path)

The real body-lowering path is additive and gated on `hasRealBody`. Any body using a
construct outside the supported grammar leaves `hasRealBody == false` and quietly flows
through the token-summary scanner / compile-time fold instead. As of the
`match`-on-`Int64` milestone, the following are still **not** supported on the real path
and silently fall back:

- **Arrays of non-`Int64` element types** (`Array<String>`, `Array<Bool>`, nested arrays,
  etc.) and array methods beyond `.size` / indexing / element write / `for-in`
  (`Array<Int64>` of those four shapes is now supported -- `opus13/arrays`).
- **`match` beyond an `Int64` selector with literal / wildcard / single-variable-binding
  patterns.** `match` on an `Int64` selector is now supported (`opus14/match`), but
  match-on-`enum` (constructor patterns), tuple / range / type patterns, a `case L1 | L2`
  literal alternation, a `where` pattern guard, the selector-less `match { case <expr> => }`
  form, and matching a non-`Int64` selector all still fall back to the summary path.
- **`struct` / `class`** declarations, fields, methods, and member access.
- **`Float64`** (and other non-`Int64` numeric widths) -- literals, arithmetic, and
  printing of a `Float`/other-width integer value.
- **Lambdas / closures** (`{ x => ... }`) and first-class function values.
- **`for-in` over a `String`** (and over collections / other non-range, non-`Array<Int64>`
  iterables).
- **`String.size`, `String` indexing / slicing, `String` comparison**, and other
  `String` methods (only literals, `+` concat, interpolation, and print are wired).
- **Compound assignment** (`+=`, `-=`, etc.), short-circuit `&&`/`||` (currently lowered
  as non-short-circuit `And`/`Or` on i1), and a `where` guard on `for-in`.

**Latent silent-fallback issue.** Because the gate is silent, a program that uses an
unsupported construct does not error or warn -- it falls back to the summary/fold path,
which may (a) compile a *different, narrower* behavior than the source intends, or
(b) succeed only because the summary scanner happened to recognize a literal-shaped
subset, while genuinely runtime semantics are dropped. The mixed-print milestone already
fixed one instance (a runtime print silently dropped when interleaved with literal prints);
the general risk remains until the summary parser is retired and every construct either
lowers on the real path or produces an explicit diagnostic. Until then, "compiles and runs"
on this path does not by itself prove the source was lowered faithfully -- each supported
slice must be confirmed by a real compile-and-run with a known expected output.

### Remaining de-isolation follow-ups

- **Real Cangjie `String` representation and other-width numeric print values.** The
  runtime print path now lowers an `Int64` value to `printf("%ld")`, a `Bool` value to
  `printf("%s")` over `"true"`/`"false"`, and a `String` value to `puts`/`fputs`
  (`opus11/string`). `String` on the real path is currently modelled as a raw CString
  (`i8*`): literals, locals/params/returns, `+` concat (libc
  `strlen`/`malloc`/`strcpy`/`strcat`), and print all work, but this is **not** the
  production Cangjie `String` struct/array representation the reference cjc emits, the
  concat `malloc` is never freed (leaks), and only the `+` operator / println-print /
  interpolation are wired (no `.size`, indexing, comparison, `String`-keyed collections, or
  other `String` methods). String interpolation (`"...${expr}..."` over `Int64`/`Bool`/
  `String`) is now lowered (`opus12/interp`), but its `Int64`/`Bool` -> String conversion
  (`malloc` + `snprintf` / `"true"`/`"false"` globals) is likewise not the production
  `String` machinery and also leaks the `malloc`. Replace the CString model with the real runtime `String`
  representation and route concat/print/compare through the runtime's `String`
  construct/concat/print symbols. Printing (or otherwise computing with) an other-width
  integer or `Float` value is also still not wired -- extend the PRINT lowering /
  `EmitRuntime*Print` (format selection) once those value types flow through the real body.
- **More operators and statement kinds on the real path.** Compound
  assignment (`+=` etc.), `struct`/`class`, `Float64`, and lambdas/closures are
  still unsupported (the body falls back to the summary path). `match` on an `Int64` selector
  (literal / wildcard / single-variable-binding patterns, statement and value forms) is now
  supported (`opus14/match`); match-on-`enum`, `|`-alternation, range/tuple/type patterns, and
  `where` guards remain follow-ups. String interpolation is now
  supported (`opus12/interp`); `Array<Int64>` literals/indexing/`.size`/writes/`for-in`/sized
  constructor are now supported (`opus13/arrays`); `for-in` over integer ranges plus
  `break`/`continue` are now supported (`opus9/loops`);
  arrays of non-`Int64` element types, `for-in` over other iterables (collections, `String`),
  and a `where` guard are follow-ups. Logical `&&`/`||` and unary `!` are supported (`opus8/bool`), though
  `&&`/`||` are currently lowered as non-short-circuit `And`/`Or` on i1 -- real
  short-circuit evaluation is a follow-up. Extend `RealParseBridge` ->
  `AST2CHIRStmtSpec`/`AST2CHIRExprSpec` -> `CreateRealBody`.
- **Retire the summary parser.** Once the real parser drives every supported
  construct, remove the frontend token-summary scanner
  (`packages/frontend/src/CompileStrategy.cj` `parseLiteralReturn` /
  `resolveLetLiteral` / `captureFunctionBodyPrints`) and the compile-time
  arithmetic fold, so all bodies flow through `RealParseBridge` ->
  `AST2CHIRStmtSpec` -> `CreateRealBody`.
- Extend the real-body adapter to more statement kinds and types beyond `Int64`,
  `Bool`, and `String` (other integer/`Float` widths, `for-in` over non-range
  iterables, `match`); deepen `String` beyond literal/concat/print to the real
  runtime `String` representation with methods, indexing, and comparison.
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
| Overall behavior-faithful self-host estimate | 51% |
| Remaining source `TODO(selfhost:*)` markers | 4 |
| Modules with remaining source markers | Sema |
| Cangjie `.cj` files under `packages/*/src` | 526 |
| Cangjie source lines | about 161.7K |
| C++ reference source-like files under `src` | 728 |
| C++ reference source lines | about 282.0K |
| C++ reference components with no same-named `.cj` component | 172 |
| Required build command | `cjpm build` |
| Build result | pass |
| Build notes | `cjpm build` succeeds (a few unused-variable/unused-import warnings on the real-body + match adapter sources) |

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
