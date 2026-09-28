# Heap graph qualification

`fixtures/compiler_heap_graph.cj` links the real AST and CHIR libraries from a
stage0 compiler build. It does not recompile model copies of those classes.
The extra `Parent` class gives one known reference to an AST `RefExpr`; the
CHIR `Function` has no reference to that expression.

Compile the fixture with the same official host SDK and the stage0 build's
package `.cjo`/`.a` files. Include the normal LLVM shim object and host LLVM
library when linking CHIR. Run the same executable with `pre` and `post`
arguments. At `READY`, take the official `cjprof heap --dump` snapshot; the
program keeps its objects alive for eight seconds and then checks their values.
Save the executable/library hashes, actual process maps, exit codes, and logs.

Qualification requires all of the following:

- Both executions and dumps succeed, with identical executable hashes.
- Both reach `TARGET_VALUE_PASS`; this checks real object state after the dump.
- The post arm reports a completed GC, `WEAK_BEFORE=1025`, and `WEAK_AFTER=1`.
  The pre arm reports `WEAK_AFTER=1`. These are positive and negative controls
  for the weak-reference observation, not compiler memory thresholds.
- In both snapshots, the sole `Parent` reference resolves to its `RefExpr`.

On official HRT SHA
`a656fbc7d16e0fa2c61598fc68a74bb55948834e428c908fed17c945783f3988`,
the last condition fails after GC: the reference ID has no corresponding
object record. The official analyzer also omits the child from the parent's
retained graph. See cjcj#633. Raw histogram records include additional dead
expressions, while the calibrated weak-reference count is one.

Consequently, neither `compiler_heap_owners.cpp` nor a raw-ID reachability
reader qualifies AST lifetime claims on these snapshots. They remain offline
diagnostics, not acceptance gates. Do not loosen their thresholds or interpret
unresolved references as zero retained memory. Compiler RSS measurements must
use the uninstrumented compiler; a separate diagnostic build may observe
weak-reference liveness as allowed by the compiler memory investigation.
