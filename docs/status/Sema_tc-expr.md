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
- Current deepening pass:
  - Wildcard patterns are now handled by the shared expression-scope pattern checker instead of falling through as pretyped-only patterns.
  - Tuple-literal subscript checking now mirrors the C++ behavior of checking the selected child against the target type and rebuilding the tuple literal type from the updated children.
  - Subscript desugar checks now propagate a resolved call target back through the existing sema target-update API when the desugar expression is a resolved call.
  - `for-in` element inference now accepts direct `Iterable<T>` interface values in addition to arrays, ranges, strings, VArray, and generic fallbacks.
  - Try catch-pattern checking now rejects non-catch pattern shapes, validates wildcard and exception-type catch patterns structurally, joins listed exception types, and checks the nested catch pattern against that joined type.
  - Shift compound assignment now rejects literal negative shift counts and counts that overflow the left integer type width, matching the C++ post-check.
- Continuation pass:
  - Built-in equality now follows the C++ scalar candidate set more closely: numeric/rune, `Bool`, `Unit`, and `Nothing`; it no longer accepts arbitrary mutually compatible nominal types as built-in `==`/`!=`.
  - Tuple equality now recursively validates element comparability instead of accepting any equal-length tuple pair.
  - Coalescing expressions now require a core `Option<T>` left operand. Synthesis checks the right operand against `T`; check mode uses the contextual target when `T` is compatible with that target, matching the C++ `ChkCoalescingExpr` shape.
  - Binary expressions with an existing desugared call now propagate the resolved call target to the original binary node.
  - `for-in` element inference now inspects real declared supertypes via `TypeManager.GetAllSuperTys` to detect implemented `Iterable<T>`, not just direct `Iterable<T>` types.
- Follow-up pass:
  - Lambda synthesis no longer silently assigns `Any` to omitted parameter types. It now allocates solving placeholders for omitted parameters, filters the active constraint set to those placeholders, applies a complete solution when available, and rechecks the lambda body after substitution.
  - Lambda body rechecking now clears previously synthesized expression/decl state while preserving type and generic nodes, mirroring the C++ `ClearLambdaBodyForReCheck` shape.
  - Try catch-pattern checking now carries an included-type set across wildcard and exception-type catch patterns, rejecting duplicate or already-covered catch types instead of accepting every structurally valid pattern.
  - Try handler command-pattern checking now carries a separate included-command set and rejects non-`Command<T>`-shaped patterns or already-covered command types before checking the nested pattern.
- Resume pass:
  - `@IfAvailable(level:)` string literal validation now uses the real `sema.Plugin.APILevelVersion` parser with the C++ `TRIPLE_ONLY` rule, while preserving the C++ expression checker behavior that accepts integer literals as literals in this path.
- Current continuation:
  - `for-in` expression checking now reuses the real sibling `IsIrrefutablePattern` helper and rejects refutable iteration patterns after type-checking the iterable, guard, and body, matching the C++ `SynForInExpr` control flow.
- Command-pattern continuation:
  - Try-handle command patterns now derive `handler.commandResultTy` from a direct or promoted `stdx.effect.Command<T>` view found through real declaration metadata, generic upper bounds, and declared supertypes, instead of accepting any single-argument generic type as command-shaped.
- Verification: `cjpm build` passes after the command-pattern continuation. `grep -rn "TODO(selfhost:Sema)" packages/sema/src` reports only out-of-scope Sema placeholders; the scoped `TypeCheckExpr.cj` and `TypeCheckExpr/*` files have zero matching markers.

Remaining fidelity gaps:
- Full overload resolution/desugar paths for operator, subscript, and compound assignment still depend on broader call/lookup/desugar infrastructure.
- Lambda syntax-driven inference from member access/calls still needs the C++ `ASTContext` candidate maps and cache invalidation path to be threaded into this self-hosted expression layer.
- Tuple equality still validates built-in element comparability only; full C++ parity needs generated/desugared element comparison expressions and operator overload checks.
- Coalescing placeholder-`Option` constraints still need the import-manager/core-decl path used by C++ for unconstrained type variables.
- Name lookup, accessibility filtering, capture diagnostics, generic constraint solving, and full C++ diagnostic parity remain limited by sibling sema systems that are still partial.
- Try-with-resources currently checks resource declarations structurally but cannot validate the imported `Resource` interface without the full import manager path.
- Try-handle command pattern promotion now follows direct/generic-upper/supertype `Command<T>` shapes, but full parity still needs the import-manager target lookup and exact diagnostics used by C++ `ChkCommandTypePattern`.
- Catch pattern validation cannot yet prove subtype-of-core-`Exception`/`Error` without an import-manager/core-decl path in this helper; it conservatively validates catchable classlike/generic shapes.
- `@IfAvailable` still lacks the C++ import-manager checks for `ohos.device_info` and `ohos.base` package availability.
- `for-in` refutable-pattern rejection now has the C++ behavior but not the exact `sema_forin_pattern_must_be_irrefutable` diagnostic emission in this shallow helper.

Completeness estimate: 57% of C++ behavior for this scoped expression type-checking area, weighted by behavior rather than line count.
