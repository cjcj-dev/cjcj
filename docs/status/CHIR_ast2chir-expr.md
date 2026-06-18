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
