# CHIR Port Status

Date: 2026-06-16

Build: `cjpm build` passes.

Reference inspected:

- Public headers and source inventory under `/root/cj_build/cangjie_compiler/include/cangjie/CHIR`
  and `/root/cj_build/cangjie_compiler/src/CHIR`.
- Core IR headers/sources for `Base`, `Type`, `Value`, `Expression`, `Terminator`, `Package`,
  `CHIRContext`, and representative checker/analysis/optimization entry points.
- Reference inventory is 269 CHIR header/source/inc/def files, about 90K lines.

Implemented:

- Replaced the single `CHIRScaffold.cj` with a multi-file package split across CHIR components:
  enums, debug locations, annotations, attributes, base node info, types, custom type defs, context,
  literal values, values, expressions, terminators, package, builder, printer, checker, analysis,
  optimization, serializer, interpreter, transformation, and AST-to-CHIR entrypoints.
- Added a real CHIR IR object model with `Base` node ids, annotation map, debug location, and attribute
  handling.
- Added C++-shaped type hierarchy support for builtins, numeric types, tuples, function types,
  raw arrays, varrays, references, boxes, generics, `This`, and nominal class/struct/enum types,
  with C++-style classification helpers and context-level type interning.
- Added custom type definitions for structs, classes, enums, extends, member variables, enum
  constructors, generic parameters, method ownership, inheritance/interface lists, and package/name
  rendering.
- Added value hierarchy support for parameters, locals, blocks, block groups, global vars, and
  functions, including owner links, body/entry block handling, parameter lists, return-value tracking,
  function-kind flags, ID generation, imported/src-code-imported attributes, and use-list maintenance.
- Added expression and terminator graph wiring: operands update value user lists, block groups own
  region expressions, blocks own ordered expressions, terminators update successor predecessor lists,
  and values can replace their users within optional block-group scope.
- Added literal value classes for null, bool, int, float, rune, string, and unit constants.
- Added `CHIRBuilder` constructors for packages, nominal definitions, functions, globals, block groups,
  blocks, parameters, locals, constants, unary/binary/generic expressions, branches, gotos, and exits.
- Added `Package` APIs for current/imported globals, functions, structs, classes, enums, extends,
  package init functions, lookups, and combined custom-type lists.
- Added `CHIRChecker` validation for parameter count mismatches, missing entry blocks, non-final
  terminators, missing block terminators, and operand user-list consistency.
- Added basic call-graph and value-use analyses over the implemented expression/value model.
- Added a conservative dead-code elimination pass for removable side-effect-free expressions with
  unused results.
- Added textual printer and serializer surfaces over the implemented package/function/block IR model.
- Split optimization/transformation scaffolding into C++-named component files for
  `DeadCodeElimination`, `MergeBlocks`, `ConstPropagation`, `NoSideEffectMarker`, and
  `ClosureConversion`.
- Fixed expression movement so `MoveTo`/`MoveBefore`/`MoveAfter` preserve operands while deletion
  still disconnects operands, matching the C++ `Expression::MoveTo` versus `RemoveSelfFromBlock`
  distinction.
- Added terminator detach handling so successor predecessor lists are updated when terminators move
  or are removed.
- Ported the C++ `FuncInfo`/`IsExpectedFunction` matching helper used by CHIR optimizations.
- Aligned custom type source rendering with the C++ `CustomType::ToSrcCodeString`, using source
  identifiers and source-rendered generic arguments rather than fully qualified package names.
- Ported `NoSideEffectMarker` whitelist behavior for known pure stdlib functions instead of
  marking all bodyless functions.
- Implemented the C++ `MergeBlocks` unconditional-goto subset supported by the current IR model:
  single-predecessor/single-successor merge, goto-only block bypass, and recursive handling of
  lambda bodies.
- Extended DCE to remove unused no-side-effect calls when the callee is marked
  `NO_SIDE_EFFECT`.
- Added local const-propagation algebraic identities (`x + 0`, `x - 0`, shifts by zero,
  `x * 1`, `x / 1`, `x ** 1`, and idempotent bit ops) while retaining the marker for the full
  C++ constant lattice and branch rewriting.
