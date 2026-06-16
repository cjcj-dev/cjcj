# Sema Inheritance Checker Self-Hosting Status

This pass replaces the status-only inheritance checker stubs with real Cangjie code split across the same component
names as the C++ implementation:

- `StructInheritanceChecker.cj` now walks packages, collects nominal and extend declarations, merges inherited class,
  interface, and visible extension members, checks override/implementation relationships, reports inherited kind/type
  conflicts, tracks top overrides, checks unimplemented abstract/interface members, checks mut/visibility/property
  compatibility, and validates generic upper-bound member conflicts.
- `MergeInheritedMemberHelper.cj` ports member-signature merging, generic substitution of inherited members, return-type
  inconsistency propagation, and upper-bound merging.
- `GenericInheritanceChecker.cj` ports generic upper-bound collection and mapped constraint-looseness checks.
- `InstantiatedChecker.cj` adds the instantiated generic member collision walk and C-struct type-argument checks that can
  be expressed with the current self-hosted AST and TypeManager APIs.
- `BuiltInInheritanceHelper.cj` recognizes built-in operator implementations in extends and synthesizes implicit operator
  members using the real AST factory/types.

De-isolation status: the implementation imports `cangjie_compiler::ast`, `cangjie_compiler::basic`, and
`cangjie_compiler::sema` directly. It does not define local compatibility copies of AST, Basic, Lex, diagnostics, or
TypeManager types.

Known remaining fidelity gaps are caused by sibling systems that are not yet represented in this self-hosting package:
full import-manager extend accessibility, native backend Java/ObjC inheritance annotation checks, full C++ diagnostic
note parity, and the C++ infinite-instantiation trigger stack. The implemented behavior is executable and participates
in the package build, but it is not yet wired into `TypeChecker::CheckInheritance` because that owner is outside this
pass's edit scope.

Verification: `cjpm build` passes for the whole workspace after this pass.
