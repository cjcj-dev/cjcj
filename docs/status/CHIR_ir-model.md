# CHIR IR-Model Deepening Status

Date: 2026-06-18

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

- Added the missing CHIR `VIRTUAL` attribute to the self-hosted attribute table, display order, and CHIR wire
  attribute parsing/serialization without shifting existing serialized attribute indices.
- Added C++ `Function`-style generic type parameter storage and builder plumbing for function containers.
- Ported the C++ `GetOutDefDeclaredTypes`/visible-generic collection behavior needed by `GetInstantiateValue.Clone`,
  including function/class/lambda/block ownership traversal and extend-definition type-argument reordering.
- Updated `GetInstantiateValue.Clone` to adjust instantiated type arguments for inlined parent functions when the
  generic result is a local lambda value, matching the C++ inlining-aware clone path.
- Tightened `CustomTypeDef.CanBeInherited()` to the C++ predicate: interface, virtual, or abstract, rather than all
  class-like definitions.
- Added C++ `DebugLocation.h`-style `Position`, invalid location/name constants, absolute-path/file-name storage,
  begin/end position accessors, macro/normal invalid-position checks, scope-info copy accessors, C++-style
  `ToString()`/`Dump()`, and equality semantics while preserving the existing serialized `fileId/line/column/length`
  compatibility fields used by current CHIR serializers and analyses.
- Aligned `BaseCommentToString()` with the C++ behavior now that debug locations render their own `loc:` prefix.
- Added function-owned block-group creation, `Block.Clone`, `BlockGroup.Clone` for function and lambda owners, deep
  block cloning with base/exception/result metadata preservation, and successor retargeting through a cloned block map.
- Added C++-style structured clone overrides for `ForInRange`, `ForInIter`, `ForInClosedRange`, and `Lambda`, including
  cloned body/latch/condition groups, lambda clone identifier suffixing, compile-time/local/default-host metadata
  preservation, parameter recreation, and return-value rediscovery in the cloned body.
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
- Added C++ `IntrinsicKind.h`-style reverse lookup functions for core, overflow, reflection, interop,
  OHOS Ark interop, cjnative sync, runtime, math, headless, and package-dispatched intrinsic classification.
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
- Added concrete C++-style clone overrides for non-structured expression and terminator IR nodes, including unary/binary
  ops, constants, memory access, calls, virtual dispatch, RTTI, casts, boxing/transforms, tuples/fields, raw-array/VArray
  nodes, intrinsics, debug/spawn, normal terminators, and exceptional terminators. Clones now rebuild through the matching
  builder factory and carry base metadata plus result-local metadata forward instead of falling back to lossy generic
  `Expression` cloning.

De-isolation:

- No CHIR IR-model-local compatibility copies of Basic/Lex/AST/Parse/Option/diagnostic types were found in the
  scoped files. The pass avoided adding new local clones.

Known remaining gaps:

- The structured clone path mirrors C++ block/group ownership and successor retargeting, but still shares operand
  values exactly as the existing expression clone layer does; full local-value remapping would need a broader inliner
  and substitution pass audit.
- Function generic type parameters are now represented in the IR model, but CHIR serializer/deserializer records still
  need a format extension before generic function parameters round-trip through `.chir`.
- Interpreter/codegen-specific intrinsic tables outside `IntrinsicKind.h`, such as AST FFI and concrete-width atomic
  lowering maps, still need downstream porting outside this IR node/type model slice.
- Full C++ generic constraint solving, vtable search/update, inheritance traversal through extends, and precise
  finalizer semantics are still missing; dynamic dispatch currently records method context and optional vtable offsets
  but does not compute vtable search results.
- CHIR package metadata and type-lowering APIs still cannot expose exact AST/Sema/Basic signatures without package
  dependency work outside this IR-model scope.
- Serializer/BCHIR/codegen consumers still cover only the subset represented by the current Cangjie IR model.

Remaining `TODO(selfhost:CHIR)` markers in `packages/chir/src`: 0.

Estimated real behavior coverage for this IR-model scope: 72%.
