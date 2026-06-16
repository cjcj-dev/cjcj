# CHIR Checker Port Status

Date: 2026-06-17

Build: `cjpm build` passes.

Reference inspected:

- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Checker/CHIRChecker.h`
- `/root/cj_build/cangjie_compiler/src/CHIR/Checker/CHIRChecker.cpp`
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Checker/UnreachableBranchCheck.h`
- `/root/cj_build/cangjie_compiler/src/CHIR/Checker/UnreachableBranchCheck.cpp`
- Current self-hosted CHIR IR support in `packages/chir/src/{Base,Type,Value,Expression,Terminator,Package,CHIRBuilder,Utils}.cj`

Implemented in this pass:

- Expanded `CHIRChecker.cj` from a block-only structural check into a C++-shaped package checker with rule flags mirroring the C++ `CHIRChecker::Rule` set.
- Added global/custom identifier uniqueness checks, imported C-function duplicate allowance, duplicate reporting, and package-wide traversal over functions, globals, and custom type definitions.
- Added global-variable checks for ref-shaped storage types, initializer requirements, source/package names, and static-member consistency.
- Added function-base checks for function type validity, C function type constraints, member-parent consistency, package name, return-type stage rules, parameter type legality, body parameter/type consistency, return-value storage checks, and abstract-with-body rejection.
- Added custom-type checks for duplicate/nonempty member names, invalid member types, method parent links, and extend target validity.
- Ported C++ block-group and block invariants over the current IR: owner links, entry block presence, nonempty block rule, block-id uniqueness, top-level function consistency, terminator position, terminator jump target block-group checks, and predecessor/successor symmetry.
- Added expression-level validation for parent/result back-links, operand use-lists, nested block-group owner links, terminator arity/successors, branch condition types, coarse unary/binary type rules, memory load/store type rules, call-like argument/result checks, constant literal/result checks, and `GetInstantiateValue` stage rejection.
- Added local result identifier uniqueness and a reachable-operand/generic-type walk shaped after the C++ `CheckUnreachableOpAndGenericTyInFuncBody`, limited to the generic/value/type APIs currently present in the self-hosted IR.

De-isolation:

- No module-local compatibility copies of Basic/Lex/AST/Parse/Option/diagnostic types were present in the checker files. The implementation continues to use real CHIR package types from the existing package.

Remaining gaps:

- The C++ checker has many checks on specialized CHIR expression classes (`Apply`, `Invoke`, `Tuple`, `Field`, `RawArrayAllocate`, RTTI, intrinsic, exception, virtual dispatch, vtables, generic instantiation maps, and more). The self-hosted IR currently represents most of these as generic `Expression` values, so this pass ports only the invariants expressible without inventing fake local fields.
- C++ diagnostics use `DiagnosticEngine` and source ranges; the self-hosted checker still reports through `CHIRCheckResult` strings.
- Other C++ checker components (`AnnotationChecker`, `ComputeAnnotations`, `OverflowChecking`, `VarInitCheck`) are not newly ported here.

Estimated checker behavior coverage vs C++ in this scope: 30%.
