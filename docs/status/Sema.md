# Sema Port Status

Sema reference inspected:

- Public headers under `/root/cj_build/cangjie_compiler/include/cangjie/Sema`.
- Source/component inventory under `/root/cj_build/cangjie_compiler/src/Sema` (261 C++ `.cpp`/`.h` files, about 96.5K lines).

Current Cangjie port state:

- Replaced the single `SemaScaffold.cj` with a multi-file package.
- Added real Cangjie data structures for Sema constraints/substitutions/blames.
- Added a functional `TypeManager` over the existing self-hosted AST type hierarchy for primitive, tuple, function, array, pointer, nominal type construction, structural equality, simple substitution, declared-super traversal, and conservative subtype/compatibility checks.
- Added plugin API-level parsing/version comparison and plugin custom annotation metadata support.
- Added real leaf expression helpers for parenthesized expressions, optional-chain expressions, tuple literals, loop-control jumps, throws, and returns over the current self-hosted AST/TypeManager surfaces.
- Added compiling public entrypoints for generic instantiation, type checking, desugar, incremental helpers, test helpers, lookup, collection, diagnostics, join/meet, promotion, and scope utilities.

Known gaps:

- This is not a complete faithful port of C++ Sema. The full C++ algorithms for type inference, overload resolution, generic constraint solving, inheritance merging, desugaring, FFI/CJMP/plugin checks, initialization legality, and expression-specific type checking still need to be ported.
- Several required upstream/downstream C++ surfaces (`Frontend`, full `Macro`, full `IncrementalCompilation`, and complete `Modules` integration) are not yet available as faithful Cangjie packages, so affected Sema entrypoints still contain self-host Sema TODO markers with compiling conservative bodies.
