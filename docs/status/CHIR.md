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
- Extended `RedundantLoadElimination` to use a reaching-definition analysis before its local fallback,
  replacing loads from exact reaching stores and repeated loads across block boundaries when the domain proves
  a single reaching definition.
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
- Added `SIntDomain`, combining numeric `ConstantRange` bounds with symbolic value bounds, including
  top/bottom construction, literal/numeric/symbolic relational constructors, symbolic negation, expression
  relation mapping, intersection/union, same-domain checks, and basic arithmetic composition.
- Added `ValueDomain`, including abstract objects, reference roots/caching, reference representation checks,
  and the C++-shaped bottom/ref/value/top join behavior used by later value-analysis passes.
- Added `FlatSet` and `ReachingDefinitionAnalysis`, mirroring the C++ reaching-definition lattice shape for
  tracked allocation results: bottom/single/top facts, reaching store/load queries, fixed-point propagation over
  block successors, conservative invalidation for mutable calls/intrinsics/lambda captures, recursive lambda block
  discovery, and block entry/exit result storage.
- Added `GenKillAnalysis`, `MaybeUninitAnalysis`, and `MaybeInitAnalysis` components. The Cangjie versions provide
  the shared reachable gen/kill domain, constructor initialization metadata, allocation tracking, maybe-uninit and
  maybe-init domains, line tracking for stores that initialize allocations/members, block fixed-point propagation,
  recursive lambda-body traversal, constructor super/delegating-call handling, and member initialization queries
  over the current `CustomTypeDef`/generic memory-expression model.
- Added `ConstMemberVarCollector`, collecting readonly non-static member candidates whose declared type can hold
  class-like values, scanning constructors for member stores, tracing forwarding local values through casts/boxing
  conversions, invalidating ambiguous or open-class assignments, and recording unique concrete derived member types
  by custom-definition id and member index.
- Added `GetOrThrowResultAnalysis` and `RedundantGetOrThrowElimination`, including the C++ `std.core.getOrThrow`
  matcher, a bottom/element/top per-argument result domain, block fixed-point propagation, recursive lambda-body
  traversal, and replacement of later redundant `getOrThrow` result uses with the first dominating result in the
  function body.
- Added `DevirtualizationInfo`, collecting concrete runtime return-type summaries, class/interface subtype
  inheritance summaries, type-to-definition mappings, and const-member-derived-type data through
  `ConstMemberVarCollector` for the current CHIR package model.
- Added `OptFuncRetType` plus `Function.ReplaceReturnValue` and `ReturnTypeShouldBeVoid`, converting eligible
  constructor/finalizer/global-init functions from `Unit` return to `Void`, clearing old return slots, removing
  removable unit return storage, and updating generic `APPLY`/`APPLY_WITH_EXCEPTION` call sites.
- Added C++-named BCHIR interpreter component files for `OpCodes`, `BCHIR`, `BCHIRPrinter`,
  `BCHIRInterpreter`, `InterpreterValue`, `InterpreterValueUtils`, `InterpreterArena`,
  `InterpreterEnv`, and `InterpreterStack`.
- Ported the BCHIR opcode inventory and metadata from `OpCodes.inc`, including stable opcode numbering,
  human labels, fixed operand counts, and exception-handler flags.
- Added an interpreter value model covering the C++ `IVal` families: signed/unsigned integer widths,
  floats, rune/bool/unit/null/string primitives, pointers, tuples, arrays, objects, and function
  references, with literal conversion, equality, truthiness, and debug rendering helpers.
- Added explicit BCHIR argument/control stacks, local/global environment storage with frame base pointers,
  and an interpreter arena for pointer-like allocated values.
- Added BCHIR definitions and package sections for bytecode cells, annotations, functions, globals,
  string/type/file sections, serialized class info, linked class tables, default-function pointers,
  main/global-init metadata, cloning, removal, and deterministic insertion-order definition storage.
- Added a BCHIR printer that emits linked bytecode, function/global definitions, annotations, string/type/file
  sections, and serialized class entries in a readable form.
- Added a working BCHIR interpreter subset for primitive constructors, strings, tuples/arrays/objects,
  allocation, local/global load/store, frames, drop/store, jumps, branches, returns/exits, integer/float/bool
  unary and binary operations, equality, and literal result extraction.
