# Generic payload source provenance fixtures

These fixtures freeze the four source classes consumed by
`IRBuilder2.CallGCWriteGenericPayloadFromSrc`:

- `as0_native.cj`: native AS0 source;
- `tracked_managed_interior.cj`: AS1 interior with a tracked managed base;
- `native_view.cj`: direct AS0-to-AS1 native view;
- `whole_managed_object.cj`: whole AS1 object;
- `managed_native_managed.cj`: product-lowering shape fixture which constructs
  AS1-to-AS0-to-AS1 through `blackBox` before the ABI materializes the value;
- `managed_native_managed.ll`: synthetic downstream-verifier control for the
  same nested cast shape;
- `addrspacecast_operator.cpp`: the cjcj shim's instruction/constant-expression
  operator coverage and nested-origin discriminator.

The `.cj` files are compiled by each arm's freshly built `cjcj-stage1`.  The
compiler unit test feeds the nested operator directly to the dispatcher guard;
the `.ll` file is only the independent downstream-verifier control.  Strict
`opt -passes=cj-ir-verifier` must report
`AddrSpaceCast source must be addrspace(0)`.
