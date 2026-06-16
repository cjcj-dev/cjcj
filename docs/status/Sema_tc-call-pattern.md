# Sema tc-call-pattern Port Status

Scope updated in this pass:

- `PatternUsefulness.cj`: replaced the self-host TODO stub with a real Maranget-style usefulness/exhaustiveness matrix over the current AST pattern/type model, including tuple/enum/bool/unit/literal constructors, OR expansion, wildcard specialization, and reachability/exhaustiveness diagnostics through the real basic diagnostic package.
- `TypeCheckPattern.cj`: replaced the stub with pattern checking over real AST and TypeManager types for wildcards, const patterns, type patterns, var patterns, enum/var-or-enum patterns, tuple patterns, enum constructor target binding, and irrefutability checks.
- `TypeCheckMatchExpr.cj`: replaced the stub with match expression synthesis/check helpers for selector/no-selector forms, guard/action checking, sugar-aware paths, case type joining, and selector exhaustiveness/reachability integration.
- `TypeCheckBuiltinExpr.cj`: replaced the stub with builtin call checking for array, value-array, pointer, C string, CFunc, and builtin type constructor calls over real AST builtin declarations and type aliases.
- `TypeCheckCall.cj`: replaced the stub with call candidate collection, named/positional argument validation, lambda syntax filtering, variadic eligibility checks, argument-to-parameter compatibility, overload comparison, function pointer calls, call kind classification, selected target binding, and call type synthesis over the current self-hosted AST/TypeManager surfaces.

Continuation updates:

- `TypeCheckCall.cj`: added C++-shaped post-selection checks for abstract class and interface construction, `This` return binding for member calls, inout legality, VArray inout requirements for C/foreign calls, unsafe C function invocation checks, C unit-argument rejection, C-struct autobox prevention, and string-argument diagnostic forwarding for the relevant old diagnostic kinds.
- `TypeCheckPattern.cj`: added C++-shaped enum-pattern constructor type instantiation for generic enum cases, including member-access base `instTys` propagation from the selector enum type and placeholder selector constraining through `TypeManager.ConstrainByCtor`.
- `TypeCheckPattern.cj`: tightened constant-pattern literal checking with the C++ rune and `UInt8` single-character string literal special cases, ideal numeric literal retargeting to the selector type, range validation, delayed string-interpolation rejection, and the final exact type-equality rule.
- `TypeCheckPattern.cj`: aligned type-pattern runtime-check decisions with the C++ `IsNeedRuntimeCheck` logic for final runtime types, class-like/generic relationships, and bidirectional boxed subtype checks.
- `TypeCheckPattern.cj`: aligned var-pattern duplicate binding behavior with C++ by exempting compiler-generated `v-compiler` bindings and specific-vs-common pattern bindings, while preserving full package metadata on generated var declarations.

Build status:

- `cjpm build` passes for the whole workspace after this pass.
- Remaining warnings are pre-existing warnings outside this scope.
- Remaining `TODO(selfhost:Sema)` markers in the five scoped files: 0.
- Package-wide `grep -rn "TODO(selfhost:Sema)" packages/sema/src` still reports 4 markers, all outside this scoped call/match/pattern/builtin/usefulness area.

Known fidelity gaps:

- The C++ `TypeCheckCall.cpp` still has deeper behavior not fully available in this self-host surface: local type argument synthesis, constraint-version rollback, full import/access filtering, re-export ordering, complete generic call mapping, variadic desugaring/recovery, operator-call desugaring, ToTokens checks, static/non-static member call validation, and rich candidate diagnostics.
- Pattern usefulness/checking is functional but still conservative around complete sealed hierarchy discovery, full intersection/union/Option refinements, operator-overloaded constant-pattern equality synthesis, and diagnostics that depend on richer C++ Sema context.
- Builtin and match checking use real AST and type data but still lack the full TypeCheckerImpl cache/synthesis integration present in C++.

Honest coverage estimate for this scoped pass: about 60% of C++ behavior, materially higher than the prior compiling stubs but not module-complete.
