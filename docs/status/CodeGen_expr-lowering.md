# CodeGen Expr Lowering Status

Last updated: 2026-06-18 12:23 CST

This pass deepened the CHIR-to-LLVM expression/statement/terminator lowering core under
`packages/codegen/src`.

Implemented in this pass:

- De-isolated call lowering onto real `cangjie_compiler::chir.Apply` and `ApplyWithException` classes and now sends
  arguments through the existing `CGFunctionType`/`CGValue` ABI-aware `IRBuilder2.CreateCallOrInvoke` path instead of
  raw `LLVMValueRef` calls. This preserves sret/unit/CFunc attribute handling already present in CodeGen.
- Added C++-named split files for previously collapsed/missing lowering components:
  `FieldExprImpl.cj`, `IntrinsicsDispatcher.cj`, `InvokeImpl.cj`, and `OverflowDispatcher.cj`.
- Added typed field lowering for `Field` and `FieldByName`, including pointer aggregate GEP+load and non-pointer
  aggregate extract-value lowering.
- Fixed static `GetElementRef` lowering to use the real CHIR path payload rather than treating only runtime operands as
  indices.
- Added intrinsic lowering for real CHIR `Intrinsic` and `IntrinsicWithException` nodes for the subset supported by the
  current self-hosted IRBuilder surface: unsafe markers, begin-catch, reference equality, size/alignment, CPointer init,
  CPointer address/add/read/write, CString conversion/init, bitcast, inout pointer conversion, null checks, and overflow
  intrinsic routing.
- Added `IntOpWithException` terminator lowering using the node's stored `opKind`, including divide-by-zero checks,
  overshift checks, and LLVM overflow intrinsics for throwing add/sub/mul/neg.
- Routed `INTRINSIC_WITH_EXCEPTION`, `INT_OP_WITH_EXCEPTION`, and the invoke-with-exception family through
  `HandleWithExceptionTerminator`, matching the C++ dispatcher shape more closely.
- Added a conservative direct-call fallback for `Invoke`/`InvokeStatic` when the target method can be resolved from the
  real CHIR custom type metadata. Unresolved virtual/vtable cases remain unmapped rather than being faked.

Remaining gaps:

- Full C++ virtual dispatch (`InvokeImpl.cpp`) still needs runtime type-info/vtable/mtable helper coverage in the
  self-hosted IRBuilder before it can be behavior-faithful.
- `InstanceOfExprImpl.cpp`, `SpawnExprImpl.cpp`, broad runtime/reflect/array intrinsic families, checked-overflow
  Option construction, and full enum/boxed/generic type transformations are still partial outside the subset above.
- Some unsupported intrinsic and spawn paths still return typed null/unit fallbacks because the corresponding sibling
  runtime/codegen surfaces are not yet modeled in this self-hosted package.

Verification:

- Baseline `cjpm build` passed before edits.
- `cjpm build` passed after the implementation, with only the pre-existing unrelated frontend unused-import warning.
- Remaining `TODO(selfhost:CodeGen)` markers in `packages/codegen/src`: 0.