- Fixed `Expression.ReplaceWith` so it detaches the replacement expression before insertion and
  disconnects the old expression without removing the new expression from the parent block.
- Added a real constant-evaluation subset for the currently implemented IR: literal constants,
  recursive local/global initializer lookup, integer/float/bool/string equality and comparison,
  integer arithmetic/bitwise/shift/power operations, float arithmetic, boolean `&&`/`||`, unary
  negation, logical not, and integer bit-not.
- Wired `ConstPropagation` to use the evaluator for constant folding when a `CHIRBuilder` is
  available, while preserving builder-less algebraic simplification.
- Added the C++ trivial unary rewrite shape for `!(!x)` and `~(~x)`.
- Added a CHIR-owned AST lowering input model (`AST2CHIRPackageSpec`, function specs, and global specs)
  that constructs real package/function/global IR through `CHIRBuilder` without depending on not-yet-wired
  AST/Sema package manifests.
- Implemented closure-conversion analysis over the current IR graph: recursive lambda traversal, capture
  detection, converted-lambda tracking, lambda representation marking, and boxed marking for mutable
  captured values.
- Replaced the serializer placeholder with a versioned textual package signature format that round-trips
  package names, globals, function kinds, return types, and parameter types for the implemented simple type
  model, while still accepting the older single-line package fallback.
- Added `UnitUnify`, matching the C++ pass shape for replacing used non-constant `Unit` results with a
  canonical unit constant in the owning block group while skipping lambdas and RTTI expressions.
- Added a conservative `RedundantLoadElimination` component that performs exact-location straight-line
  store/load forwarding over the current generic `STORE` and `LOAD` expression representation, clears
  knowledge across calls and memory-affecting expressions, and recurses into lambda bodies.
- Added `UselessAllocateElimination` for allocations whose result is unused except by exact stores and
  debug expressions, preserving function return-value allocations and deleting the allocation plus its
  removable users.
- Added `BoolDomain`, a direct four-state boolean lattice (`bottom`, `false`, `true`, `top`) with C++-shaped
  logical/bitwise operations, union, single-value queries, and string rendering.
- Added `SInt`, the fixed-width integer value primitive used by CHIR range analysis, with width conversion
  from CHIR types, normalization, signed/unsigned predicates, bit masks, arithmetic, shifts, and formatting.
- Added `ConstantRange`, a real half-open fixed-width range domain over `SInt`, including full/empty/singleton
  construction, relational constraints, wrapping membership checks, min/max queries, difference,
  intersection/union with signed/unsigned preference, and conservative arithmetic results.

Known gaps:

- This is not a complete faithful port of C++ CHIR. The full C++ AST-to-IR lowering, complete
  expression taxonomy, checker suite, BCHIR instruction interpreter/linker, binary
  serializer/deserializer, analyses, transformations, and optimization passes still need to be
  ported.
- The package manifest for `chir` currently has no dependencies and this task forbids manifest edits,
  so real AST/Sema/Basic/Modules/Mangle-dependent entrypoints cannot yet expose the exact C++ signatures.
- Those areas are represented by CHIR-owned data structures and compiling behavior rather than fake
  cross-package signatures; exact C++ integration remains blocked until the package dependency graph is
  available.
- The serializer is a real versioned text format for the implemented Cangjie IR model, not the complete
  C++ BCHIR/flatbuffer serializer and deserializer.
- Closure conversion currently records captures and marks lambda representation/captured value attributes;
  it does not yet synthesize the full C++ closure environment classes and rewritten call paths.
- `RedundantLoadElimination` is currently the safe local subset; the C++ reaching-definition dataflow
  engine, static-member call adjustment, and cross-block fixed-point propagation are not fully ported.
- `UselessAllocateElimination` cannot yet honor class finalizer exclusions because the current Cangjie
  `ClassDef` model has not ported the finalizer link.
- `SInt` and `ConstantRange` cover the core value/range domain semantics needed by later passes, but the full
  C++ arbitrary edge cases, saturation operations, and complete multi-interval preference logic remain to be
  ported.
- The current implementation establishes a compiling, real IR core that downstream CHIR work can build on,
  but it is far below full C++ CHIR behavioral coverage.

Remaining CHIR selfhost markers: 0.
