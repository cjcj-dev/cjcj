# Generic struct receiver copies

The receiver wrapper must copy an unknown-size value using the boxed receiver's
real TypeInfo. A synthetic `i8_array` describes no references and therefore cannot
supply the GC layout for this copy. Reference loads follow
`zBarrierSet.inline.hpp:173-179`; the headerless stack payload is a Cangjie ABI
adaptation.

Run on kkk2 with a private SDK and the built compiler:

```sh
export CANGJIE_HOME=/absolute/private/sdk
export LD_LIBRARY_PATH=/absolute/host/runtime:/absolute/host/stdlib:/absolute/llvm
export PAYLOAD_RUN_LD=/absolute/product/runtime:/absolute/product/stdlib:/absolute/llvm
bash test/generic_this_payload/run.sh /absolute/cjcj-stage1 /absolute/evidence
```

`PAYLOAD_RUN_HEAP` defaults to `96G`, the product runtime spelling. The official
host's `cjHeapSize=96GB` may be supplied separately for compilation. Keep both
runtime and boundscheck libraries in the selected product runtime directory.

The six independent assertions inspect the compiler's actual IR and executable:

* Ordinary and hidden-result-slot receivers must pass a native alloca, the boxed
  `this` object and its dynamically loaded size to the payload-read intrinsic,
  then pass that same native payload to the method.
* Mutable receivers must keep forwarding both the base and interior pointer;
  known-layout receivers must keep their typed field load.
* Both immutable receiver wrappers must lower to `CJ_MCC_ReadGenericPayload`.

The fixture also executes and checks the returned reference/value and mutation.
This small execution alone does not prove relocation correctness. The IR/ELF
checks establish the compiler's layout selection; an end-to-end bootstrap is
recorded separately in the lane evidence.

A product fault arm restores `CreateFunctionWrapperForNormalCases` to its old
`CallGCReadAgg` plus synthetic `i8_array` layout, rebuilds the compiler and reruns
this unchanged suite. Exactly the two dynamic-layout and two lowered-call checks
must fail; both controls must pass. Restore the source and rebuild in the same
path to check that the compiler identity and all six checks return to the
candidate result. Each assertion logs even after another assertion fails.

For the TreeMap bootstrap reproducer, rebuild and install the standard library
with the candidate compiler **before linking stage2**. `nextNode` is supplied by
`libcangjie-std-collection.a`; rebuilding only compiler sources leaves the old
wrapper in the final executable. Preserve the old archive/ELF as a control, and
check the rebuilt archive's wrapper relocation targets before testing stage2.
