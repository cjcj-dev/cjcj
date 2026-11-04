# Dynamic receiver copy regression

Compile `receiver.cj` as package `receiver_copy` with the candidate public compiler, then compile and link `main.cj` against that package and the candidate-generated target std. Run the executable. The receiver has references beyond word zero; the callback changes the source record and requests a real GC while the callee still reads its own shallow copy. Changing a referenced Cell remains visible. The other assertions cover the mut receiver, escaped method and throwing callback.

Keep pre/post optimization IR for `Snapshot.observe` and the copying wrapper, including the sret call. Run the normal and compile-debug configurations through the existing public CLI flags. Successful compilation alone does not satisfy the runtime assertions. The LLVM/rootmap and exact product-cut checks are recorded in the lane report; no stress loop is added here.

The callback captures immutable class references; the source record is a mutable
field of ReceiverSource. Cangjie rejects escaping lambdas capturing mutable local
variables, so those invalid captures are not used. The source field still changes
during the callee, preserving the independent shallow-copy assertion. A native
local case separately exercises native typed source handling. Scalar copy checks
precede reference dereferences so a missing copy reaches a precise assertion.
