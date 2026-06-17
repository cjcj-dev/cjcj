# Sema Legality Status

Date: 2026-06-17
Build: `cjpm build` passes for the workspace.

## Scope

This pass covers the self-hosted Cangjie port under:

- `packages/sema/src/ConstEvaluationChecker.cj`
- `packages/sema/src/LegalityOfUsage/GlobalVarChecker.cj`
- `packages/sema/src/LegalityOfUsage/InitializationChecker.cj`
- `packages/sema/src/LegalityOfUsage/LegalityOfUsage.cj`

`CheckInternalTypeUse.cj` was left unchanged.

## Deepening Completed

- Replaced local summary stubs with analyzers that operate on the real sibling AST and Sema packages instead of compatibility copies.
- Implemented a global-variable initialization checker with def/use graph construction, declaration order edges, file-order handling, use-before-initialization issues, and cycle reporting data.
- Implemented const-evaluation legality traversal for constant declarations, annotation arguments, default parameters, const functions, class variable initialization, calls, operators, blocks, control-flow expressions, and desugared calls.
- Implemented initialization legality traversal for packages, files, declarations, class/struct/enum/interface/extend bodies, constructors, functions, blocks, loops, branching expressions, patterns, member accesses, references, assignments, and mutable/let assignment checks.
- Reconnected `LegalityOfUsage.cj` as an orchestrator for capture-kind propagation, initialization checking, global-variable initialization checking, and access-level validity checking.
- Continued fidelity work by porting the C++ const-evaluation special case for desugared `std.core.String` binary operators.
- Added the global-variable initialization issue for illegal `common static let` initialization inside a `static init`, while preserving the C++ dependency collection order for that assignment.
- Aligned constructor initialization checking with the C++ skip rule for already-checked constructors and CJMP common constructors without `COMMON_WITH_DEFAULT`.
- Refined the `std.core.String` binary-operator check so string comparisons with non-string result types follow the C++ const-evaluation path.
- Added the C++ common-part skip in initialization checking for declarations deserialized from a common compilation unit.
- Added C++ do-while initialization rollback behavior for variables initialized after an early jump in a body that otherwise executes at least once.
- Aligned const default-parameter checking with C++ by checking only when the desugared backing declaration is present and can receive the const result.
- Replaced the earlier no-constructor member-field approximation with the C++ CJMP-specific check for non-common fields without initializers in common class/struct declarations.
- Matched C++ desugared multiple-assignment const checking by processing only `VarDecl` temporaries and expression nodes in the expanded block.
- Routed function bodies with resolved symbols through loop-style initialization rollback, matching the C++ `CheckInitInFuncBody` path more closely.
- Ported the C++ conditional-initialization branch merge for `if`, `else if`, `match`, and condition let-pattern destructors, including control-transfer suppression and the generic-bound rule used by immutable struct-member assignment checks.
- Added function-body stack tracking for initialization checking so member uses outside constructors are skipped like C++, constructor assignment context is related-type aware, and assignments no longer mark captured/different-function declarations initialized.
- Added C++-style scope-gate bookkeeping for variables visible before `return`, `throw`, `break`, and `continue`, including optional-context suppression for short-circuit/coalescing RHS checks and try-block throw handling.
- Ported constructor early-return field tracking so fields still definitely uninitialized at a constructor `return` are reported even if later unreachable assignments mark them initialized.
- Preserved first scope termination kind after per-scope context cleanup, matching C++ behavior used to skip constructor/static-init field checks after direct throwing termination.
- Routed string interpolation initialization checking through `InterpolationExpr.block`, matching the C++ traversal of interpolation blocks instead of treating interpolation wrapper expressions as leaf nodes.
- Switched member-field collection in type initialization checking to `GetVarsInitializationOrderWithPositions`, preserving the C++ common/specific field dependency order.
- Ported the missing `CheckLetFlagInMemberAccess` immutable-assignment cases for struct values returned by calls/subscripts and struct-valued property bases, using real AST type information and desugared base expressions.
- Added C++-style illegal member-access checks before full initialization: member functions/properties in member initializers, captured `this` through nested function/lambda bodies, `this.member`, `super.memberFunc`, and the distinct `super` member-variable issue before a valid member function context exists.
- Aligned global-variable def-use graph iteration with the C++ source-position ordered map, and matched static-initializer collection of uninitialized member `VarDecl`s before checking assignments in `static init`.
- Matched C++ const-evaluation short-circuiting for calls and subscript expressions so argument/index checks are skipped after a non-const callee or base has already failed.
- Ported C++ `CheckSubscriptLegality` coverage for constant `VArray` index bounds, including overflow suppression, negative-index wording, past-end details, and `ShouldDiagnose(true)` gating.
- Ported C++ `CheckStaticMembersWithGeneric` coverage for static vars, properties, and static initializers in generic declarations, including source top-level/exported-internal iteration, `RefExpr`/`RefType` generic-type detection, static generic member references, and skip-child behavior after a reported use.

## Remaining Fidelity Gaps

- The new analyzers currently return structured issue records, but they are not yet fully wired into the original diagnostic engine with exact C++ diagnostic ids, ranges, notes, hints, and recovery behavior.
- `VArray` subscript legality now records the same high-level failures as C++, but final diagnostic emission still needs the exact C++ diagnostic id and hint/range plumbing.
- Static-member generic checks now find the same high-level illegal references as C++, but still emit structured issue records rather than `sema_static_variable_use_generic_parameter` diagnostics with exact type-set formatting.
- Some initialization edge cases still depend on sibling components that are only partially represented in the self-hosted port, especially exact scope-manager cache behavior, constructor delegation state, reachability/termination analysis, and AST context profile hooks.
- The new termination and illegal-member tracking is local and uses available scope names/function-body stacks; it does not yet reproduce every C++ `ScopeManager` symbol-cache query, top-level symbol lookup, or exact `IsNode1ScopeVisibleForNode2` case.
- Const-evaluation coverage follows the C++ legality shape but does not yet reproduce every target-specific profile check and diagnostic specialization from the C++ implementation.
- Global-variable initialization checking now preserves source-order graph traversal, but final integration with compilation-unit import ordering, diagnostic formatting, and type-checker phase scheduling remains incomplete.

## Estimate

Honest behavior coverage for this legality/const-evaluation scope is about 73% versus the C++ reference. The port now has real traversal and issue production in the scoped files, several targeted C++ edge cases, the main conditional-initialization merge path, termination-aware initialization state, constructor early-return field tracking, string interpolation block traversal, dependency-aware member initialization order, immutable struct-base assignment checks, illegal member-use checks before full initialization, source-ordered global def-use traversal, const-eval call/subscript short-circuiting, constant `VArray` subscript bounds checking, and static-member generic dependency checks, but production completeness still requires diagnostic integration and the remaining exact semantic edge cases above.
