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
- Instantiated declaration traversal now mirrors the C++ seen-key flow more closely: top-level declarations are cached
  with the empty type-argument key, generic upper-bound type nodes are marked with the active walker id to avoid recursive
  constraint walks, non-empty instantiations recursively walk the instantiated declaration when no visible extend already
  cached the key, and member-signature type substitution reuses a per-instantiation type cache.
- Infinite-instantiation detection now checks recursive type arguments after applying the active instantiation map and
  handles the C++ "triggered inside the same declaration" path using `Ty.GetGenericTyOfInsTy`.
- Extension ordering for generic extended types now instantiates the current extension's inherited interface types through
  the other extension's extended-type arguments before comparing sub/super interface relationships, matching the C++
  `GenerateTypeMappingByTy` path for generic same-target extensions.
- Inherited kind/type conflict diagnostics and return-type incompatibility diagnostics now prefer declaration identifier
  ranges where the C++ emits identifier-focused ranges, instead of always highlighting the full declaration.

De-isolation status: the implementation imports `cangjie_compiler::ast`, `cangjie_compiler::basic`, and
`cangjie_compiler::sema` directly. This pass also imports the real `cangjie_compiler::modules` package-relation helper.
It does not define local compatibility copies of AST, Basic, Lex, diagnostics, TypeManager, or generic substitution
types.

Known remaining fidelity gaps are caused by sibling systems that are not yet represented in this self-hosting package:
full import-manager extend accessibility, native backend Java/ObjC inheritance annotation checks, platform-specific
replacement of inherited interface type nodes through CJMP specific implementations during extension ordering, and full
C++ diagnostic note/hint parity. The implemented behavior is executable and participates in the package build, but it is
not yet wired into `TypeChecker::CheckInheritance` because that owner is outside this pass's edit scope.

Verification: `cjpm build` passes for the whole workspace after this continuation deepening pass.

Imported-extend and synthesis fidelity update:

- `StructInheritanceChecker.Check` now filters walked extensions through the package visibility relation before scheduling
  them, matching the C++ intent that invisible extensions are not checked as current-package visible members.
- Public imported extensions recorded in `TypeManager` are now pulled into the inheritance pass for conflict checking when
  they extend an imported public declaration or a built-in type and are not all from a single imported package. This mirrors
  the C++ native-backend `GetAllNeedCheckExtended` path using the self-hosted `TypeManager` maps available in this scope.
- Extension ordering across packages now keeps visible different-package extensions in the ordered set instead of dropping
  them solely because their defining package differs from the current extension package.
- Instantiated generic extension checks now use the same package-relation visibility helper as non-instantiated extension
  checking instead of the earlier same-package/public approximation.
- Synthesized built-in operator functions now include compiler-added return type nodes on their function bodies, preserving
  the C++ helper's observable AST shape for later passes that inspect `FuncBody.retType`.

De-isolation note: `cangjie_compiler::modules.IsVisible` was tested but is currently typed over the modules package's
compatibility `Node`, not the real `cangjie_compiler::ast.Node`, so this area still keeps the AST-typed local visibility
predicate while importing the real `GetPackageRelation` and `PackageRelation`.

Verification: `cjpm build` passes for the whole workspace after this imported-extend and synthesis fidelity update.

Diagnostic fidelity continuation:

- Named-parameter override mismatch diagnostics now mirror the C++ `DiagnoseParameterName` path more closely: the main
  diagnostic is reported on the child function identifier, mismatched parameters receive precise hints explaining named vs
  positional conflicts or the expected parent parameter name, and the parent function note points at the parent identifier.
- Weak-visibility override diagnostics now use the C++ visibility text and structured notes: inherited implementations get
  a main hint that the deriving member is inherited, child notes point to the actual deriving declaration and visibility,
  and parent notes report the base declaration visibility with an interface hint when applicable. Macro-call note forwarding
  is also wired through the available self-hosted `DiagnosticEngine.AddMacroCallNote` surface.

Verification: `cjpm build` passes for the whole workspace after this diagnostic fidelity continuation.

Ordered-diagnostic continuation:

- Conflict-inheritance diagnostics now build declaration notes through a source-position ordered declaration set, matching
  the C++ `OrderedDeclSet` behavior instead of preserving member-map insertion order.
- Unimplemented abstract/interface member notes are now emitted in the C++ stable order: declaration position first, then
  type-name ordering for duplicate declarations.
- Instantiated generic ambiguity diagnostics now order candidate notes through the same inheritance declaration ordering
  helper and report candidate notes on declaration identifiers when available, matching the C++ candidate-note shape more
  closely.

Verification: `cjpm build` passes for the whole workspace after this ordered-diagnostic continuation.

Incomplete extension implementation continuation:

- Inherited-interface checking now ports the native-backend C++ `CheckIncompleteOverrideOrImplOfExtend` core path. When an
  interface function is satisfied by a member from an extension of a generic class, the checker instantiates the extended
  class through the current class's generic mapping and verifies that the extension constraints still hold.
- The new check preserves the C++ escape cases for implementations that belong to the declaration currently being checked
  or one of its own extensions, and diagnoses either a default-interface override conflict or a potentially invisible
  interface implementation with the same note wording used by the C++ implementation.
- The CJMP `commonPartCjos`-controlled inherited-type replacement remains a known gap because this scoped checker does
  not receive global options and the replacement helper lives outside the permitted edit area.

Verification: `cjpm build` passes for the whole workspace after this incomplete extension implementation continuation.
