# Mangle Port Status

Date: 2026-06-16

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
  generic constraints, function parameters, patterns, CHIR functions, CHIR custom types, and CHIR types.
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

Known fidelity caveats:

- The C++ public API exposes functions named `MangleType`, but the current Cangjie package already owns a
  descriptor class named `MangleType`. Cangjie does not allow a top-level function with the same name, so
  real CHIR type mangling is exposed through the existing `MangleCHIRType` overload family until the
  descriptor layer is fully retired.
- Real CHIR overloads now use `cangjie_compiler::chir` objects directly where the scaffold carries the
  needed metadata. Some C++ CHIR details are still not represented in the self-hosted CHIR package, notably
  raw-array dimensions, extend implemented-interface type lists, custom type source-code identifiers, and
  internal linkage info. Those paths remain descriptor-backed or use the currently available CHIR fields.
- The AST adapter maps the currently available self-hosted AST package into the Mangle descriptor model
  and prepares package context from `curFile.curPackage` when available. Byte-for-byte validation against
  full parser/sema output still depends on downstream packages producing complete annotation arrays,
  semantic types, parent links, and file/package metadata.
- The descriptor CHIR model preserves the CHIR mangling grammar and indexing algorithms, but it depends
  on callers to populate CHIR-equivalent fields that the C++ implementation obtains from real CHIR IR.

Remaining Mangle selfhost markers: 0.
