# Mangle Port Status

Date: 2026-06-18

Build: `cjpm build` passes.

Implemented:

- Replaced the Mangle scaffold with a multi-file Cangjie package mirroring the C++ Mangle components:
  `MangleUtils`, `StdPkg`, `Compression`, `BaseMangler`, `ASTMangler`, `CHIRMangler`,
  `CHIRManglingUtils`, and `CHIRTypeManglingUtils`.
- Ported the C++ mangling constants, primitive/operator encodings, standard-package compression table,
  decimal mangling numbers, file-private name hashing, compiler-added class names, and common helpers.
- Ported the C++ compression parser/tree renderer for variables, functions, default-parameter functions,
  paths, composite types, function types, tuple types, and recursive entity/type output.
- Added descriptor-backed equivalents for declarations, files, semantic types, parser type annotations,
  generic constraints, function parameters, and patterns.
- Added a module-local dependency on `cangjie_compiler::ast` and an AST adapter that converts real
  AST packages, declarations, files, semantic `Ty` instances, parser type nodes, generics, function
  bodies, function parameters, patterns, inheritance, properties, and member trees into the Mangle
  descriptor model.
- Added AST-walker-backed mangler context collection so AST-facing mangling now discovers local
  variables, wildcard pattern declarations, nested functions, lambdas, extends, and global wildcard
  pattern declarations from real function bodies and blocks, matching the C++ walker structure.
- Extended real-AST context collection to class/interface/struct/enum member variable initializer scopes,
  matching the C++ local-scope collection trigger for composite member variables.
- Added public AST-backed overloads for `BaseMangler.Mangle`, `BaseMangler.MangleExportIds`,
  `BaseMangler.MangleExportId`, `BaseMangler.MangleLambda`, `ASTMangler.Mangle`, and top-level
  `MangleAstType`; AST declaration mangling now accepts C++-shaped `ArrayList<Node>` prefix paths.
- Added AST-facing `MangleUtils` overloads for primitive type lookup, auto-boxed declaration checks,
  enum-element mangling, file-private suffix mangling, and custom-identifier mangling.
- Implemented declaration, package, prefix, generic-argument, function-parameter, user-defined type,
  tuple, function, array, VArray, pointer, CString, local-variable, local-function, lambda, extend,
  export-id, and entry-function mangling logic over the descriptor model.
- Implemented recursive mangler context collection for local variables, wildcard pattern variables,
  local functions, lambdas, extends, and global wildcard pattern declarations.
- Aligned lambda numbering with the C++ context-index lookup and aligned export-id handling with the
  C++ function/property/primary-constructor/interface-generic branches.
- Aligned global var-with-pattern prefix handling, private/default-init extend prefix handling,
  common/specific generic-parameter naming, parser-AST `MainDecl` return mangling, parser-AST static
  constructor spelling, and parser-AST property accessor return-type fallback with the C++ rules.
- Aligned top-level-only core runtime special-function mangling and all-initial-parameter function
  parameter mangling with the C++ `BaseMangler` behavior, including native-backend runtime throw helpers.
- Aligned parser-AST extend generic-constraint ordering with the C++ stable sort by constrained type.
- Aligned parser-AST constant type annotation conversion with the C++ use of literal `stringValue`.
- Aligned descriptor and CHIR generic type references with the C++ declaration-order stack index.
- Aligned descriptor AST generic-parameter and generic-type reference failures with the C++ assertion
  behavior by rejecting undeclared generic references instead of aliasing them to `G0`.
- Aligned real-AST lambda indexing for declaration annotation arrays with the C++ two-bucket lookup, so
  lambdas in function/constructor/global/member annotation arrays are numbered after body lambdas.
- Aligned parser-AST member-parameter accessibility mangling with C++ modifier-list based emission.
- Implemented parser-AST type annotation mangling, including primitive, reference, qualified, option,
  constant, VArray, parenthesized, function, tuple, generic, inherited type, generic constraint,
  and var-with-pattern name handling.
- Implemented CHIR-specific mangling utilities for virtual/mutable dispatch names, generic instantiation,
  lambdas, overflow operators, annotation functions, closure helper classes, wrapper classes,
  abstract dispatch helpers, and CHIR type qualified names.
