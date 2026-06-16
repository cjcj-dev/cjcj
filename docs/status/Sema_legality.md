# Sema Legality Status

Date: 2026-06-17
Build: `cjpm build` passes for the workspace.

## Scope

This pass covers the self-hosted Cangjie port under:

- `packages/sema/src/ConstEvaluationChecker.cj`
- `packages/sema/src/LegalityOfUsage/GlobalVarChecker.cj`
- `packages/sema/src/LegalityOfUsage/InitializationChecker.cj`
- `packages/sema/src/LegalityOfUsage/LegalityOfUsage.cj`

`CheckInternalTypeUse.cj` was left unchanged.

## Deepening Completed

- Replaced local summary stubs with analyzers that operate on the real sibling AST and Sema packages instead of compatibility copies.
- Implemented a global-variable initialization checker with def/use graph construction, declaration order edges, file-order handling, use-before-initialization issues, and cycle reporting data.
- Implemented const-evaluation legality traversal for constant declarations, annotation arguments, default parameters, const functions, class variable initialization, calls, operators, blocks, control-flow expressions, and desugared calls.
- Implemented initialization legality traversal for packages, files, declarations, class/struct/enum/interface/extend bodies, constructors, functions, blocks, loops, branching expressions, patterns, member accesses, references, assignments, and mutable/let assignment checks.
- Reconnected `LegalityOfUsage.cj` as an orchestrator for capture-kind propagation, initialization checking, global-variable initialization checking, and access-level validity checking.
- Continued fidelity work by porting the C++ const-evaluation special case for desugared `std.core.String` binary operators.
- Added the global-variable initialization issue for illegal `common static let` initialization inside a `static init`, while preserving the C++ dependency collection order for that assignment.
- Aligned constructor initialization checking with the C++ skip rule for already-checked constructors and CJMP common constructors without `COMMON_WITH_DEFAULT`.

## Remaining Fidelity Gaps

- The new analyzers currently return structured issue records, but they are not yet fully wired into the original diagnostic engine with exact C++ diagnostic ids, ranges, notes, hints, and recovery behavior.
- Some initialization edge cases still depend on sibling components that are only partially represented in the self-hosted port, especially exact scope-manager cache behavior, constructor delegation state, reachability/termination analysis, and AST context profile hooks.
- Const-evaluation coverage follows the C++ legality shape but does not yet reproduce every target-specific profile check and diagnostic specialization from the C++ implementation.
- Global-variable initialization checking models C++ def/use and cycle behavior, but final integration with compilation-unit import ordering, diagnostic formatting, and type-checker phase scheduling remains incomplete.

## Estimate

Honest behavior coverage for this legality/const-evaluation scope is about 54% versus the C++ reference. The port now has real traversal and issue production in the scoped files, plus several targeted C++ edge cases, but production completeness still requires diagnostic integration and the remaining exact semantic edge cases above.
