# CHIR Serializer/Deserializer Port Status

Date: 2026-06-18

Build: `cjpm build` passes.

Reference inspected:

- `/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRSerializer.cpp`
- `/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRDeserializer.cpp`
- `/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRSerializerImpl.h`
- `/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRDeserializerImpl.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Serializer/CHIRSerializer.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Serializer/CHIRDeserializer.h`

Implemented in this pass:

- Deepened the existing `CHIR-TEXT\t2` format without breaking older records by appending expression/custom
  metadata fields instead of renumbering existing fields.
- Added C++-faithful type payload coverage for `CPointerType` and raw array dimensions; raw arrays no longer
  deserialize all shapes as one-dimensional arrays, and C pointer element types are now preserved.
- Extended custom type definition records toward the C++ `CustomTypeDef` flatbuffer shape: source-code
  identifier, public `AnnoInfo`, static member variables, instance-var init function, generic declaration,
  implemented interface types, superclass type, and C-struct flag now round-trip when exposed by the Cangjie IR.
- Changed custom type member serialization to use direct instance variables, matching the C++ serializer's
  class-member behavior instead of duplicating inherited fields through `GetInstanceVars()`.
- Extended `MemberVarInfo` round-tripping beyond name/type/static/readonly: raw mangled name, attribute info,
  debug location, annotation info, initializer function, and outer definition are now serialized and restored.
- Added an appended expression payload field and concrete deserialization paths for the exposed CHIR expression
  classes: branch source expression, multibranch case values, integer-operation exception kind, allocation target
  type, static and dynamic element refs, named element refs, apply/invoke call metadata, virtual method offsets,
  instance-of target type, generic instantiation types, RTTI static type, field paths/names, raw-array allocation
  element type, intrinsic kind and instantiation types, debug source identifier, spawn execute closure, for-in
  block groups, and lambda signature metadata.
- Added deferred expression payload repair for lambda return values and parameter-default host lambdas after all
  expression result locals have been registered.
- Added a local generated reverse map for every `IntrinsicKindName` case so intrinsic payloads deserialize back to
  the real `IntrinsicKind` enum without changing the shared intrinsic enum source.

Previous implemented work retained:

- Replaced the single compatibility `Serializer.cj` with C++-named serializer/deserializer entry and
  implementation files: `CHIRSerializer`, `CHIRDeserializer`, `CHIRSerializerImpl`,
  `CHIRDeserializerImpl`, and `CHIRSerializationFormat`.
- Added a versioned `CHIR-TEXT\t2` wire format while keeping the previous `CHIR-TEXT\t1` reader path.
- Added a context-aware `SerializePackage(pkg, context)` overload that emits deterministic source-file map
  records from `CHIRContext`, and deserialization registers those records back into the builder context before
  debug-location-bearing nodes are configured.
- Added real type round-tripping for builtins, tuples, function types including C-function and vararg flags,
  raw arrays, varrays, refs, boxes, generic types with source names and upper bounds, `This`, and nominal
  struct/class/enum types.
- Added package-level serialization for access level and package init/literal-init function references.
- Added custom type definition records for local and imported structs/classes/enums/extends, generic
  parameters, instance member variables, enum constructors, superclasses, implemented interfaces, extension
  links, extended types, debug locations, attributes, and public base annotation-map entries.
- Added global variable and function records that preserve stable value ids, source identifiers, raw mangled
  names, package names, types, initializer links, feature strings, parent custom definitions, annotations,
  function kind, body/return links, generic-declaration/default-host links, property locations, debug
  locations, attributes, and public base annotation-map entries.
- Added function parameter records preserving parameter ids, identifiers, source identifiers, types,
  annotations, debug locations, attributes, and public base annotation-map entries.
- Added block group, block, and expression records preserving body ownership, entry blocks, block order,
  landing-pad exception class types, explicit predecessor lists, expression order, result locals, operands,
  expression-owned block groups, terminator successors, constant literal payloads, debug locations, attributes,
  and public base annotation-map entries.
- Extended expression result-local records toward the C++ `LocalVar` serializer shape: result source-code
  identifiers, return-value flags, debug locations, attributes, and public base annotation-map entries now
  round-trip with the expression result.
- Added lambda-owned parameter payloads to expression records, matching the C++ `Parameter` distinction between
  function-owned and lambda-owned parameters; lambda parameter ids, identifiers, source identifiers, types,
  annotations, debug locations, attributes, and public base annotations now round-trip before nested lambda-body
  expression operands are resolved.
- Deserialization is now multi-pass: package/custom defs, globals/functions/parameters, block groups/blocks,
  relationship configuration, expression creation, explicit predecessor repair, block-group entry/owner repair,
  and package function repair.
- Removed local compatibility stand-ins; serializer/deserializer uses the real CHIR package types and builder.
- `grep -rn "TODO(selfhost:CHIR)" packages/chir/src` reports no markers.

Known gaps:

- The C++ implementation writes/reads the official FlatBuffers package format. This self-hosting pass uses a
  deterministic textual format for the current Cangjie CHIR model, so binary compatibility with the C++ serializer
  is still not complete.
- C++ annotations stored in `Base` are only partially exposed in the current Cangjie CHIR APIs; this pass preserves
  debug locations, attributes, public `AnnoInfo`, and string annotation-map entries exposed by `Base.GetAnno()`,
  but not the full typed annotation union.
- Specialized expression payloads beyond the current Cangjie model are still represented by generic expression
  kind, operands, result, literals, and successors. Full C++ expression-class payload parity remains.
- Function local/block/block-group id counters and C++ original lambda signature metadata are not exposed by the
  current Cangjie `Function` API and are not serialized yet.
- Callers that still use `SerializePackage(pkg)` without a `CHIRContext` cannot emit source file path tables because
  `Package` does not expose the owning context; the new `SerializePackage(pkg, context)` overload covers callers
  that have the builder/context available.
- Overflow-strategy fields, typed C++ annotation unions, vtable payloads, original lambda info on `Function`,
  enum exhaustiveness, and annotation-class target lists are still limited by missing or not-yet-wired Cangjie IR
  APIs in this package.

Honest coverage estimate for CHIR serializer/deserializer scope: 55%.
