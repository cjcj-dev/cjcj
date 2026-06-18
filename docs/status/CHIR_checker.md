# CHIR Checker Port Status

Date: 2026-06-18

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
- `/root/cj_build/cangjie_compiler/include/cangjie/CHIR/Checker/ComputeAnnotations.h`
- `/root/cj_build/cangjie_compiler/src/CHIR/Checker/ComputeAnnotations.cpp`
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
- Refined aggregate expression checking for the current IR: `Tuple` results now dispatch by result kind and validate normal tuple element arity/types, struct member arity/types, enum selector type/constant source, enum constructor payload arity/types, and `VArray` element types.
- Added local result identifier uniqueness and a reachable-operand/generic-type walk shaped after the C++ `CheckUnreachableOpAndGenericTyInFuncBody`, limited to the generic/value/type APIs currently present in the self-hosted IR.
- Added `OverflowChecking.cj`, mirroring the C++ checker component split. It ports signed/unsigned integer overflow checks for add, neg, sub, mul, div, mod, int exponentiation overflow, wrapping and saturating result behavior, and integer typecast overflow helpers across signedness combinations.
- Added `VarInitCheck.cj`, mirroring the C++ checker component split. It selects functions with the C++ skip rules available in the current IR, builds constructor member state, runs the real self-hosted `MaybeUninitAnalysis` and `MaybeInitAnalysis`, and checks use-before-init, uninitialized constructor exits, illegal member calls before full initialization, and reassignments to initialized `let` locals/members.
- Added `AnnotationChecker.cj`, mirroring the C++ checker component split. It collects annotation target sets from real annotation class definitions, recognizes the C++ `std.core.AnnotationKind` target names, checks custom annotation applicability on global variables, global functions, member functions, properties, constructors, parameters, type definitions, and extensions where those annotation surfaces exist in the current self-hosted CHIR, and treats an empty target set as "all targets" like the C++ pass.

Deepening pass on 2026-06-18:

- `CHIRChecker.cj` now dispatches custom-type checks through struct/class/enum/extend-specific entry points, matching the C++ package traversal shape instead of using one collapsed custom-def path.
- Added custom type consistency checks for struct/class/enum definitions, direct instance member outer-def validation, inherited public/protected duplicate-member detection, static member parent/static-attribute checks, implemented-interface validation, and C-struct member CType validation.
- Tightened `CheckMultiBranch` to require exactly one selector operand and to validate the C++ invariant that case-value count equals normal-block count.
- `UnreachableBranchCheck.cj` now handles constant-selector `MultiBranch` terminators and reports all non-selected successors, bringing match/multiway branch behavior closer to the C++ constant-analysis target-successor path.
- `UnreachableBranchCheck.cj` now preserves the C++ recursion guard for branches generated by `FOR_IN_EXPR`.
- `AnnotationChecker.cj` now registers annotation targets by source-code identifier, checks custom type annotations from real `CustomTypeDef.GetAnnoInfo()`, preserves the metadata fallback, and checks direct member variable `AnnoInfo` against the member-variable target.
- `VarInitCheck.cj` now builds constructor member context like C++: all instance members in order, direct instance var count as local count, and inherited count as the difference. This fixes class constructor member-index drift caused by duplicating inherited members.

Continuation deepening pass on 2026-06-18:

- Fixed `Store` checking to follow the real CHIR `Store(value, location)` operand order, so the destination ref type and stored value type are validated against the same operands as the C++ checker.
- Split call validation into `Apply`, `Invoke`, and `InvokeStatic` paths. The checker now validates Apply callees, abstract callees, represented lambda instantiated type-argument counts, Apply `thisType` legality, Invoke/InvokeStatic generic argument counts, required Invoke `thisType`, generic upper-bound presence for Invoke `thisType`, InvokeStatic RTTI source shape, method argument arity/types, and call result types.
- Added intrinsic validation for invalid intrinsic kinds and ported the core C++ `INOUT_PARAM` checks expressible in the current IR: no type arguments, exactly one ref operand, no `&&` operand, C-type excluding `CString`, CPointer result, and invalid source value categories.
- Extended the unreachable generic-type walk to track lambda generic parameters in the same places as C++ and to check expression-owned type fields for `Allocate`, `FuncCall` instantiated type args/`ThisType`, `GetRTTIStatic`, `InstanceOf`, `RawArrayAllocate`, and `Intrinsic`.
- Kept the Apply generic-argument check conservative for global functions because the current self-host `Function` model still does not expose the C++ `Function::GetGenericTypeParams()` surface; lambda call metadata is checked where represented.

De-isolation:

- No module-local compatibility copies of Basic/Lex/AST/Parse/Option/diagnostic types were present in the checker files. The implementation continues to use real CHIR package types from the existing package.
- `OverflowChecking.cj` imports the real `cangjie_compiler::utils.OverflowStrategy` instead of defining a checker-local compatibility enum; `packages/chir/cjpm.toml` now declares that dependency.
- `VarInitCheck.cj` imports the real `cangjie_compiler::utils.STATIC_INIT_FUNC` constant and reuses the existing CHIR dataflow analyses instead of introducing checker-local analysis copies.
- `AnnotationChecker.cj` uses the real CHIR `ClassDef`, `Package`, `GlobalVar`, `Function`, `Parameter`, `MemberVarInfo.annoInfo`, `CustomTypeDef.GetAnnoInfo`, and `Attribute.ANNOTATION` surfaces. It does not introduce AST/diagnostic compatibility copies; diagnostics continue to flow through the checker-local `CHIRCheckResult` abstraction already used by the self-hosted checker.

Remaining gaps:

- The C++ checker still has deeper checks for field/path expressions, raw-array initialization, RTTI result types, exception-call variants, virtual method/vtable resolution, generic instantiation maps, generic constraint satisfaction, and builder-backed type substitution. This pass ports only the parts expressible through the current self-host CHIR APIs without inventing checker-local compatibility state.
- Tuple checks use the current self-host `StructDef`/`EnumDef` member payload types directly. They do not yet reproduce the C++ builder-backed generic substitution used by `GetInstantiatedMemberTys` and `EnumType::GetConstructorInfos`.
- Apply calls to generic global functions cannot yet validate instantiated type-argument count faithfully because `Function::GetGenericTypeParams()` is not represented in `packages/chir/src/Value.cj`; the checker avoids false positives until that shared CHIR model surface exists.
- C++ diagnostics use `DiagnosticEngine` and source ranges; the self-hosted checker still reports through `CHIRCheckResult` strings.
- `VarInitCheck.cj` is limited by the current generic `Expression` representation: C++ `Load`, `StoreElementRef`, `ApplyWithException`, path vectors, `SkipCheck`, and precise diagnostics are approximated through the existing operand conventions and `CHIRCheckResult` strings.
- `AnnotationChecker.cj` is still limited by the current self-hosted annotation metadata. C++ `ClassDef::GetAnnotationTargets`, `EnumCtorInfo::annoInfo`, and `AnnoInfo::GetCustomAnnoInstances` with debug locations are not yet represented directly, so enum-constructor diagnostics and source-range diagnostics remain incomplete.
- `ComputeAnnotations` is still not ported. It depends on AST declaration and const-eval plumbing not yet represented in this CHIR package.

Estimated checker behavior coverage vs C++ in this scope: 56%.
