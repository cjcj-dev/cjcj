# CHIR Transform/Optimization Deepening Status

This pass deepens existing CHIR transform/optimization files against the
C++ CHIR reference while staying inside `packages/chir/src` pass-owned code.

- `DeadCodeElimination.cj`: tightened unused-expression deletion to mirror the
  C++ removable expression categories instead of deleting every unused result.
  The pass now preserves calls, stores, debug expressions, allocations,
  throwing/exception expressions, shifts/division/modulo, and arithmetic whose
  C++ overflow strategy is not represented in the current self-host IR.
- `UselessAllocateElimination.cj`: preserves allocations of class types whose
  class method list contains a finalizer, matching the C++ finalizer guard, and
  only prints debug deletion output for non-zero debug locations.
- `MergeBlocks.cj`: added option-shaped debug/coverage merge guards while
  preserving the old default API, and propagates the removed goto-only block
  debug location to its successor like the C++ pass.

Verification:

- `cjpm build` passes for the whole workspace after these changes.
- `rg -n "TODO\\(selfhost:CHIR\\)" packages/chir/src` reports no CHIR
  self-host TODO markers in `packages/chir/src`.

Remaining fidelity gaps in this transform/optimization scope:

- The current self-host CHIR IR does not expose C++ pass metadata such as
  `SkipCheck`, `GeneratedFromForIn`, `NeverOverflowInfo`, concrete `Apply`,
  `Load`, `Store`, `GetElementRef`, and `Allocate` subclasses, so exact C++
  option paths, overflow-strategy deletion, generated-for-in block splitting,
  and call-site metadata rewrites remain blocked without core IR deepening.
- Large C++ passes such as closure conversion, function/lambda inline,
  devirtualization, vtable generation, sanitizer coverage, and several array
  optimizations are still absent or represented only by smaller compatibility
  surfaces in this package.

Continuation pass:

- `UselessAllocateElimination.cj`: fixed `StoreElementRef` operand handling to
  use operand 1 as the stored-to location, matching the C++ constructor and
  serializer/deserializer contract `{value, location}`. This prevents the pass
  from mistaking the stored value for the allocation location.
- `ReachingDefinitionAnalysis.cj`: fixed the same `StoreElementRef` location
  operand in the data-flow invalidation used by redundant-load elimination, and
  conservatively handles `StoreElementByName` the same way while the
  self-hosted `UpdateMemberVarPath` pass is not yet real.
- `ConstPropagation.cj`: now recursively simplifies nested lambda block groups
  and scopes algebraic result replacement to the expression's parent block
  group, matching the C++ helper's scoped `ReplaceWith` usage more closely.

Second continuation pass:

- `ConstPropagation.cj`: added the C++-style terminator rewrite for branches
  whose condition is already a constant `Bool`, replacing the branch with a
  `GoTo` to the taken successor while preserving the original debug location
  and updating CFG predecessor/successor links through terminator removal.
- `NoSideEffectMarker.cj`: aligned the no-body function scan with the C++
  `GetGlobalFuncsWithoutBody()` default filtering, so pure abstract no-body
  declarations are no longer marked `NO_SIDE_EFFECT` by this pass.

Third continuation pass:

- `DeadCodeElimination.cj`: now repeats the unused-expression sweep to a fixed
  point for each function body, matching the C++ worklist behavior where
  removing a dead consumer can expose a newly dead producer in the same pass.
- `ReachingDefinitionAnalysis.cj`: narrowed call invalidation to the C++
  `mut` callee receiver case for tracked struct refs instead of clearing every
  non-readonly operand around calls.
- `ReachingDefinitionAnalysis.cj`: added recursive lambda capture invalidation
  for ref-typed captured values, including lambdas reached through direct
  lambda applies, mirroring the C++ `GetLambdaCapturedVarsRecursively` helper.

Fourth continuation pass:

- `UnitUnify.cj`: now recursively visits non-lambda child block groups while
  sharing one synthesized unit constant for the function body, matching the C++
  visitor behavior that continues through structured block groups but skips
  lambda bodies to avoid creating unit constants inside lambdas.

Fifth continuation pass:

- `ConstPropagation.cj`: broadened the double-unary simplification guard to
  match the C++ helper: an outer `NOT`/`BITNOT` now accepts either `NOT` or
  `BITNOT` as the inner unary before replacing the result with the original
  operand.
- `UselessAllocateElimination.cj`: aligned traversal with the C++ pass by
  scanning only the current function body's blocks. The pass no longer recurses
  into lambda block groups, which the reference implementation does not visit
  for this optimization.

Estimated behavior coverage for the touched transform/optimization surface is
about 31% versus the C++ reference. The changes above remove several unsafe
behavior differences but the overall CHIR transform/optimization module remains
far from complete.
