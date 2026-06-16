# Sema tc-expr status

Date: 2026-06-17

Scope: `packages/sema/src/TypeCheckExpr.cj` and expression checker components for assign, binary, if, if-available, lambda, loops, name references, subscript, and try expressions.

Build: `cjpm build` passes.

What changed:
- Removed all `TODO(selfhost:Sema)` markers in the requested expression type-checking scope.
- Added real expression synthesis/check helpers over the existing self-hosted AST and sema packages, without local compatibility copies of Basic/Lex/AST/diagnostic types.
- Implemented built-in binary operators, assignment result typing, boolean conditions, branch joining, loop `Unit` typing, lambda function types with target-driven parameter typing, try/catch/finally joining, `@IfAvailable` lambda/desugared-if checks, tuple/VArray subscript access, and name-reference target/type propagation.
- Added root `TypeCheckExpr.cj` helpers for option boxing and type-alias mapping behavior that can be represented with the current self-hosted APIs.
- Continued fidelity pass:
  - Multiple assignment now validates tuple shape and element compatibility recursively against the synthesized right-hand tuple type, including wildcard and assignable single-element targets.
  - Checked lambda expressions now preserve the target `FuncTy` ABI/config flags (`isC`, closure, vararg, and no-cast) on both the lambda body and lambda expression type.
  - Try-handle checking now validates illegal `return` placement in try/catch/handle blocks with real AST walking, binds `resume` expressions to the enclosing handler, derives handler command/result types from command patterns, and checks desugared handler lambdas against the command parameter type instead of `Any`.
- Verification: `cjpm build` passes after the continuation pass. `grep -rn "TODO(selfhost:Sema)" packages/sema/src` reports only out-of-scope Sema placeholders; the scoped `TypeCheckExpr.cj` and `TypeCheckExpr/*` files have zero matching markers.

Remaining fidelity gaps:
- Full overload resolution/desugar paths for operator, subscript, and compound assignment still depend on broader call/lookup/desugar infrastructure.
- Name lookup, accessibility filtering, capture diagnostics, generic constraint solving, and full C++ diagnostic parity remain limited by sibling sema systems that are still partial.
- Try-with-resources currently checks resource declarations structurally but cannot validate the imported `Resource` interface without the full import manager path.
- Try-handle command pattern promotion is still approximated from the available self-hosted type arguments; full parity needs the broader promotion/import-manager path used by C++ `ChkCommandTypePattern`.

Completeness estimate: 48% of C++ behavior for this scoped expression type-checking area, weighted by behavior rather than line count.
