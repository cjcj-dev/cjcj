# CHIR Serializer/Deserializer Port Status

Date: 2026-06-17

Build: `cjpm build` passes.

Reference inspected:

- `/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRSerializer.cpp`
- `/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRDeserializer.cpp`
- `/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRSerializerImpl.h`
- `/root/cj_build/cangjie_compiler/src/CHIR/Serializer/CHIRDeserializerImpl.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Serializer/CHIRSerializer.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Serializer/CHIRDeserializer.h`

Implemented in this pass:

- Replaced the single compatibility `Serializer.cj` with C++-named serializer/deserializer entry and
  implementation files: `CHIRSerializer`, `CHIRDeserializer`, `CHIRSerializerImpl`,
  `CHIRDeserializerImpl`, and `CHIRSerializationFormat`.
- Added a versioned `CHIR-TEXT\t2` wire format while keeping the previous `CHIR-TEXT\t1` reader path.
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
- Source file path tables cannot be emitted by the current `SerializePackage(pkg)` API because `Package` does not
  expose the owning `CHIRContext`; debug locations still preserve file ids, lines, columns, and lengths.
- `TYPE_CPOINTER` exists in the enum but has no concrete Cangjie type/context constructor in this package, so
  deserialization falls back to `Invalid` for that kind.

Honest coverage estimate for CHIR serializer/deserializer scope: 38%.
