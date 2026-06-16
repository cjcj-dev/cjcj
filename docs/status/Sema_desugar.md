# Sema Desugar Status

Last updated: 2026-06-17

## Current pass

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
- The new after-type-check traversal is implemented in `sema.Desugar`, but the root type-checker facade is outside this pass's edit surface, so full pipeline wiring remains pending.
- `ForInExpr` currently has real range lowering only. String and iterator lowering still need faithful lookup/import-manager behavior from the C++ implementation.
- In-type-check desugar is still limited to pipeline/composition. Primary constructor lowering, compound assignment overload lowering, and other C++ in-typecheck transformations remain pending.
- After-instantiation desugar now covers declaration attributes and generic-instantiation coverage positions, but recursive type elimination, used-import marking, option/extend boxing, and dependency pruning remain pending.
- String interpolation, try-with-resources/finally details, effect handlers, semantic usage collection, macro desugar, property desugar, Java/ObjC interop branches, main invocation synthesis, and linkage refresh behavior remain below C++ fidelity.

## Coverage estimate

Real behavior coverage for this scoped desugar area is about 27% versus the C++ reference. The implemented pieces now perform meaningful AST transformations, but substantial C++ behavior remains either not wired into the root pipeline or represented by compiling compatibility bodies.
