# CHIR Transform/Optimization Deepening Status

This pass deepens three existing CHIR transform/optimization files against the
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

Estimated behavior coverage for the touched transform/optimization surface is
about 24% versus the C++ reference. The changes above remove several unsafe
behavior differences but the overall CHIR transform/optimization module remains
far from complete.
