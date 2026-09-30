# Root constructor registration

The source fixtures exercise the real compiler with a minimal `std.core` for
CHIR tests. `run.py` collects compiler exit codes, CHIR artifacts, compiler and
loaded-library hashes, CPU affinity, and uptime. It does not treat successful
compilation as a finalizer assertion.

`root.cj` covers the root return and a multilevel construction chain;
`delegated.cj` covers a delegated constructor. The const fixtures cover a
finalizable object, a shared global reference, a temporary outside the result
graph, a nested finalizable object, and a non-finalizable folding control.

The minimal core fixtures cannot substitute for the real core package during
code generation: the package initialization path requires its exception raiser.
For IR checks, compile the complete pinned `stdlib/libs/std/core` sources with
`integration/core_probe.cj` added to a private source copy. This supplies the
real exception and package initialization definitions, and adds two source-level
allocation callers for the finalizable and non-finalizable comparisons.

The compiler package changes are held for combination with cjcj-llvm#109 and
cangjie-runtime#1394. Compiler CHIR/IR checks do not establish runtime registration
timing for a mixed compiler/LLVM/runtime installation. Rebuild the standard
library and imported CHIR with the complete candidate combination before use.
