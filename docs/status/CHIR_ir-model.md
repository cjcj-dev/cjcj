# CHIR IR-Model Deepening Status

Date: 2026-06-17

Build: `cjpm build` passes.

Reference inspected:

- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/Type/Type.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/Type/CustomTypeDef.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/Type/{StructDef,ClassDef,EnumDef,ExtendDef}.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/Expression/{Expression,Terminator}.h`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/IR/{CHIRContext,CHIRBuilder}.h`
- Corresponding C++ sources under `/root/cj_build/cangjie_compiler/src/CHIR/IR`.

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

De-isolation:

- No CHIR IR-model-local compatibility copies of Basic/Lex/AST/Parse/Option/diagnostic types were found in the
  scoped files. The pass avoided adding new local clones.

Known remaining gaps:

- The complete C++ expression taxonomy is still not ported: virtual dispatch, RTTI, type casts, intrinsics, raw-array
  operations, varray builders, for-in forms, debug expressions, boxing/unboxing, spawn, and exception-call variants
  remain incomplete.
- Full C++ generic constraint solving, vtable search/update, inheritance traversal through extends, and precise
  `CanBeInherited`/finalizer semantics are still missing.
- CHIR package metadata and type-lowering APIs still cannot expose exact AST/Sema/Basic signatures without package
  dependency work outside this IR-model scope.
- Serializer/BCHIR/codegen consumers still cover only the subset represented by the current Cangjie IR model.

Remaining `TODO(selfhost:CHIR)` markers in `packages/chir/src`: 0.

Estimated real behavior coverage for this IR-model scope: 42%.
