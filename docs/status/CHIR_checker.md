# CHIR Checker Port Status

Date: 2026-06-17

Build: `cjpm build` passes.

Reference inspected:

- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Checker/CHIRChecker.h`
- `/root/cj_build/cangjie_compiler/src/CHIR/Checker/CHIRChecker.cpp`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Checker/UnreachableBranchCheck.h`
- `/root/cj_build/cangjie_compiler/src/CHIR/Checker/UnreachableBranchCheck.cpp`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Checker/OverflowChecking.h`
- `/root/cj_build/cangjie_compiler/src/CHIR/Checker/OverflowChecking.cpp`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Checker/VarInitCheck.h`
- `/root/cj_build/cangjie_compiler/src/CHIR/Checker/VarInitCheck.cpp`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Checker/AnnotationChecker.h`
- `/root/cj_build/cangjie_compiler/src/CHIR/Checker/AnnotationChecker.cpp`
- Current self-hosted CHIR IR support in `packages/chir/src/{Base,Type,Value,Expression,Terminator,Package,CHIRBuilder,Utils}.cj`

Implemented in this pass:

- Expanded `CHIRChecker.cj` from a block-only structural check into a C++-shaped package checker with rule flags mirroring the C++ `CHIRChecker::Rule` set.
- Added global/custom identifier uniqueness checks, imported C-function duplicate allowance, duplicate reporting, and package-wide traversal over functions, globals, and custom type definitions.
- Added global-variable checks for ref-shaped storage types, initializer requirements, source/package names, and static-member consistency.
- Added function-base checks for function type validity, C function type constraints, member-parent consistency, package name, return-type stage rules, parameter type legality, body parameter/type consistency, return-value storage checks, and abstract-with-body rejection.
- Added custom-type checks for duplicate/nonempty member names, invalid member types, method parent links, and extend target validity.
- Ported C++ block-group and block invariants over the current IR: owner links, entry block presence, nonempty block rule, block-id uniqueness, top-level function consistency, terminator position, terminator jump target block-group checks, and predecessor/successor symmetry.
- Added expression-level validation for parent/result back-links, operand use-lists, nested block-group owner links, terminator arity/successors, branch condition types, C++-shaped unary/binary arithmetic rules, memory load/store type rules, call-like argument/result checks, constant literal/result checks, and `GetInstantiateValue` stage rejection.
- Refined unary/binary expression checking to match C++ behavior for `Nothing` operands, `%` integer-only operands, exponentiation (`Int64 ** UInt64 -> Int64` and `Float64 ** Int64/Float64 -> Float64`), bit-expression operand typing, comparison result typing, and logic expression result typing.
- Added local result identifier uniqueness and a reachable-operand/generic-type walk shaped after the C++ `CheckUnreachableOpAndGenericTyInFuncBody`, limited to the generic/value/type APIs currently present in the self-hosted IR.
- Added `OverflowChecking.cj`, mirroring the C++ checker component split. It ports signed/unsigned integer overflow checks for add, neg, sub, mul, div, mod, int exponentiation overflow, wrapping and saturating result behavior, and integer typecast overflow helpers across signedness combinations.
- Added `VarInitCheck.cj`, mirroring the C++ checker component split. It selects functions with the C++ skip rules available in the current IR, builds constructor member state, runs the real self-hosted `MaybeUninitAnalysis` and `MaybeInitAnalysis`, and checks use-before-init, uninitialized constructor exits, illegal member calls before full initialization, and reassignments to initialized `let` locals/members.
- Added `AnnotationChecker.cj`, mirroring the C++ checker component split. It collects annotation target sets from real annotation class definitions, recognizes the C++ `std.core.AnnotationKind` target names, checks custom annotation applicability on global variables, global functions, member functions, properties, constructors, parameters, type definitions, and extensions where those annotation surfaces exist in the current self-hosted CHIR, and treats an empty target set as "all targets" like the C++ pass.

De-isolation:

- No module-local compatibility copies of Basic/Lex/AST/Parse/Option/diagnostic types were present in the checker files. The implementation continues to use real CHIR package types from the existing package.
- `OverflowChecking.cj` imports the real `cangjie_compiler::utils.OverflowStrategy` instead of defining a checker-local compatibility enum; `packages/chir/cjpm.toml` now declares that dependency.
- `VarInitCheck.cj` imports the real `cangjie_compiler::utils.STATIC_INIT_FUNC` constant and reuses the existing CHIR dataflow analyses instead of introducing checker-local analysis copies.
- `AnnotationChecker.cj` uses the real CHIR `ClassDef`, `Package`, `GlobalVar`, `Function`, `Parameter`, `AnnoInfo`, and `Attribute.ANNOTATION` surfaces. It does not introduce AST/diagnostic compatibility copies; diagnostics continue to flow through the checker-local `CHIRCheckResult` abstraction already used by the self-hosted checker.

Remaining gaps:

- The C++ checker has many checks on specialized CHIR expression classes (`Apply`, `Invoke`, `Tuple`, `Field`, `RawArrayAllocate`, RTTI, intrinsic, exception, virtual dispatch, vtables, generic instantiation maps, and more). The self-hosted IR currently represents most of these as generic `Expression` values, so this pass ports only the invariants expressible without inventing fake local fields.
- C++ diagnostics use `DiagnosticEngine` and source ranges; the self-hosted checker still reports through `CHIRCheckResult` strings.
- `VarInitCheck.cj` is limited by the current generic `Expression` representation: C++ `Load`, `StoreElementRef`, `ApplyWithException`, path vectors, `SkipCheck`, and precise diagnostics are approximated through the existing operand conventions and `CHIRCheckResult` strings.
- `AnnotationChecker.cj` is limited by the current self-hosted annotation metadata. C++ `ClassDef::GetAnnotationTargets`, `CustomTypeDef::GetAnnoInfo`, `MemberVarInfo::annoInfo`, `EnumCtorInfo::annoInfo`, and `AnnoInfo::GetCustomAnnoInstances` with debug locations are not yet represented directly, so type/member/enum diagnostics are checked only through available metadata strings and `AnnoInfo.GetAnnotations()`.
- `ComputeAnnotations` is still not ported. It depends on AST declaration and const-eval plumbing not yet represented in this CHIR package.

Estimated checker behavior coverage vs C++ in this scope: 46%.
