# Deisolation Plan: lowering a real function body end-to-end

Status: read-only analysis (no `.cj` changed by this document). Build verified green
(`cjpm build` -> `cjpm build success`) and the existing literal-fold slice still runs
(`main(): Int64 { let a = 5; return a }` -> exit code 5 via the self-host `cjc`).

Target program to lower **without** compile-time folding:

```cangjie
main(): Int64 {
    let a = 2
    let b = 3
    return a + b
}
```

Expected behavior: process exits with code 5, where `5` is produced by a real CHIR
`Add` instruction at runtime (not constant-folded in the frontend).

---

## 0. Executive summary — where the facade is

The current pipeline is a literal-spec **bridge**, and the isolation is concentrated in
exactly one place: **`packages/frontend`**. The frontend does **not** use
`packages/parse` (the real parser) nor `packages/ast` (the real AST). Instead:

- `packages/frontend/src/CompileStrategy.cj` contains a hand-rolled, token-stream
  ad-hoc parser (`ParseSourceFile` -> `parseTopLevelDecls` -> `createDeclFromKeyword`
  -> `finishParsedDecl` -> `finishDeclExtent`). It scans `FrontendToken`s and, for a
  function body, only **summarizes** it: `parseLiteralReturn` / `resolveLetLiteral`
  (folds `let x = <lit>; return x`) and `captureFunctionBodyPrints`
  (`println/print("literal")`). It records those summaries on
  `frontend.FuncBody.hasLiteralReturn / literalReturnKind / literalReturnValue /
  printStrings / printNewlines`. **The statement list of the body is discarded.**
- `packages/frontend/src/FrontendModel.cj` defines the frontend's own minimal AST
  (`Decl`, `FuncDecl`, `FuncBody`, `VarDecl`, `Type`, `File`, ...). Critically:
  - `frontend.FuncBody` (FrontendModel.cj:429) has **no `body` / statement list** and
    **no `Block`** — only the literal/print summary fields.
  - `frontend.VarDecl` (FrontendModel.cj:517) has **no `initializer`** — a local
    `let a = 2` is never represented as a node with an init expression.
  - There is **no expression node hierarchy** in FrontendModel at all (no `BinaryExpr`,
    `RefExpr`, `ReturnExpr`, `LitConstExpr`).
- `packages/frontend/src/CodeGenBridge.cj` turns that summary into a CHIR *spec*
  (`AST2CHIRFunctionSpec`) via `buildFunctionSpec`, calling `setLiteralReturn(...)` and
  `AddPrintString(...)`. It never builds real statements.

Downstream of the bridge everything is **real and already capable**:

- `packages/chir` builds an actual CHIR `Function` with a `BlockGroup`/`Block` and
  real `Expression`s (`CHIRBuilder` has `CreateConstant`, `CreateAllocate`,
  `CreateStore`, `CreateLoad`, `CreateBinaryExpression`, `CreateExit`).
- `packages/codegen` walks those blocks generically and emits LLVM IR for
  `Constant`, `Allocate`, `Load`, `Store`, `BinaryExpression` (incl. `Add`), and
  `Exit` (return). **Codegen needs no changes for this slice.**

So "escaping the facade" = replacing the frontend's token-summary parser + summary
model + summary bridge with: (a) a real AST for the body, and (b) a real
`ast.FuncBody -> CHIR` lowering that emits VarDecl/BinaryExpr/ReturnExpr. The cleanest
path reuses the already-written real parser in `packages/parse`.

---

## 1. `packages/parse` — does `Parser.ParseTopLevel` parse real bodies?

**Yes, fully.** `packages/parse` is a complete recursive-descent parser that is
currently **unused by the compile pipeline**.

- `parse/src/Parser.cj:21` `ParseTopLevel(): File` -> `ParserImpl.ParseTopLevel`
  (`parse/src/ParseDecl.cj:6`), which parses package/imports/top-level decls.
- Function decls flow through `ParseDecl` -> `ParseFuncBody`
  (`parse/src/ParseDecl.cj:477`), which parses a real `Block` via `ParseBlock`
  (`parse/src/ParseExpr.cj:291`). `ParseBlock` loops `ParseExprOrDecl`, building a
  real statement list (`block.body: ArrayList<Node>`).
- `let a = 2` parses to `parse.VarDecl` with a real `initializer: Option<Expr>`
  (`parse/src/DeclNodes.cj:174-195`, via `ParseVarOrLet` at `ParseDecl.cj:548`).
