# Sema Desugar Status

Last updated: 2026-06-17

## Current pass

- Deepened `packages/sema/src/Desugar/AfterTypeCheck/CallExpr.cj` against the C++ `AfterTypeCheck/CallExpr.cpp` reference:
  - replaced the empty token-call body with real `std.ast.Token(...)` desugaring to `std.ast.refreshPos(Token(...), fileID, line, column)`;
  - preserved the C++ guards for invalid types, already-desugared calls, `TOKEN_CALL` recursion avoidance, non-ref callees, wrong package targets, empty argument lists, and calls that already carry position arguments;
  - marks the inner `Token(...)` call with `SugarKind.TOKEN_CALL`, propagates source/cur-file information, and carries the original token type onto the generated `refreshPos` call.
- Deepened `packages/sema/src/Desugar/DesugarBeforeTypeCheck.cj` against the C++ `DesugarBeforeTypeCheck.cpp` reference:
  - added real `@IfAvailable` desugaring for `level` and `syscap` arguments, including the SDK-26 `apiAvailable(...)` split, legacy `DeviceInfo.sdkApiVersion >= N` checks, string triple parsing via the real `sema.Plugin.APILevelVersion`, invalid-literal fallback cloning, and source/cur-file propagation;
  - replaced unconditional branch unitification with a discarded-value context stack modeled after the C++ `DiscardedHelper`, including block-child, loop, finally, constructor, explicit `Unit` return, parenthesized, `if`/`try`/`match`, synchronized-body, and function-body propagation rules;
  - fixed unitification to recognize only literal `()` as unit, rather than treating every literal as already unit-like;
  - handled `tryLambda` branch bodies during try-expression unitification;
  - added tuple-assignment handling for optional-chain lvalues, producing compiler-added `OptionalChainExpr` assignment nodes rather than plain cloned lvalue assignments.
- Continued the in-type-check desugar port in `packages/sema/src/Desugar/DesugarInTypeCheck.cj` with real lowering for pipeline expressions (`a |> f` to `f(a)`) and composition expressions (`f ~> g` to `composition(f, g)`), including `operator()` wrapping for non-function callees, flow-expression marking, `sourceExpr`, unsafe propagation, and cur-file propagation.
- Continued the after-instantiation desugar port in `packages/sema/src/Desugar/DesugarAfterInstantiation.cj` with the C++ pass's declaration attribute update behavior: default marking for initialized variables, `--export-for-test` linkage/`FOR_TEST` handling for extend and foreign functions, property linkage propagation, and coverage line-info clearing for generic-instantiated declarations.
- Added a package-local before-type-check desugar traversal in `packages/sema/src/Desugar/DesugarBeforeTypeCheck.cj` with concrete lowering for synchronized expressions, optional chains, increment/decrement, tuple assignment, option types, main declarations, trailing closures, and branch unitification.
- Added after-type-check package traversal in `packages/sema/src/Desugar/AfterTypeCheck.cj` and connected it to the existing local desugar helpers for range expressions, calls, binary/coalescing expressions, casts, type checks, `if`, `spawn`, and function parameters.
- Implemented `??` discovery in `AfterTypeCheck/Coalescing.cj` so existing coalescing lowering is applied through a tree walk.
- Replaced the `ForInExpr` placeholder with real range-for lowering in `AfterTypeCheck/ForInExpr.cj`, including closed and half-open ranges, `where` guards, first-iteration handling, loop variable binding, and break/continue target repair.
- Removed all scoped `// TODO(selfhost:Sema)` markers from the Sema desugar area. Files that still depend on missing sibling infrastructure now keep compiling status bodies rather than TODO markers.

## Build

- `cjpm build` passes for the workspace after this pass.

## Remaining gaps

- The public root `sema.PerformDesugarBeforeTypeCheck` facade is still a no-op. The real helper currently lives in package `cangjie_compiler::sema.Desugar`; importing it into root `sema` creates a cycle through `sema.Desugar.AfterTypeCheck -> sema`. Fixing this needs a package ownership split outside this pass's allowed edit surface.
- The `desugarMacrocall` switch is not faithfully represented: the generic self-hosted walker already visits `File.originalMacroCallNodes`, so the C++ file-dispatch loop cannot be copied directly without double-walking macro-call nodes. Macro declaration and quote desugar remain substantially incomplete.
- The new after-type-check traversal is implemented in `sema.Desugar`, but the root type-checker facade is outside this pass's edit surface, so full pipeline wiring remains pending.
- `ForInExpr` currently has real range lowering only. String and iterator lowering still need faithful lookup/import-manager behavior from the C++ implementation.
- In-type-check desugar is still limited to pipeline/composition. Primary constructor lowering, compound assignment overload lowering, and other C++ in-typecheck transformations remain pending.
- After-instantiation desugar now covers declaration attributes and generic-instantiation coverage positions, but recursive type elimination, used-import marking, option/extend boxing, and dependency pruning remain pending.
- String interpolation and try-with-resources/finally details still need faithful import-manager lookup and synthesis context that are not currently threaded through the self-hosted desugar facade. Effect handlers, semantic usage collection, macro desugar, property desugar, Java/ObjC interop branches, main invocation synthesis, and linkage refresh behavior remain below C++ fidelity.

## Coverage estimate

Real behavior coverage for this scoped desugar area is about 32% versus the C++ reference. The implemented pieces now perform meaningful AST transformations, including token-call position refresh, the API-level `@IfAvailable` path, and more faithful discarded-context branch handling, but substantial C++ behavior remains either not wired into the root pipeline or represented by compiling compatibility bodies.
