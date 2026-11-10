# Native result copies

Build `producer/values.cj` as the `typed_copy_values` static package with the
normal installed `bin/cjc -O2 --save-temps`, then compile and link `main.cj`
against that package using the same installation. Run the resulting executable.
The two markers verify both native result branches and the independent
reference-bearing return control.

Inspect the producer's pre-optimization bitcode: `choosePair` and `chooseByte`
must contain complete `llvm.cj.copy.no.ref.struct` transfers from entry allocas
to their same-type noalias sret argument, with concrete `AggType` metadata.
`referenceControl` must keep the normal reference-bearing copy/root path.
The paired LLVM runtime-lowering pass must lower only the native transfers
before SROA. Retain the actual post-optimization IR and executable identity.
No source annotation, inlining threshold or GC option is changed for this test.

This producer requires the early native-copy lowering in LLVM commit
3b32800b796a1ee0bee30cc33699163e15db58c0 for the intended optimization.
Older backends still implement the intrinsic, but lower it too late for SROA.
The fixed old two-byte example was measured at cost 265 with late lowering and
235 with early lowering; 235 still exceeds its 225 inline threshold. This test
therefore does not assert an elapsed-time improvement or that threshold is met.
