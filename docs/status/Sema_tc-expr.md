# Sema tc-expr status

Date: 2026-06-17

Scope: `packages/sema/src/TypeCheckExpr.cj` and expression checker components for assign, binary, if, if-available, lambda, loops, name references, subscript, and try expressions.

Build: `cjpm build` passes.

What changed:
- Removed all `TODO(selfhost:Sema)` markers in the requested expression type-checking scope.
- Added real expression synthesis/check helpers over the existing self-hosted AST and sema packages, without local compatibility copies of Basic/Lex/AST/diagnostic types.
- Implemented built-in binary operators, assignment result typing, boolean conditions, branch joining, loop `Unit` typing, lambda function types with target-driven parameter typing, try/catch/finally joining, `@IfAvailable` lambda/desugared-if checks, tuple/VArray subscript access, and name-reference target/type propagation.
- Added root `TypeCheckExpr.cj` helpers for option boxing and type-alias mapping behavior that can be represented with the current self-hosted APIs.

Remaining fidelity gaps:
- Full overload resolution/desugar paths for operator, subscript, and compound assignment still depend on broader call/lookup/desugar infrastructure.
- Name lookup, accessibility filtering, capture diagnostics, generic constraint solving, and full C++ diagnostic parity remain limited by sibling sema systems that are still partial.
- Try-with-resources currently checks resource declarations structurally but cannot validate the imported `Resource` interface without the full import manager path.

Completeness estimate: 45% of C++ behavior for this scoped expression type-checking area, weighted by behavior rather than line count.
