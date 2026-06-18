# CHIR ast2chir-expr

## 2026-06-18 Deepening Pass

- Added C++-shaped short-circuit lowering for logical `&&` and `||` in the real-body AST2CHIR expression-spec path. The translator now evaluates the left operand, branches to either the right-operand block or a constant-result block, stores into a Bool slot, and loads the merged result, matching the control-flow shape of the C++ `TranslateBinaryExpr.cpp` path instead of eagerly lowering both operands into a plain binary operation.
- Added a CHIR-side `DoWhile` statement spec and lowering component in `TranslateDoWhileExpr.cj`, mirroring the C++ body-first CFG: entry -> body -> condition -> body/exit, with `continue` targeting the condition block and `break` targeting the exit block.
- Added lexical scope snapshots for real-body lowering. `if`, `while`, range `for`, and array `for-in` bodies now restore local/value/array bindings after nested body emission, so local declarations and loop variables no longer leak into the enclosing adapter scope while stores to captured outer slots still affect the same CHIR storage.
- Split new logic into C++-named translator components: `TranslateBinaryExpr.cj` and `TranslateDoWhileExpr.cj`, while preserving the existing `TranslateFuncBody.cj` entry path used by declaration lowering.
- Verification: baseline `cjpm build` passed before editing; final `cjpm build` passed after the changes. Remaining build output is an out-of-scope frontend unused-import warning in `packages/frontend/src/RealParseBridge.cj`.
- Remaining scoped `TODO(selfhost:CHIR)` markers under `packages/chir/src`: 0.

## Remaining Gaps

- The current CHIR AST2CHIR expression path is still adapter-spec based, not the full typed AST visitor from the C++ `Translator`. It does not yet own real typed-AST pattern lowering, full match/try/throw lowering, pattern guards, exception/finally control-flow duplication, or the C++ switch-table optimization for match/let-pattern conditions.
- `DoWhile` is now supported by the CHIR-side spec/lowering API, but the frontend parse bridge that builds those specs lives outside this pass scope and has not been changed here.
- Logical short-circuit now matches the C++ CFG semantics for the supported Bool spec path, but overflow-aware integer operations, C++ exception-capable operators, debug locations, and diagnostics remain partial in the real-body adapter path.

Honest behavior coverage for this scoped AST2CHIR expression/statement/control-flow slice is about 28% versus the C++ reference. This pass deepens active lowering semantics for logical control flow and lexical scoping and adds a do-while component, but the full C++ typed-AST translator remains substantially broader.

## 2026-06-18 Continuation

- Added `TranslateAssignExpr.cj` to mirror another C++ `TranslateASTNode` component and ported the simple local compound-assignment lowering shape: load the left slot once, compute the compound value, and store it back to the same slot.
- Added CHIR-side `AST2CHIRStmtSpec.CompoundAssign(name, op, expr)` and the corresponding statement kind. Arithmetic/bitwise compound assignments lower through a real `BinaryExpression`; `&&=` and `||=` use body CFG blocks so the right-hand expression is evaluated only when required, matching the C++ translator's `TransShortCircuitAnd` / `TransShortCircuitOr` path.
- Verification: `cjpm build` passed after the continuation. `grep -rn "TODO(selfhost:CHIR)" packages/chir/src` reports no markers.

## Remaining Gaps After Continuation

- The frontend parse bridge still rejects compound assignment before it reaches CHIR; wiring that bridge is outside this pass's `packages/chir/src` edit scope.
- The new compound assignment path handles simple local slots in the current adapter model. C++ also supports wildcard assignment, member-path left values, tuple destructuring, VArray intrinsic set, overflow exception terminators, and debug-location/diagnostic propagation through the typed-AST translator.

Updated honest behavior coverage for this scoped AST2CHIR expression/statement/control-flow slice is about 30% versus the C++ reference. The port now has real C++-shaped lowering for short-circuit binary expressions, do-while control flow, lexical body scoping, and simple local compound assignment, but remains far from the full typed-AST Translator.
