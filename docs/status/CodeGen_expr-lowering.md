# CodeGen Expr Lowering Status

Last updated: 2026-06-18 13:47 CST

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

Continuation update:

- Added real `GetRTTI` and `GetRTTIStatic` lowering in the others dispatcher. Dynamic RTTI now loads the object header
  `TypeInfo*` using the same header layout as the CJNative C++ helper; static RTTI now emits the corresponding
  `CGType` type-info global instead of returning a typed null value.
- Added `InstanceOfExprImpl.cj` to mirror the C++ component split and route `INSTANCEOF` expressions through the real
  Cangjie CHIR `InstanceOf` class. The implementation covers the C++ object-type cases for Any/generic runtime split,
  class subtype checks, tuple `llvm.cj.is.tupletype.of`, and static subtype fallback through `llvm.cj.is.subtype`.
- Extended builtin intrinsic lowering for `GET_TYPE_FOR_TYPE_PARAMETER` and `IS_SUBTYPE_TYPES`, matching the C++
  `GenerateBuiltinCall` paths through TypeInfo metadata and the `llvm.cj.is.subtype` intrinsic.
- Routed `STORE_ELEMENT_REF` and `STORE_ELEMENT_BY_NAME` through the memory dispatcher instead of falling through to a
  typed null value.
- Added core `StoreElementRef` lowering for CHIR value/location/path nodes: materialize the value and aggregate
  location, build the static GEP index list from the real CHIR path, and emit the LLVM store. Empty static paths now
  return no value instead of silently storing through the base pointer, matching the C++ checker contract.
- Added conservative `StoreElementByName` and `GetElementByName` support by resolving member names through the real
  `chir.CustomType` metadata (`GetAllInstanceVars`, including raw mangled names) before lowering as path-based element
  access. C++ normally expects these nodes to have been rewritten by `UpdateMemberVarPath`; this keeps self-hosted
  lowering robust when serialized or partial CHIR still contains name-based forms.
- Ported the C++ no-op store guards that can be represented by the current self-hosted backend surface: class null
  constants and stores of unit values into return slots now do not emit an LLVM store for `Store` or element-store
  lowering.
- Deepened `EXIT` terminator lowering toward the C++ return-slot path. Value-less exits now use the real owning
  `chir.Function` return type and return-value slot: void-like functions emit `ret void`, raw-array return slots from
  raw-array allocation return the mapped allocation directly, ordinary return slots are loaded before returning, and
  sret functions copy the result into LLVM argument 0 before `ret void`. The old direct `Exit(Some(value))` path is
  preserved for simplified self-hosted CHIR, but now respects void-like and sret function ABIs.
- De-isolated core terminator dispatch for `GoTo`, `Branch`, and `MultiBranch` onto the real CHIR terminator classes.
  `MultiBranch` lowering now uses `chir.MultiBranch.GetCaseVals()` and case successor accessors, matching the C++
  dispatcher's switch construction from stored case constants instead of incorrectly treating runtime operands as case
  labels.
- Added `SpawnExprImpl.cj` to mirror the C++ component split and routed both `SPAWN` and `SPAWN_WITH_EXCEPTION` through
  the real CHIR `Spawn`/`SpawnWithException` classes. Future-spawn now resolves `Future.execute`, materializes the
  optional thread context, calls the external CJ thread runtime (`CJ_MCC_NewCJThread`), checks the null result path via
  `SpawnException`, stores the runtime thread handle back into the Future thread object, and returns the Future object.
- Added closure-spawn lowering for `executeClosure`, including result `TypeInfo` plumbing and the
  `CJ_MCC_NewCJThreadNoReturn` runtime call. The result remains unused just like the C++ path.
- Extended `IRBuilder2` with the spawn runtime-call helpers, `SpawnException` construction through implicit runtime
  CHIR, class-object allocation through the LLVM `llvm.cj.malloc.object` intrinsic, and the
  `_CNat6Thread24setRuntimeCJThreadHandleHPu` helper call used by Future spawn.

Remaining gaps:

- Full C++ virtual dispatch (`InvokeImpl.cpp`) still needs runtime type-info/vtable/mtable helper coverage in the
  self-hosted IRBuilder before it can be behavior-faithful.
- Spawn lowering now emits the real runtime thread creation path, but full parity still needs exact C++ object-payload
  field addressing for `CreateGEP(CGValue, {0})`, fully dynamic generic `TypeInfo` creation, and assertion-equivalent
  handling for verifier-invalid missing Future/closure metadata.
- Broad runtime/reflect/array intrinsic families, checked-overflow Option construction, and full enum/boxed/generic type
  transformations are still partial outside the subset above.
- The new `InstanceOf` lowering relies on static `CGType` TypeInfo creation for generic-related target types; full
  dynamic generic TypeInfo construction still belongs with broader IRBuilder type-info parity.
- Full C++ aggregate element addressing still needs a self-hosted equivalent of `IRBuilder2::CreateGEP(CGValue, path)`,
  including class payload extraction, raw-array element addressing, base-pointer propagation, auto-env offsets, and
  generic field-offset intrinsic handling. The current pass improves dispatcher coverage but does not claim parity for
  those layout-sensitive paths.
- Full C++ return lowering still has unsupported debug-exit metadata handling, C FFI return post-processing, override
  source-function boxing optimizations, and allocation-time sret slot reuse. This pass ports the ordinary return-slot
  and sret-copy behavior that fits the current self-hosted backend surface.
- Some unsupported intrinsic and verifier-invalid compatibility paths still return typed null/unit fallbacks because the
  corresponding sibling runtime/codegen surfaces are not yet modeled in this self-hosted package.

Verification:

- Baseline `cjpm build` passed before edits.
- `cjpm build` passed after the implementation, with only the pre-existing unrelated frontend unused-import warning.
- Continuation `cjpm build` passed after RTTI, type-info intrinsic, and InstanceOf lowering changes, with the same
  unrelated frontend warning.
- Continuation `cjpm build` passed after memory element-store/name-path lowering changes, with the same unrelated
  frontend warning.
- Continuation `cjpm build` passed after return-slot `EXIT` terminator lowering changes, with the same unrelated
  frontend warning.
- Continuation `cjpm build` passed after real `GoTo`/`Branch`/`MultiBranch` terminator dispatch changes, with the same
  unrelated frontend warning.
- Continuation `cjpm build` passed after spawn runtime-call lowering changes, with the same unrelated frontend warning.
- Remaining `TODO(selfhost:CodeGen)` markers in `packages/codegen/src`: 0.
