# Sema tc-expr status

Date: 2026-06-18

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
- Subscript-overload continuation:
  - Shallow expression dispatch now handles `CallExpr` by synthesizing the call base and arguments before forwarding to the real sibling `SynCallExpr`/`ChkCallExpr` implementation.
  - Non-tuple/non-VArray subscript expressions now follow the C++ fallback path: desugar through the real `DesugarOperatorOverloadExpr`, type-check the desugared call, propagate the resolved call target back to the original subscript on success, and recover the original subscript shape on failure.
- Operator-overload continuation:
  - Member-access synthesis now seeds missing member targets from the real sibling `FieldLookup` and `ExtendFieldLookup` helpers after the base type is known, including operator member accesses created by desugaring.
  - Binary arithmetic, relational, and shift expressions now try the C++-shaped fallback path for overloadable operators: built-in check first, desugar through `DesugarOperatorOverloadExpr`, type-check the desugared call, propagate the resolved target, and recover the original binary expression on failure. Direct overload is skipped for both-tuple `==`/`!=`, matching the C++ tuple-special-case path.
  - Assignment expressions now probe the real desugared subscript setter path and compound-assignment overload path before falling back to built-in assignment checking, and propagate resolved setter/operator targets to the original assignment node on success.
- Flow-operator continuation:
  - Pipeline and composition expressions now route through the real sibling in-type-check desugar path before falling back to the prior function-type checks.
  - Flow checking now mirrors the C++ hard-failure cases for function-position `this`/`super`, rejects flow operands that resolve to functions with named parameters, propagates the resolved desugared call target, and recovers the original binary expression if the desugared call cannot be checked.
- Try-expression continuation:
  - Try-handle desugared lambda checking now uses the nested command pattern type as the lambda parameter type, while preserving `handler.commandResultTy` as the promoted `Command<T>` payload for `resume`, matching the C++ `ChkHandler` split.
  - Try-with-resources resource specifications now check explicit type/initializer compatibility and require the resulting resource type to be or implement `std.core.Resource` through real declaration metadata, generic upper bounds, and declared supertypes.
- Condition-checking continuation:
  - `let` pattern conditions now replace ideal initializer types before checking patterns, propagate the destructed expression context into nested variable patterns, reject mixed OR-pattern shapes, and reject explicit variable bindings introduced by OR-pattern alternatives.
  - Recursive `&&`/`||` condition checking now rejects explicit variable bindings under `||` while still type-checking both sides, matching the C++ control-flow rule for condition-local bindings.
- Binary/if continuation:
  - Built-in arithmetic and relational synthesis now follows the C++ `SynLiteralInBinaryExpr` shape more closely: synthesize from the right operand, check the left against that exact primitive candidate, clear and retry from the left when needed, and use the C++ candidate sets instead of rank-based numeric widening.
  - `if` branch joining now replaces ideal types and normalizes `This` types on both branches before computing the joined type, matching the C++ pre-join normalization step.
- Tuple-equality continuation:
  - Tuple `==`/`!=` now builds the C++-shaped desugared boolean chain (`true && ...` or `false || ...`) using real AST clone/create APIs, tuple-access nodes for non-literal tuple operands, shared `mapExpr` for side-effecting operands, and recursive synthesis of each generated element comparison.
- Binary check-mode continuation:
  - Checked binary expressions now try C++-shaped built-in target checking before synthesis fallback. Arithmetic operators unbox contextual `Option<T>` targets, filter concrete primitive candidates by subtype compatibility with the target, and check both operands against each candidate so contextual literal typing is preserved.
  - Exponentiation check mode now follows the C++ `Int64 ** UInt64` and `Float64 ** (Int64 | Float64)` target split, including rejection of ambiguous `Float64` exponent candidates.
  - Logical and relational check mode now requires a `Bool`-compatible target before checking operands, while shift check mode checks the left operand against the target and synthesizes/replaces the right operand before validating the integer candidate set.
  - Failed non-tuple built-in check attempts clear expression state before falling back to overload/synthesis, preserving the C++ reset shape without re-enabling direct overloads for both-tuple `==`/`!=`.