- `a + b` parses through `ParseExpr` -> `ParseExprRhs` to a `parse.BinaryExpr`
  (`parse/src/ExprNodes.cj:321`) with `leftExpr`/`rightExpr`/`op: Token`.
- `return a + b` parses to `parse.ReturnExpr` (`parse/src/ExprNodes.cj:578`,
  `ParseReturnExpr` at `ParseExpr.cj:692`) with `expr: Option<Expr>`.
- `a` parses to `parse.RefExpr` (`ExprNodes.cj:81`); `2` to `parse.LitConstExpr`
  (`ExprNodes.cj:55`, `kind = LitConstKind.INTEGER`, `stringValue = "2"`).

So `packages/parse` already produces exactly the nodes this slice needs.

### 1a. Concrete incompatibilities between `parse.*` nodes and `ast.*` nodes

These are **two separate, independent class hierarchies** in two packages, sharing only
the `ASTKind` enum and `Attribute` (re-exported by parse from ast — see
`parse/src/ASTCore.cj:5`). They are **not** subtype-compatible:

| Concept | `packages/parse` | `packages/ast` | Incompatibility |
|---|---|---|---|
| Base node | `parse.Node` (`ASTCore.cj:10`): fields `begin/end/curMacroCall/curFile/astKind/isBroken`; `Children()` returns `ArrayList<parse.Node>` | `ast.Node` (`ast/src/Node.cj`): much richer (symbol table, scope, types, attribute pack) | Distinct classes, same name in different packages. A `parse.Node` is **not** an `ast.Node`. `Children()` element types differ. |
| File | `parse.File` | `ast.File` | Distinct types; `Package.AddFile` etc. on each side expect their own. |
| FuncDecl/FuncBody | `parse.FuncDecl` -> `funcBody: Option<FuncBody>`, `parse.FuncBody.body: Option<Block>` | `ast.FuncDecl` / `ast.FuncBody` (different fields, type wiring) | Different shapes; parse's `FuncBody` carries no semantic/type info, ast's does. |
| Expr base | `parse.Expr <: parse.Node` | `ast.Expr <: ast.Node` | Distinct hierarchies; `parse.BinaryExpr` is not an `ast.BinaryExpr`. |
| Block | `parse.Block <: parse.Expr`, `body: ArrayList<parse.Node>` | `ast.Block` | Element type of `body` differs (`parse.Node` vs `ast.Node`). |
| Identifiers | both use `SrcIdentifier` but **each package declares its own** | own | Same name, different declaring package -> different type. |
| Modifiers/Annotations | `parse.Modifier`/`parse.Annotation` | `ast.*` equivalents | Distinct. |

There is also a **third** AST: `frontend.*` (FrontendModel.cj), used by the live
pipeline, which is even more minimal than either (no body, no expr nodes — see §0).

### 1b. Recommendation: **adapter**, not unify (for this first slice)

Recommended: build a small **adapter** that runs the real `parse` parser and translates
the resulting `parse.*` tree into the CHIR spec/body the bridge needs — rather than a
full "unify the AST hierarchies" effort.

Rationale:

1. **Scope/risk.** Unifying `parse.*` and `ast.*` (and retiring `frontend.*`) is a
   large, cross-package refactor touching sema, mangle, codegen-bridge, and the
   incremental machinery. The first real-expression slice does not need sema at all
   (no name resolution beyond the local `let` bindings, no overload resolution; types
   are explicit/inferable locally).
2. **The real parser already exists and is decoupled.** We can call
   `parse.Parser(...).ParseTopLevel()` directly and consume `parse.*` nodes without
   disturbing `ast.*` or `frontend.*`.
3. **Minimal blast radius.** The adapter is additive: a new translation step that maps
   `parse.FuncBody.body` statements onto `AST2CHIRFunctionSpec` body-building calls
   (see §2), leaving every existing literal/print path untouched, so the
   ALREADY-VERIFIED slices cannot regress.
4. **Migration story.** The adapter is the seam where, slice by slice, the
   token-summary frontend is replaced by the real parser. Once the real parser drives
   everything and `frontend.*`/`ast.*` converge in practice, a later unify step (fold
   `frontend.*` into `ast.*`, or make the bridge consume `ast.*` directly) becomes a
   mechanical cleanup rather than a risky big-bang.

The longer-term unify target (out of scope for the first slice) is: make sema and the
bridge consume `ast.*` produced from `parse.*` (or have `parse` emit `ast.*` directly),
and delete `frontend.*`'s parser+model. That should be a follow-up plan once 2–3
real-expression slices have proven the adapter path.

---

