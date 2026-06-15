# Mangle Port Status

Date: 2026-06-15

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
- Implemented declaration, package, prefix, generic-argument, function-parameter, user-defined type,
  tuple, function, array, VArray, pointer, CString, local-variable, local-function, lambda, extend,
  export-id, and entry-function mangling logic over the descriptor model.
- Implemented recursive mangler context collection for local variables, wildcard pattern variables,
  local functions, lambdas, extends, and global wildcard pattern declarations.
- Implemented parser-AST type annotation mangling, including primitive, reference, qualified, option,
  constant, VArray, parenthesized, function, tuple, generic, inherited type, generic constraint,
  and var-with-pattern name handling.
- Implemented CHIR-specific mangling utilities for virtual/mutable dispatch names, generic instantiation,
  lambdas, overflow operators, annotation functions, closure helper classes, wrapper classes,
  abstract dispatch helpers, and CHIR type qualified names.

Known fidelity caveats:

- The C++ public API takes real `AST`, `Basic`, and CHIR objects. This package cannot currently import
  `cangjie_compiler::ast` or `cangjie_compiler::basic` without editing package metadata, and this task
  explicitly disallows `cjpm.toml` edits. The port therefore exposes a faithful local descriptor model
  rather than direct AST/CHIR bindings.
- The descriptor model preserves the mangling grammar and indexing algorithms, but it depends on callers
  to populate AST/CHIR-equivalent fields that the C++ implementation obtains from real compiler nodes,
  semantic types, files, function bodies, annotations, and parent links.
- The C++ walker visits the full compiler AST, including statement bodies and annotations. The Cangjie
  context collector recurses through descriptor `members`, so downstream integration must map real
  function bodies, local declarations, lambdas, annotations, and pattern declarations into that tree.
- Export-id handling covers the recursive member path and property accessor mangling shape, but exact
  generic-parameter export-id side effects need real AST generic declarations before they can be matched
  byte-for-byte with the C++ implementation.

Remaining Mangle selfhost markers: 0.
