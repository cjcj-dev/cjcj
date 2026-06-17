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
- `TypeCheckPattern.cj`: added C++-shaped constant-pattern equality resolution: built-in equality types return directly, while non-built-in exact-typed constants synthesize and check an overloaded `==` call stored in `operatorCallExpr`.
- `TypeCheckBuiltinExpr.cj`: added C++-shaped target-driven pointer constructor inference so `CPointer` calls with invalid/generic pointee types can take a valid pointer target type, and tightened `CFunc` construction to require a direct reference callee like the C++ `RefExpr` guard.
- `TypeCheckPattern.cj`: tightened enum-pattern target discovery so member-access and placeholder ref fallbacks only keep declarations owned by an `EnumDecl`, matching the C++ guards that reject stale or non-enum call/member candidates before arity matching.
- `TypeCheckPattern.cj` / `PatternUsefulness.cj`: aligned type-pattern subtype checks with the C++ `implicitBoxed: true, allowOptionBox: false` form for runtime-match classification, unreachable type-pattern checks, wildcard equivalence, and type-constructor coverage.
- `TypeCheckMatchExpr.cj`: threaded the real basic diagnostic engine through selector/no-selector match helpers so OR-pattern binding errors, mixed OR-pattern kinds, no-selector cases without a type, and no-selector matches without a default now emit the same diagnostic families as the C++ implementation.
- `TypeCheckMatchExpr.cj`: aligned OR-pattern same-kind checking with the C++ raw-`ASTKind` comparison after the enum-like exemption, while keeping resolved var-or-enum names only for diagnostic text.
- `TypeCheckBuiltinExpr.cj`: tightened two-argument `Array` constructor validation to match the C++ split between unnamed function initializers and `repeat:` element initializers, including the raw-array lambda parameter subtype direction and precise basic diagnostics for wrong array argument names/arity where the diagnostic engine is available.
- `TypeCheckCall.cj`: mirrored the C++ `IsInterfaceFuncWithSameSignature` overload tie-breaker so duplicate abstract interface functions with the same instantiated signature are suppressed instead of producing a false ambiguity after normal candidate comparison.
- `TypeCheckCall.cj` / `TypeCheckBuiltinExpr.cj`: reused the real AST `IsValidCFuncConstructorCall` helper so function-pointer calls skip rechecking already validated `CFunc<...>(CPointer(...))` constructors like C++, and threaded CFunc constructor diagnostics for wrong arity, named arguments, and non-pointer operands through the existing basic diagnostic engine.
- `TypeCheckBuiltinExpr.cj`: threaded the basic diagnostic engine through pointer expression/call checking, including C++-shaped reports for too many `CPointer` arguments, unknown pointer generic inference, named pointer constructor arguments, non-pointer/non-CFunc operands, and target-type mismatches.

Build status:

- `cjpm build` passes for the whole workspace after this pass.
- Remaining warnings are pre-existing warnings outside this scope.
- Remaining `TODO(selfhost:Sema)` markers in the five scoped files: 0.
- Package-wide `grep -rn "TODO(selfhost:Sema)" packages/sema/src` still reports 4 markers, all outside this scoped call/match/pattern/builtin/usefulness area.

Known fidelity gaps:

- The C++ `TypeCheckCall.cpp` still has deeper behavior not fully available in this self-host surface: local type argument synthesis, constraint-version rollback, full import/access filtering, re-export ordering, complete generic call mapping, variadic desugaring/recovery, operator-call desugaring, ToTokens checks, static/non-static member call validation, and rich candidate diagnostics.
- Pattern usefulness/checking is functional but still conservative around complete sealed hierarchy discovery, full intersection/union/Option refinements, and diagnostics that depend on richer C++ Sema context.
- Builtin and match checking use real AST and type data but still lack the full TypeCheckerImpl cache/synthesis integration present in C++.

Honest coverage estimate for this scoped pass: about 69% of C++ behavior, materially higher than the prior compiling stubs but not module-complete.