## 2. `packages/chir` — is there a real `ast.FuncBody -> CHIR` path beyond the spec path?

**No.** There is only the **spec path**. CHIR is fed exclusively by
`AST2CHIRPackageSpec` / `AST2CHIRFunctionSpec` (`chir/src/AST2CHIR.cj`), built by the
frontend bridge. There is **no** consumer of `ast.FuncBody` or `parse.FuncBody` inside
`packages/chir`. The lowering entry is `AST2CHIR.LowerPackage` ->
`AST2CHIRDeclTranslator.LowerPackage` (`chir/src/AST2CHIRDeclTranslator.cj:261`) ->
`LowerFunction` (`chir/src/TranslateFuncDecl.cj:6`).

What `LowerFunction` currently does for a body (`TranslateFuncDecl.cj:25-31`):
- if `spec.hasLiteralReturn` -> `CreateLiteralReturnBody(fn, BuildLiteralReturn(spec))`
  (`AST2CHIRDeclTranslator.cj:151`): single entry block, allocate return slot, one
  `Constant`, one `Exit(result)`.
- else -> `CreateEmptyBody(fn)` (`AST2CHIRDeclTranslator.cj:143`): entry block +
  `Exit(None)`.

Neither emits locals or arithmetic. So the "spec" intentionally has no statement list.

### What is **missing** to lower `VarDecl` + `BinaryExpr` + `ReturnExpr`

The CHIR **builder primitives all already exist** (`chir/src/CHIRBuilder.cj`):
`CreateConstant` (:121), `CreateAllocate` (:129), `CreateStore` (:145),
`CreateLoad` (:137), `CreateBinaryExpression` (:112), `CreateExit` (:465);
`ExprKind.ADD` exists (`chir/src/Enums.cj:350`). What is missing is **the code that
calls them in the right order from a real body**. Concretely, we need either:

- (preferred) a new body representation on the spec — e.g. an ordered list of
  "statements" (local-let with init expr, return with expr) carried on
  `AST2CHIRFunctionSpec` — plus a new `CreateRealBody(fn, statements)` translator that
  walks it; **or**
- a new translator that consumes `parse.FuncBody.body` directly (couples chir to parse).

For the target slice the translator must produce, in the entry block:

1. return slot: `EnsureReturnSlot(fn, entry)` (already exists,
   `AST2CHIRDeclTranslator.cj:170`) — allocates a `Ref<Int64>` and sets it as the
   function return value.
2. for `let a = 2`: `CreateAllocate(Ref<Int64>, Int64)` -> `aSlot`;
   `CreateConstant(Int64, IntLiteral(2))` -> `c2`; `CreateStore(c2, aSlot)`.
3. for `let b = 3`: same with `IntLiteral(3)` -> `bSlot`.
4. for `a + b`: `CreateLoad(Int64, aSlot)` -> `va`; `CreateLoad(Int64, bSlot)` -> `vb`;
   `CreateBinaryExpression(ExprKind.ADD, Int64, va, vb)` -> `sum`.
5. for `return <sum>`: store `sum` into the return slot then `CreateExit(Some(retVal))`
   (mirror how `CreateLiteralReturnBody` finishes, but with `sum` instead of a constant).

A **name->slot map** (local symbol table) is needed inside the translator so the
`RefExpr` `a`/`b` resolve to the `Allocate` results from step 2/3. This is the only new
"semantic" bookkeeping and it is local to one function body (no cross-decl resolution).

Recommended chir-side additions (file-level):
- `chir/src/AST2CHIR.cj`: add a minimal statement model to `AST2CHIRFunctionSpec`
  (e.g. `bodyStatements: ArrayList<AST2CHIRStmtSpec>` describing local-let-with-literal
  / local-let-with-binary / return-of-expr), so chir stays decoupled from parse/ast.
- new `chir/src/TranslateFuncBody.cj`: `CreateRealBody(fn, spec)` implementing steps
  1–5 above using existing `CHIRBuilder` calls, plus a `HashMap<String, Value>` for
  locals. Gate it from `LowerFunction` (`TranslateFuncDecl.cj`) with a new
  `spec.hasRealBody` flag, **above** the existing `hasLiteralReturn` branch so existing
  behavior is unchanged when `hasRealBody == false`.

(The statement model keeps chir from depending on `parse`/`frontend`; the adapter in the
frontend (§3) is what flattens `parse` expr trees into that model.)

---

## 3. `packages/codegen` — does it already lower CHIR arithmetic / local-var / return?

**Yes, all three, with no changes required.** The function emitter walks CHIR blocks
generically:

