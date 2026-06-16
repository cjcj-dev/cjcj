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

Continuation update:

- Instantiated-member checking now follows constructor references through their containing declaration, re-adds instance
  constructors and private members for instantiated collision checks, filters generic/non-function members out of the
  collision pool, and checks visible public or same-package generic extensions for instantiated nominal uses.
- C-struct type-argument checking now mirrors the C++ skip for enum-constructor member access, uses constructor outer
  declaration types for constructor references, and reports at the type-argument angle position when available.
- Extension inheritance checking now ports the exported-extension dependence diagnostic: an exported extension no longer
  silently satisfies an exported interface member with an implementation from a non-exported extension.
- Unimplemented-member reporting now includes the C++ static abstract member diagnostic for abstract classes and
  disambiguates duplicate unimplemented member notes with the member type.

Deepening update:

- Inheritance member visibility now uses the real modules package relation helper and applies the C++ public/protected/
  internal visibility table to real AST nodes, replacing the earlier same-package approximation.
- Common-part declarations now follow the C++ `NeedRecheck` rule: non-common declarations from the common part are
  rechecked only when they inherit/extend common declarations or an extended target has a specific implementation.
- Inherited interface type collection and extension collection are now stable-ordered. Extensions of the same target are
  filtered with the C++ parent/sub-interface ordering rule and report `sema_extend_check_sequence_cannot_decide` when
  cross-inherited extension ordering cannot be decided.
- Class/extend base-member lookup now switches to a base declaration's `specificImplementation` when present, matching
  the C++ common/specific implementation path.
- Local inheritance-only copies of generic substitution utilities were removed. Instantiated checking now calls the real
  `GenerateTypeMapping`, `TypeManager.GetTypeArgs`, and `MultiTypeSubstToTypeSubst` helpers from `cangjie_compiler::sema`.
- Instantiated generic member checking now keeps a trigger stack, reports ambiguous instantiated function diagnostics at
  the instantiation use site with the instantiated declaration text, pre-walks referenced generic nominal declarations,
  and diagnoses direct/cyclic generic infinite instantiation with the real substitution cycle helper.

Continuation deepening update:

- Generic override constraint diagnostics now mirror the C++ mapped-bound check more closely: parent constraints are
  instantiated before formatting, rendered in stable type order, and reported on the exact child generic constraint node
  when available instead of on the whole child declaration.
- Return-type inconsistency diagnostics now use stable quoted conflict-type text and exclude the child return type from
  the inherited conflict list when matching the C++ override failure note.
- Function override return checking now includes the C++ extension-relation invariance branch before falling back to
  subtype-incompatible diagnostics.
- Instantiated declaration walking now keeps a substitution stack like the C++ `institutionMaps`: nested instantiated
  type arguments are substituted through the active map, active maps participate in cyclic-substitution detection, and
  extend declarations build a combined map from the extended nominal type and the extension's own type arguments.
- Repeated instantiated generic member checks now replay cached `(parent, member)` diagnostic pairs for the same
  declaration/type-argument key, matching the C++ `genericMembersForInstantiatedDecl` path instead of silently returning.

De-isolation status: the implementation imports `cangjie_compiler::ast`, `cangjie_compiler::basic`, and
`cangjie_compiler::sema` directly. This pass also imports the real `cangjie_compiler::modules` package-relation helper.
It does not define local compatibility copies of AST, Basic, Lex, diagnostics, TypeManager, or generic substitution
types.

Known remaining fidelity gaps are caused by sibling systems that are not yet represented in this self-hosting package:
full import-manager extend accessibility, native backend Java/ObjC inheritance annotation checks, C++ extension ordering
generic substitution through extended generic type arguments for cross-extension ordering, full C++ diagnostic note/hint
parity, and complete C++ instantiated-type cache reuse for all member-signature substitutions. The implemented behavior
is executable and participates in the package build, but it is not yet wired into `TypeChecker::CheckInheritance` because
that owner is outside this pass's edit scope.

Verification: `cjpm build` passes for the whole workspace after this continuation deepening pass.
