# CHIR ast2chir-decl status

Date: 2026-06-17

## Scope

Deepened `packages/chir/src` declaration lowering for the existing CHIR self-host port. This pass stayed inside the CHIR package source boundary and did not touch runtime, stdx, tools, or the C++ reference tree.

## Implemented

- Split declaration lowering into C++-mirrored files:
  - `TranslateFuncDecl.cj`
  - `TranslateVarDecl.cj`
  - `TranslateClassDecl.cj`
  - `TranslateStructDecl.cj`
  - `TranslateInterfaceDecl.cj`
  - `TranslateEnumDecl.cj`
  - `TranslateExtendDecl.cj`
- Added `AST2CHIRDeclTranslator` orchestration for declaration lowering order:
  - predeclare nominal definitions
  - lower globals and top-level functions
  - fill nominal contents after symbols are available
- Extended the existing compatibility specs to describe declaration behavior now needed by the translator:
  - global attributes and optional C++-style ref storage
  - package access level and source-file registration data
  - declared package names plus raw/scoped identity aliases for globals, functions, and nominal definitions
  - function attributes, source parameter names, owner type, instance-member handling, generic-decl linking, generic instantiation children, debug locations, and property locations
  - nominal declaration specs for class, interface, struct, enum, and extend
  - nominal/global debug locations
  - ordered nominal members, member variables, properties, and enum constructors
  - package init and package literal-init function hooks
- Ported behavior that the current CHIR IR can represent:
  - package access-level setup and source-file registration in `CHIRContext`
  - global variables with literal initializer functions
  - raw-mangled and package-scoped declaration lookup aliases for predeclared/cached shells
  - declaration attribute refresh when an existing function, global, or nominal shell is reused
  - foreign functions automatically marked imported
  - function signatures with implicit `this` parameter for instance members
  - source debug locations on globals, functions, and nominal definitions
  - property source locations on getter/setter functions when supplied by specs
  - return-value allocation slots for non-`Void` lowered function bodies and global literal initializer functions
  - constructor/finalizer return normalization to `Unit`
  - no-body handling for abstract and foreign functions
  - package-level function registration plus owner `CustomTypeDef` method attachment
  - default-parameter desugar functions with host-function linkage
  - generic instantiation child functions linked back to their generic declaration
  - package init and package literal-init functions stored on the CHIR package
  - imported nominal definitions routed to package imported type lists
  - class superclass and implemented-interface links
  - interface-as-class-def lowering with abstract attribute
  - struct member/method/property lowering
  - class/interface/enum/extend property accessor attachment as member functions
  - member lowering in C++ declaration order when specs are populated through the builder API
  - C++-style member filtering for specific/common merge using descriptor source-file keys
  - instance member initializer functions emitted as owner methods
  - enum constructor payload lowering
  - duplicate enum constructor suppression at the descriptor level with payload type matching
  - extend target type setup and registration on custom or builtin extended type

## Remaining Gaps

- The CHIR package manifest currently does not depend on `cangjie_compiler::ast`; direct imports of real typed AST nodes fail unless `packages/chir/cjpm.toml` is changed. Because this task constrained edits to `packages/chir/src` plus this status file, this pass did not add the real AST entry point.
- Several C++ CHIR fields do not yet exist in the current self-host IR surface, including full annotation factory linkage, link type info, static member var storage distinct from instance fields, interface lists for struct/enum/extend defs, and deserialization cache state.
- Function body translation remains outside this declaration-only pass. Bodies emitted here are valid empty CHIR bodies for signatures that should have bodies.

## Verification

- `cjpm build` passes for the whole workspace.
- Remaining `TODO(selfhost:CHIR)` markers in `packages/chir/src`: 0.

## Coverage Estimate

For declaration lowering in this constrained CHIR package source area: about 32% behavior coverage versus the C++ AST2CHIR declaration paths. The pass materially improves symbol/nominal/member lowering over the previous package-spec summary lowering, but full typed-AST fidelity is still blocked by the package dependency boundary and missing IR features listed above.