- `EmitFunctionIR` (`codegen/src/EmitFunctionIR.cj:15`) gets the body and calls
  `EmitBasicBlockIR(cgMod, entryBlock)`.
- `EmitBasicBlockIR` (`codegen/src/EmitBasicBlockIR.cj:75`) walks blocks (DFS over
  successors) and for each calls `EmitExpressionIR` over `block.GetExpressions()`.
- `EmitExpressionIR` (`codegen/src/EmitExpressionIR.cj:39`) calls `DispatchExpression`
  per CHIR expr and maps results.
- `DispatchExpression` (`codegen/src/ExprDispatcher.cj:9`) routes:
  - `Constant` -> `HandleConstantExpression` (`ConstantExprDispatcher.cj`).
  - `Allocate` / `Load` / `Store` -> `HandleMemoryExpression`
    (`codegen/src/MemoryExprDispatcher.cj:6`) -> `GenerateAllocate` / `GenerateLoad`
    / `GenerateStore` (in `codegen/src/AllocateImpl.cj` and `IRBuilder.cj`).
  - `BinaryExpression` (`Add`) -> `HandleBinaryExpression`
    (`codegen/src/BinaryExprDispatcher.cj`) -> `GenerateArithmeticOperation`
    (`codegen/src/ArithmeticOpImpl.cj:5`), which materializes both operands and calls
    `irBuilder.CreateBinaryTyped(ExprKind.ADD, ...)`.
  - `Exit` (return) -> `HandleTerminatorExpression`
    (`codegen/src/TerminatorExprDispatcher.cj:29-35`): 0 operands -> `CreateRetVoid`;
    1 operand -> `CreateRet(value)`.

The print directives are a separate side-channel (`EmitFunctionPrintDirectives`,
`codegen/src/EmitPrintIR.cj`) inserted at the entry block head — independent of the
above, so it does not interfere with a real body.

Conclusion: once a CHIR function carries a real entry block with
allocate/const/store/load/add/exit, **codegen already lowers it correctly**. The arithmetic
slice is purely a frontend+chir-bridge task.

---

## 4. Ordered, minimal step list for the first real-expression slice

Each step lists the file(s) touched. Steps are ordered so the build stays green and the
ALREADY-VERIFIED slices (println/print, literal int return, `let x=<lit>; return x`)
never regress (the new path is gated and additive).

1. **CHIR statement model (additive).**
   `packages/chir/src/AST2CHIR.cj`: add a tiny body description to
   `AST2CHIRFunctionSpec`: `var hasRealBody: Bool = false` plus an ordered
   `ArrayList<AST2CHIRStmtSpec>` where `AST2CHIRStmtSpec` encodes the three statement
   kinds needed: `LocalLetLiteral(name, IntLiteral)`,
   `LocalLetBinary(name, op, lhsName, rhsName)` (operands are local names or literals),
   and `ReturnExpr(operandName-or-literal)`. Keep it deliberately small (Int64 only).
   No behavior change yet (default `hasRealBody == false`).

2. **CHIR real-body translator (additive).**
   New `packages/chir/src/TranslateFuncBody.cj`: `CreateRealBody(fn, spec)` implementing
   §2 steps 1–5 using existing `CHIRBuilder` calls and a `HashMap<String, Value>` for
   the local slots/loaded values. Reuse `EnsureReturnSlot`.
   `packages/chir/src/TranslateFuncDecl.cj`: in `LowerFunction`, add
   `if (spec.hasRealBody) { CreateRealBody(fn, spec) } else if (spec.hasLiteralReturn)
   {...} else {...}` — new branch first, existing branches unchanged.

3. **Wire the real parser into the frontend (additive, behind a flag).**
   `packages/frontend/src/CompileStrategy.cj` (or a new
   `packages/frontend/src/RealParseBridge.cj`): add a code path that, for each source
   file, runs `parse.Parser(fileID, source, diag, sm).ParseTopLevel()` to obtain a
   `parse.File`. Initially keep the existing token-summary parser as the default and
   only use the real parser when the body is **not** foldable (i.e. when
   `parseLiteralReturn` returned false) — this guarantees the verified literal/print
   slices keep their exact current lowering.