- Added a direct dependency on the real `cangjie_compiler::chir` package and real-CHIR overloads for
  CHIR type mangling, primitive encoding, type qualified-name rendering, virtual/mutable dispatch wrapper
  names, instantiated function names, lambda wrapper names, overflow operator names, closure helper names,
  wrapper class names, abstract dispatch helpers, and override helper names.
- Aligned real and descriptor CHIR generic type handling with the C++ assertion behavior by rejecting
  undeclared generic type references instead of silently mapping them to `G0`.
- Aligned real-CHIR virtual/wrapper helper names with the C++ `CustomTypeDef::GetIdentifierWithoutPrefix`
  behavior and made CHIR prefix replacement reject non-`_C` inputs instead of silently preserving them.
- Aligned real-CHIR custom type identifier fallback in type mangling and type qualified-name rendering so
  C++-shaped `@`-prefixed `CustomTypeDef` identifiers are normalized before use.
- Aligned CHIR overflow-operator helper-name generation with the C++ assertion behavior by rejecting
  unsupported operator spellings instead of emitting a malformed `_CO` name.
- De-isolated Mangle linkage handling to the real `Linkage` enum re-exported by `cangjie_compiler::ast`,
  removing the module-local `MangleLinkage` clone and adapter conversion.
- De-isolated CHIR overflow helper APIs to the real `OverflowStrategy` enum re-exported by
  `cangjie_compiler::ast`, removing the module-local overflow-strategy clone.
- De-isolated descriptor declaration/type-annotation/pattern kind handling to the real
  `cangjie_compiler::ast.ASTKind`, removing the module-local `MangleAstKind` clone and the adapter's
  kind conversion layer.
- De-isolated descriptor declaration and function-parameter attributes to the real
  `cangjie_compiler::ast.Attribute`, removing the module-local `MangleAttribute` clone.
- De-isolated descriptor semantic type kinds to the real `cangjie_compiler::ast.TypeKind` and
  `TypeKindName`, removing the module-local `MangleTypeKind` clone and conversion layer.
- De-isolated descriptor CHIR type kinds to the real `cangjie_compiler::chir.TypeKind`, removing the
  module-local `CHIRTypeKind` clone and sharing the same primitive dispatcher as real CHIR overloads.
- De-isolated CHIR helper APIs to the real `cangjie_compiler::chir` value/type/definition classes by
  removing the module-local `CHIRType`, `CHIRFunction`, and `CHIRCustomTypeDef` compatibility models and
  the duplicate descriptor overloads that depended on them.
- Aligned parser-AST `FuncParam` declaration suffix mangling with C++ `IsMemberParam`: ordinary function
  parameters no longer receive the member-var type discriminator, while primary-constructor member
  parameters still do.
- Aligned extend indexing buckets with C++ semantic-type grouping by using the converted extended
  semantic type string when available instead of the parsed annotation spelling.
- Aligned CHIR type and type-qualified-name fallthrough behavior with C++ `CJC_ASSERT` paths by rejecting
  invalid or unsupported type kinds, missing descriptor element/base payloads, malformed CPointer types,
  and AutoEnv descriptor misuse instead of emitting empty or partial names.
- Aligned descriptor semantic-type and extend-entity failure behavior with C++ `CJC_ASSERT`/null-check paths
  by rejecting unsupported user-defined type kinds, missing nominal declarations, malformed raw-array and
  CPointer payloads, missing function-parameter semantic types, and incomplete extend context/index data.
- Aligned real-CHIR virtual/mutable wrapper names for extend definitions with the C++ implementation by
  appending sorted implemented-interface type mangles before the package suffix.
- Aligned real-CHIR raw-array type mangling with C++ `RawArrayType::GetDims()` instead of assuming a
  single-dimensional raw array, and switched real-CHIR CPointer mangling/qualified-name rendering to the
  concrete `CPointerType` element API.
- Aligned real-CHIR custom type qualified-name rendering with C++ generic-instantiation behavior by using
  the generic declaration package when `CustomTypeDef.GetGenericDecl()` is present.
