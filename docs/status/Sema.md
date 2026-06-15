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
- Added real leaf helpers for perform, resume, synchronized, quote, numeric type conversion, `is`/`as`, increment/decrement expressions, and FFI precheck ABI propagation over currently available AST state.
- Added generic-instantiation utility helpers and runtime-prepared type-pattern creation/runtime-check classification over the current AST/TypeManager surfaces.
- Added integer overflow strategy propagation and integer arithmetic overflow marking, including option-to-AST strategy mapping through the self-hosted compiler instance.
- Added inline-function eligibility analysis for source packages, including exportability, frozen/const ownership, internal type rejection, reference-target filtering, default-parameter propagation, imported inline function handling, and the C++ 32-node body limit.
- Added real after-typecheck desugar helpers for `is`, `as`, pipeline binary expressions, range construction, unit insertion for `if`, default-parameter debug line-info cleanup, and shared enum/ref-loop utilities. Coalescing now has the real Option-match construction helper, with traversal still blocked by missing `COALESCING` in the self-host AST token surface.
- Added literal constant range validation/ideal-type replacement plus after-typecheck helpers for spawn future construction, spawn scheduler-handle extraction, and std.core comparable intrinsic call rewriting.
- Added enum-sugar target discovery/resolution over the self-hosted AST context, including enum-constructor lookup, type-argument arity filtering, contextual target refinement through `Option`, interface-super matching, reference target updates, and generic enum type-argument instantiation.
- Added TypeManager generic-instantiation validation beyond arity, including concrete generic-parameter matching, extend instantiated-type checks, generic-parameter/type-argument substitution, and `where` upper-bound constraint subtype checks over the current AST generic constraint surface.
- Added TypeManager top-overridden-function tracking, including property getter/setter override expansion, duplicate suppression, and cycle-safe top override lookup.
- Added type-check expression diagnostic helpers for invalid multiple assignment, unary/binary/subscript expressions, inference failure, and the C++ numeric int/float comparison helper used by type compatibility.
- Added real type-check expression helpers for builtin unary expressions, range literals, spawn expressions, and literal constants, including numeric suffix/default typing, range element/step validation, future type instantiation, scheduler-handle checks, constant range validation, and `Option<T>` literal boxing over the current self-hosted type surfaces.
- Added concrete member-signature storage, type-variable constraint graph topological solving/substitution, block expression synthesis/checking over already-typed children, and unit-test mock context package-name tracking within current package dependencies.
- Added C++-shaped function linkage analysis over current AST surfaces, including modifier-based internal marking, default-parameter/property linkage propagation, exported type/reference promotion, generic source-export queues, and final internal nominal-member cleanup.
- Added the plugin custom-annotation JSON scanner (`JsonObject`/`JsonPair`) with the C++ cursor behavior for strings, numbers, arrays, object recursion, and recursive key lookup.
- Added internal-type accessibility collection for public/non-private declarations plus CJMP function parameter/generic matching and default-argument propagation helpers.
- Added C++-shaped unused-import collection over resolved AST targets, including private-vs-package-wide used maps, cache maps, extend/generic-bound target propagation, import filtering, structured unused findings, and diagnostic reporting through `sema_unused_import`.
- Added declaration-attribute propagation and validation for nominal declarations, interface/enum/struct/class/extend members, property accessors, CJMP abstract members, generic operator functions, and context parent links.
- Added access-control and mutation helpers for visibility filtering, inout receiver-use detection, `let` value access to `mut` functions, mutable-function-alone detection, and non-mut struct member mutation checks.
- Added the shared `TypeCheckUtil` helper surface for ideal-type expansion, target replacement, reference/member target maintenance, `This` return compatibility, main-declaration discovery, default-parameter marking, overloadable/builtin operator classification, function parameter type extraction, type-alias target chasing, property accessor selection, `Option` unboxing/nesting, call argument-to-parameter ordering, enum-constructor generic checks, and placeholder/questable-node classification.
- Added compiling public entrypoints for generic instantiation, type checking, desugar, incremental helpers, test helpers, lookup, collection, diagnostics, join/meet, promotion, and scope utilities.

Known gaps:

- This is not a complete faithful port of C++ Sema. The full C++ algorithms for type inference, overload resolution, generic constraint solving, inheritance merging, desugaring, FFI/CJMP/plugin checks, initialization legality, and expression-specific type checking still need to be ported.
- Several required upstream/downstream C++ surfaces (`Frontend`, full `Macro`, full `IncrementalCompilation`, complete `Modules` integration, C++ `ASTContext` diagnostic ownership, and the type-checker synthesis entrypoints needed by token desugaring) are not yet available as faithful Cangjie packages, so affected Sema entrypoints still contain self-host Sema TODO markers with compiling conservative bodies.