4. **Adapter: `parse.FuncBody` -> CHIR statement model.**
   In the same new bridge file: translate the `parse` body. Walk
   `funcBody.body.getOrThrow().body` (the `ArrayList<parse.Node>`):
   - `parse.VarDecl` with `LitConstExpr` initializer -> `LocalLetLiteral`.
   - `parse.VarDecl` with `BinaryExpr` initializer (operands `RefExpr`/`LitConstExpr`)
     -> `LocalLetBinary`.
   - `parse.ReturnExpr` whose `expr` is `RefExpr` / `LitConstExpr` / `BinaryExpr`
     -> `ReturnExpr` (lowering a binary return as an implicit temp + return).
   Anything outside this grammar -> fall back to the existing summary path (so no
   regression, and unsupported programs behave as today). Set `spec.hasRealBody = true`
   and attach the statement list on the `AST2CHIRFunctionSpec` built in
   `packages/frontend/src/CodeGenBridge.cj` (`buildFunctionSpec`).

5. **Return-type handling.**
   `packages/frontend/src/CodeGenBridge.cj`: when `hasRealBody`, the function return
   type comes from the parsed `retType` (`Int64` here) via the existing
   `lowerValueType`; bypass `lowerFunctionReturnType`'s literal-return special casing.
   Ensure `main(): Int64` keeps `FuncKind.MAIN_ENTRY` (existing `toChirFuncKind`).

6. **Build + verify.**
   `cjpm build` to green. Then with the runtime env set, compile and run the target
   program with the self-host `cjc`:
   ```
   main(): Int64 { let a = 2; let b = 3; return a + b }
   ```
   Confirm exit code `5`. Confirm via CHIR dump / LLVM (`-S` / `--dump-chir` if wired)
   that the body contains a real `Add` (no constant folding) — i.e. the `5` is computed
   at runtime. Re-run the three ALREADY-VERIFIED slices to confirm no regression.

7. **(Follow-up, not in this slice) Unify.**
   Once 2–3 real-expression slices work through the adapter, plan the convergence:
   either make `parse` emit `ast.*` (or make the bridge consume `ast.*`/`parse.*`
   directly and retire `frontend.*`'s token parser + summary model). Tracked separately.

### Smallest possible first cut

If an even smaller first increment is wanted before `a + b`: do steps 1–6 for
`main(): Int64 { let a = 2; return a }` but **without folding** — i.e. force the real
body path (Allocate/Store/Load/Exit, no `Add`). That isolates "real local variable +
real load + real return" from arithmetic, and the only delta to reach the full target is
adding the `BinaryExpr` -> `CreateBinaryExpression(ADD, ...)` case in step 2/4.

---

## Appendix: key file references

- Frontend ad-hoc parser & summaries: `packages/frontend/src/CompileStrategy.cj`
  (`ParseSourceFile`:414, `parseLiteralReturn`:1041, `resolveLetLiteral`:1119,
  `captureFunctionBodyPrints`:1003).
- Frontend minimal AST: `packages/frontend/src/FrontendModel.cj`
  (`FuncBody`:429 — no body/Block; `VarDecl`:517 — no initializer; `Type`:373).
- Frontend -> CHIR spec bridge: `packages/frontend/src/CodeGenBridge.cj`
  (`buildFunctionSpec`:168, `setLiteralReturn`:403, `lowerFunctionReturnType`:349).
- Real parser (unused by pipeline): `packages/parse/src/Parser.cj:21`
  (`ParseTopLevel`), `ParseDecl.cj:477` (`ParseFuncBody`), `ParseExpr.cj:291`
  (`ParseBlock`), `:692` (`ParseReturnExpr`); nodes in `parse/src/ExprNodes.cj`
  (`BinaryExpr`:321, `ReturnExpr`:578, `RefExpr`:81, `LitConstExpr`:55, `Block`:373)
  and `parse/src/DeclNodes.cj` (`FuncBody`:126, `VarDecl`:193).
- CHIR spec + translators: `packages/chir/src/AST2CHIR.cj`
  (`AST2CHIRFunctionSpec`:62), `AST2CHIRDeclTranslator.cj`
  (`CreateLiteralReturnBody`:151, `CreateEmptyBody`:143, `EnsureReturnSlot`:170),
  `TranslateFuncDecl.cj` (`LowerFunction`:6, body branch :25), `CHIRBuilder.cj`
  (create primitives :112–:465), `Enums.cj:350` (`ExprKind.ADD`).
- CHIR -> LLVM (already complete): `packages/codegen/src/EmitFunctionIR.cj:15`,
  `EmitBasicBlockIR.cj:75`, `EmitExpressionIR.cj:39`, `ExprDispatcher.cj:9`,
  `MemoryExprDispatcher.cj:6`, `ArithmeticOpImpl.cj:5`,
  `TerminatorExprDispatcher.cj:29` (Exit/return), `EmitPrintIR.cj` (print side-channel).