- Branch-join continuation:
  - `if` branch synthesis now uses the real sibling `Join` helper instead of the older compatibility/common-super-only approximation, preserving union results for disjoint branch types like the C++ `JoinAndMeet` path.
  - Try expression result joining and catch exception type-pattern joining now use the same shared `Join` helper, so try/catch/handle synthesis can carry union branch types instead of collapsing to invalid when there is no single common supertype.
- For-in iterable continuation:
  - `for-in` element inference now recursively promotes generic upper bounds to `Iterable<T>` before reading the element type, covering bounded generic iterables whose bound implements `Iterable<T>`.
  - Removed the previous unconstrained `Any`/generic fallback for `for-in` operands. Values must now be a recognized iterable shape or promote to a declared `Iterable<T>` view, matching the C++ `GetIterableTy` failure behavior more closely.
- Verification: `cjpm build` passes after the for-in iterable continuation. `grep -rn "TODO(selfhost:Sema)" packages/sema/src` reports only out-of-scope Sema placeholders; the scoped `TypeCheckExpr.cj` and `TypeCheckExpr/*` files have zero matching markers.

Remaining fidelity gaps:
- Full overload/desugar diagnostic parity still depends on broader call/lookup/desugar infrastructure: binary, flow, subscript, and compound assignment now use the real fallback shapes, but not the C++ diagnostic suppression, negative-cache constraint rollback, return-type-inference diagnostics, or exact recovery diagnostics.
- Binary target-driven built-in checking now mirrors the core C++ control flow, but exact diagnostic replay and constraint-transaction behavior remain approximate until the self-hosted checker has the C++ negative-cache/commit-scope machinery.
- Branch joining now preserves union results through the shared self-hosted `Join` helper, but exact C++ `JoinAndMeet::SetJoinedType` diagnostics and visible-type notes are still not emitted in this shallow layer.
- Lambda syntax-driven inference from member access/calls still needs the C++ `ASTContext` candidate maps and cache invalidation path to be threaded into this self-hosted expression layer.
- Tuple equality now generates the element comparison tree and checks each element comparison, but exact tuple comparison diagnostics still need the C++ diagnostic text and note plumbing.
- Coalescing placeholder-`Option` constraints still need the import-manager/core-decl path used by C++ for unconstrained type variables.
- Name lookup, accessibility filtering, capture diagnostics, generic constraint solving, and full C++ diagnostic parity remain limited by sibling sema systems that are still partial.
- Condition binding checks now reject explicit `VarPattern` bindings in OR contexts, but exact C++ parity still needs ASTContext enum-constructor classification for ambiguous `VarOrEnumPattern` nodes and the precise refactor diagnostics.
- Try-with-resources now validates visible `std.core.Resource` supertypes and generic upper bounds, but full parity still needs the import-manager target lookup and exact resource diagnostic used by C++.
- Try-handle command pattern promotion now follows direct/generic-upper/supertype `Command<T>` shapes, but full parity still needs the import-manager target lookup and exact diagnostics used by C++ `ChkCommandTypePattern`.
- Catch pattern validation cannot yet prove subtype-of-core-`Exception`/`Error` without an import-manager/core-decl path in this helper; it conservatively validates catchable classlike/generic shapes.
- `@IfAvailable` still lacks the C++ import-manager checks for `ohos.device_info` and `ohos.base` package availability.
- `for-in` refutable-pattern rejection and iterable failure now have the core C++ behavior, but exact diagnostics and unconstrained placeholder `Iterable<T>` construction still need the import-manager/core-decl path used by C++.

Completeness estimate: 72% of C++ behavior for this scoped expression type-checking area, weighted by behavior rather than line count.
