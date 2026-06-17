# CHIR IR-Model Deepening Status

Date: 2026-06-17

Build: `cjpm build` passes.

Reference inspected:

- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/Type/Type.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/Type/CustomTypeDef.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/Type/{StructDef,ClassDef,EnumDef,ExtendDef}.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/Expression/{Expression,Terminator}.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/IntrinsicKind.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/{CHIRContext,CHIRBuilder}.h`
- Corresponding C++ sources under `/root/cj_build/cangjie_compiler/src/CHIR/IR` and
  `/root/cj_build/cangjie_compiler/src/CHIR/Utils/ToStringUtils.cpp`.

Implemented in this pass:

- Split nominal definition subclasses into C++-named files: `StructDef.cj`, `ClassDef.cj`, `EnumDef.cj`,
  and `ExtendDef.cj`, leaving shared container logic in `CustomTypeDef.cj`.
- Added `CustomDefKind`, `SourceExpr`, richer `MemberVarInfo`, static member vars, direct/all instance-var APIs,
  implemented-interface type storage, generic-decl links, var-init function links, and custom-def type links.
- Added `CPointerType`, raw-array dimensions, C type predicates, ref-dimension predicates, root ref-base lookup,
  C++-style function/ref/varray source rendering, and nominal def accessors.
- Wired `CHIRContext` interning for `CPointerType`, raw-array dimensions, string lookup, and nominal def-to-type
  back-links.
- Added concrete memory and apply expression classes (`Allocate`, `Load`, `Store`, element get/store by path/name,
  `FuncCallContext`, `FuncCall`, and `Apply`) plus builder factory methods.
- Added terminator accessors and concrete terminator nodes for `MultiBranch`, `RaiseException`, and
  `ExpressionWithException`, plus branch source-expression metadata.
- Continued the expression taxonomy with concrete IR classes and builders for virtual-call contexts (`FuncSigInfo`
  function names, `InvokeCallContext`, `DynamicDispatch`, `Invoke`, `InvokeStatic`), RTTI, `TypeCast`,
  `InstanceOf`, `Tuple`, `Field`, `FieldByName`, raw-array allocation/init forms, `VArray`, `VArrayBuilder`,
  `GetException`, `Debug`, `Spawn`, and `GetInstantiateValue`.
- Added concrete exceptional terminator expressions and builders for `ApplyWithException`, `InvokeWithException`,
  `InvokeStaticWithException`, `IntOpWithException`, `TypeCastWithException`, `AllocateWithException`,
  `RawArrayAllocateWithException`, and `SpawnWithException`.
- Added `IntrinsicKind.cj` mirroring the C++ intrinsic enum, including reflection and native-only intrinsic ranges,
  plus stable enum labels and C++-style `IntrinsicKindToString` names for mapped intrinsic kinds.
- Added `IntrisicCallContext`, concrete `Intrinsic`, concrete `IntrinsicWithException`, argument/type-argument
  accessors, C++-style operand rendering, and builder factory methods for normal and exceptional intrinsic calls.
- Modeled C++ nullable operands such as spawn arguments and VArrayBuilder item/init function with `Option<Value>`
  while keeping present operands in the normal CHIR use-def list.
- Added boxing/unboxing and generic/concrete transform expressions (`Box`, `UnBox`, `TransformToGeneric`,
  `TransformToConcrete`, `UnBoxToRef`) plus builders.
- Added high-level `ForIn` IR nodes (`ForInRange`, `ForInIter`, `ForInClosedRange`), body/latch/cond block-group
  initialization, and C++ execution-order accessors.
- Deepened `Lambda` with function type, identifiers, source identifier, generic params, local/compile-time flags,
  parameter-default host links, body initialization, return-value tracking, lambda-owned parameter creation, and
  C++-style captured-variable discovery that skips nested lambda bodies.

De-isolation:

- No CHIR IR-model-local compatibility copies of Basic/Lex/AST/Parse/Option/diagnostic types were found in the
  scoped files. The pass avoided adding new local clones.

Known remaining gaps:

- Full lambda body cloning/identifier regeneration and complete clone behavior for all expression subclasses remain
  incomplete.
- Reverse intrinsic classification maps from C++ `IntrinsicKind.h` (`coreIntrinsicMap`, overflow/runtime/sync/math
  maps, and FFI/name lookup integration) are not yet fully represented in Cangjie; the IR node surface and print names
  now exist.
- Full C++ generic constraint solving, vtable search/update, inheritance traversal through extends, and precise
  `CanBeInherited`/finalizer semantics are still missing; dynamic dispatch currently records method context and optional
  vtable offsets but does not compute vtable search results.
- CHIR package metadata and type-lowering APIs still cannot expose exact AST/Sema/Basic signatures without package
  dependency work outside this IR-model scope.
- Serializer/BCHIR/codegen consumers still cover only the subset represented by the current Cangjie IR model.

Remaining `TODO(selfhost:CHIR)` markers in `packages/chir/src`: 0.

Estimated real behavior coverage for this IR-model scope: 58%.