- Added C++-named CHIR-to-BCHIR component files for `CHIR2BCHIRAtomic`, `CHIR2BCHIR`, `TranslateValue`,
  and `BCHIRLinker`.
- Added a real CHIR-to-BCHIR package translator for the currently implemented IR model: package metadata,
  global initializers, function bodies, parameters, local variable slots, blocks, block jump placeholders,
  class/struct/enum/extend method tables, primitive constants, local/global/function references, unary/binary
  expressions, allocation/store, tuple/array/apply expressions, goto/branch/exit terminators, string and type
  section interning, and compile-time filtering.
- Added a BCHIR linker that combines package bytecode into a linked top-level definition, resolves function
  placeholders, assigns global/class/method ids, remaps string references, adjusts local branch/jump offsets,
  links serialized class method tables, installs default function pointers, emits global initializers, and
  provides a dummy abort target for unresolved functions.
- Extended the BCHIR interpreter with function application and return-frame handling so linked bytecode can
  call translated functions through the argument/control stacks.

Known gaps:

- This is not a complete faithful port of C++ CHIR. The full C++ AST-to-IR lowering, complete
  expression taxonomy, checker suite, complete BCHIR translator/interpreter/linker, binary
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
- `RedundantLoadElimination` now has the C++ reaching-definition shape and cross-block fixed-point
  propagation, but static-member call adjustment, precise specialized memory-expression classes, and the
  complete C++ alias/intrinsic model remain incomplete.
- `UselessAllocateElimination` cannot yet honor class finalizer exclusions because the current Cangjie
  `ClassDef` model has not ported the finalizer link.
- `SInt` and `ConstantRange` cover the core value/range domain semantics needed by later passes, but the full
  C++ arbitrary edge cases, saturation operations, and complete multi-interval preference logic remain to be
  ported.
- `SIntDomain` and `ValueDomain` are real analysis domains over the current IR, but the C++ template
  abstraction, complete arithmetic transfer functions, and integration with the fixed-point analysis engine
  are still pending.
- `MaybeInitAnalysis` and `MaybeUninitAnalysis` now model the C++ gen/kill behavior for the current IR, but
  precise `Debug` expression filtering, specialized `StoreElementRef` metadata, exact `IsInitialisingMemberVar`
  semantics, and full constructor-call annotations are still limited by the not-yet-complete expression classes.
- `ConstMemberVarCollector` mirrors the C++ constructor-scan and unique-derived-type logic over the current generic
  expression model, but exact direct/all inherited instance-var splitting, specialized `StoreElementRef` path
  metadata, final/inheritance flags, and full `CanBeInherited` semantics remain limited by the current IR model.
- `RedundantGetOrThrowElimination` follows the C++ state-before-expression replacement behavior over generic
  `APPLY` operands, but it does not yet include the complete C++ engine visitor/debug-location reporting surface or
  specialized `Apply` accessors.
- `DevirtualizationInfo` has real return/subtype/const-member collection over the implemented Cangjie IR, but
  exact `GlobalOptions`, `Modules::GetPackageRelation`, `Attribute::SKIP_ANALYSIS`/`INTERNAL`, closure-conversion
  auto-env metadata, and specialized `Apply`/`TypeCast` source-type accessors are approximated by current package
  names, annotations, and generic expression operands.
- `OptFuncRetType` implements the C++ unit-to-void function rewrite over the current generic expression model, but
  exact `Apply`/`ApplyWithException` reconstruction, instantiated type arguments, `this` type, and super-call flags
  remain limited until specialized call-expression classes are ported.
- The BCHIR translator/linker/interpreter now has the first real end-to-end package/function/global/control
  path, but exact float/rune byte encoding, the complete expression taxonomy, intrinsics/syscalls, exception
  machinery, object method dispatch, raw-array operations, type casts, full serialization, and FFI execution
  paths remain to be ported.
- The current implementation establishes a compiling, real IR core that downstream CHIR work can build on,
  but it is far below full C++ CHIR behavioral coverage.

Remaining CHIR selfhost markers: 0.