- Aligned real-CHIR custom type identifier normalization with the C++ `CustomTypeDef::GetIdentifierWithoutPrefix`
  contract for `@_C...` names while preserving self-hosted `_C...` and source-name identifiers, and made
  qualified-name rendering prefer public source identifiers while falling back to normalized mangled names
  for private/internal-style definitions.
- Aligned lambda prefix package selection with the C++ `ManglePrefix` rule by deriving lambda package
  mangling from the nearest declaration in the prefix instead of relying on lambda descriptor package
  metadata.
- De-isolated `CHIRMangler.MangleCFuncSignature` to accept the real `cangjie_compiler::ast.FuncTy`
  alongside the descriptor overload, matching the C++ `AST::FuncTy` API shape.
- Aligned AST-facing package export-id generation with the C++ package walker by visiting real AST nodes,
  requiring `Ty.IsTyCorrect`, and then copying export IDs back through the adapter.
- Aligned parser-AST malformed type-annotation handling with C++ assertion/null-check behavior for missing
  parenthesized, option, function-return, VArray element/constant, qualified-base, and constant-literal
  payloads, and for unsupported AST type-annotation kinds.
- Aligned descriptor enum-constructor generic ownership with the real AST `Decl.GetGeneric()` behavior by carrying
  the real `Attribute.ENUM_CONSTRUCTOR` through the adapter and using it when a function body has a parent enum.
- Aligned local variable mangling with C++ `BaseMangler::MangleVarDecl` by emitting the `K` count prefix whenever a
  prepared package context exists, then appending the member/local index payload according to the discovered scope.
- Added the C++ `VAR_WITH_PATTERN_DECL` branch to descriptor `MangleDeclName` so direct helper calls preserve the
  reference `MangleDecl` behavior in addition to the common `Mangle` entry point.
- Aligned AST adapter member conversion with the real AST `Decl.GetMemberDeclPtrs()` API used by C++ export-id
  recursion, so enum constructors are preserved in descriptor member trees instead of only enum body members.
- Aligned descriptor `GetGeneric()` with real AST enum-member behavior: `VarDecl` members of generic enums now inherit
  the enum generic parameter list just as `Decl.GetGeneric()` does in the sibling AST package.
- Aligned parser-AST file-private suffix mangling with the C++ null-check and short-filename behavior: missing
  `curFile` now fails instead of fabricating `"$"`, and filenames shorter than `.cj` use the full filename rather
  than a hash.
- Aligned wildcard pattern declaration mangling with the C++ assertion path: all-wildcard validation, prepared package
  context, current file metadata, outer local scope, and registered wildcard index are now required instead of silently
  falling back to local index `0`.
- Aligned private prefix and global wildcard-pattern file handling with the C++ null-check behavior by rejecting
  missing `curFile` metadata before emitting file-private discriminators.

Known fidelity caveats:

- The C++ public API exposes functions named `MangleType`, but the current Cangjie package already owns a
  descriptor class named `MangleType`. Cangjie does not allow a top-level function with the same name, so
  real CHIR type mangling is exposed through the existing `MangleCHIRType` overload family until the
  descriptor layer is fully retired.
- Real CHIR overloads now use `cangjie_compiler::chir` objects directly where the scaffold carries the
  needed metadata. Some C++ CHIR details are still not represented in the self-hosted CHIR package, notably
  `CustomType.IsAutoEnvGenericBase`/`IsAutoEnvInstBase` and `LinkTypeInfo`-style internal linkage queries
  for custom type defs, so those assertion-guarded branches use the currently available CHIR fields.
- CHIR custom-type and function identifiers in the self-hosted CHIR builder can still be source-style or `_C`-prefixed
  where the C++ CHIR API usually presents `@`-prefixed identifiers before `GetIdentifierWithoutPrefix()`. Mangle keeps
  compatibility normalization for those current sibling-CHIR shapes until CHIR enforces the C++ identifier contract.
- The AST adapter maps the currently available self-hosted AST package into the Mangle descriptor model
  and prepares package context from `curFile.curPackage` when available. Byte-for-byte validation against
  full parser/sema output still depends on downstream packages producing complete annotation arrays,
  semantic types, parent links, and file/package metadata.
Remaining Mangle selfhost markers: 0.
