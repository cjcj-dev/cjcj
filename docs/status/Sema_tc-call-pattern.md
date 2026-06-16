# Sema tc-call-pattern Port Status

Scope updated in this pass:

- `PatternUsefulness.cj`: replaced the self-host TODO stub with a real Maranget-style usefulness/exhaustiveness matrix over the current AST pattern/type model, including tuple/enum/bool/unit/literal constructors, OR expansion, wildcard specialization, and reachability/exhaustiveness diagnostics through the real basic diagnostic package.
- `TypeCheckPattern.cj`: replaced the stub with pattern checking over real AST and TypeManager types for wildcards, const patterns, type patterns, var patterns, enum/var-or-enum patterns, tuple patterns, enum constructor target binding, and irrefutability checks.
- `TypeCheckMatchExpr.cj`: replaced the stub with match expression synthesis/check helpers for selector/no-selector forms, guard/action checking, sugar-aware paths, case type joining, and selector exhaustiveness/reachability integration.
- `TypeCheckBuiltinExpr.cj`: replaced the stub with builtin call checking for array, value-array, pointer, C string, CFunc, and builtin type constructor calls over real AST builtin declarations and type aliases.
- `TypeCheckCall.cj`: replaced the stub with call candidate collection, named/positional argument validation, lambda syntax filtering, variadic eligibility checks, argument-to-parameter compatibility, overload comparison, function pointer calls, call kind classification, selected target binding, and call type synthesis over the current self-hosted AST/TypeManager surfaces.

Build status:

- `cjpm build` passes for the whole workspace after this pass.
- Remaining warnings are pre-existing warnings outside this scope.
- Remaining `TODO(selfhost:Sema)` markers in the five scoped files: 0.

Known fidelity gaps:

- The C++ `TypeCheckCall.cpp` still has deeper behavior not fully available in this self-host surface: local type argument synthesis, constraint-version rollback, full import/access filtering, re-export ordering, complete generic call mapping, variadic desugaring/recovery, operator-call desugaring, ToTokens checks, inout legality, unsafe CFunc checks, and rich candidate diagnostics.
- Pattern usefulness/checking is functional but still conservative around complete sealed hierarchy discovery, full intersection/union/Option refinements, and diagnostics that depend on richer C++ Sema context.
- Builtin and match checking use real AST and type data but still lack the full TypeCheckerImpl cache/synthesis integration present in C++.

Honest coverage estimate for this scoped pass: about 52% of C++ behavior, materially higher than the prior compiling stubs but not module-complete.
