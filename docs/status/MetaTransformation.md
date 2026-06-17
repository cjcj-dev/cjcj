# MetaTransformation Port Status

Date: 2026-06-18

Build: `cjpm build` passes.

Implemented:

- Replaced the placeholder with a multi-file Cangjie package mirroring the C++ MetaTransformation split:
  `MetaTransform`, `MetaTransformPluginBuilder`, and `MetaTransformPluginManager`.
- Ported `MetaTransformKind`, `MetaTransformConcept`, CHIR kind predicates, the generic
  `MetaTransform` base, `MetaTransformPluginManager`, `CHIRPluginManager`, `MetaTransformPluginBuilder`,
  and `MetaTransformPluginInfo`.
- Modeled the C++ pure-virtual transform contract with a Cangjie interface-backed abstract base class,
  so concrete transforms must implement `Run`.
- Implemented CHIR plugin callback registration and manager construction in source order, matching the
  C++ builder behavior.
- De-isolated the CHIR boundary: `MetaTransformation` now imports the real sibling `chir` package and
  uses `CHIRBuilder`, `Function`, and `Package` directly instead of local compatibility interfaces.
- Matched the C++ enum-ordering surface more closely: `MetaTransformKind` has relational operators,
  formally implements `Comparable`, and `IsForCHIR` uses the same range comparison as the C++
  implementation. The ordinal helper is private implementation detail rather than public API.
- Narrowed the public `MetaTransformConcept` surface back toward the C++ declaration: transform kind
  remains protected state, and callers use the CHIR/function/package predicates rather than a non-C++
  public getter.
- Tightened construction to match the C++ ownership model: kind-setting constructors are protected, and
  the CHIR meta-kind marker is a value marker rather than a heap class.
- Ported the public `MetaKind` marker and the CHIR manager marker used by `CHIRPluginManager`; Cangjie
  keeps the nested `MetaKind::CHIR` shape flattened as `MetaKindCHIR`.
- Matched the C++ constructor sequence more closely: `MetaTransformConcept` now only default-constructs
  with `UNKNOWN`, and `MetaTransform` assigns the protected kind during its own construction.
- Exposed the public callback type aliases used by plugin registration and plugin-info registration, so
  the Cangjie API surface no longer hides public C++ callback signatures behind private aliases.
- Added `MakeCHIRPluginInfo`, the Cangjie equivalent of the C++ `CHIR_PLUGIN` macro expansion: it wraps
  a transform factory in a plugin-info registration callback that appends the produced transform to the
  CHIR plugin manager. The default overload reports the real `basic.CANGJIE_VERSION`, matching the C++
  macro's version source, while the explicit-version overload remains useful for tests. The helper is
  generic over the concrete transform subclass, so callers do not need to pre-widen plugin factories to
  `MetaTransformConcept` before registration.
- Exposed the C++ macro's getter-level contract in Cangjie: `META_TRANSFORM_PLUGIN_INFO_SYMBOL` records
  the exact `getMetaTransformPluginInfo` symbol spelling used by the C++ loader, and
  `MetaTransformPluginInfoGetter` plus CHIR getter helpers model the zero-argument function that returns
  plugin info.
- Added the raw native plugin-info ABI surface used by dynamically loaded plugins:
  `NativeMetaTransformPluginInfo` is an `@C` struct with the C++ fields (`const char*` version and
  registration function pointer), `NativeMetaTransformPluginBuilder` is the opaque `@C` type used behind
  the native builder reference, `NativeMetaTransformPluginInfoGetter` models the exported getter function
  pointer, and `GetNativeMetaTransformPluginInfo` casts a non-null native symbol pointer and invokes it
  under `unsafe`.
- Mirrored the C++ native plugin validity/registration path more closely: raw plugin info can now compare
  its `const char*` version against a requested compiler version with C `strcmp`, validate against
  `basic.CANGJIE_VERSION`, and invoke the native `registerTo` callback only after checking both the
  callback and native builder reference for null.
- Added typed CHIR transform factory aliases and function/package-specific plugin-info helpers. These
  preserve the C++ macro's type-specific construction path more closely for Cangjie plugins that derive
  from `CHIRFunctionMetaTransform` or `CHIRPackageMetaTransform`; the helpers are generic over the
  concrete transform subclass so plugin factories can return the actual plugin type like the C++ macro.
- Tightened `MetaTransformPluginInfo` nullability: the C++ `registerTo` function pointer can be absent
  and the C++ frontend validity check rejects that state, so the Cangjie port now stores it as
  `Option<MetaTransformRegisterCallback>`. Valid factory helpers still use the direct callback
  constructor, while invalid/no-callback plugin info can be represented explicitly.
- Tightened the plugin version side of the same ABI model: the C++ field is a raw `const char*`, so the
  self-hosted representation now stores `cjcVersion` as `Option<String>`. Valid plugin-info helpers still
  accept a plain `String`; malformed/no-version plugin info can be represented as `None` instead of an
  impossible empty-string sentinel.
- Added an explicit default invalid `MetaTransformPluginInfo` state with no version and no registration
  callback. This gives the self-hosted API a safe representation for the invalid/default plugin-info
  states that the C++ loader must reject before registration.
- Added plugin-info validation and registration helpers (`HasRegisterCallback`, `IsValidForVersion`,
  `HasVersion`, `VersionMatches`, `IsValid`, and `RegisterTo`) so the version/callback checks used by
  the C++ plugin loader are available in the self-hosted API without using null.
- Refined registration helper behavior: `RegisterTo` is now the required, void-style registration path
  and throws if plugin info has no callback, while `TryRegisterTo` preserves a checked boolean path for
  callers that validate malformed plugin info before invoking it. This better matches the C++ loader's
  non-optional callback invocation after plugin validation.
- Added `RunCHIRMetaTransforms`, a self-hosted equivalent of the C++ CHIR plugin execution loop in
  `ToCHIR::PerformPlugin`: it skips non-CHIR transform concepts, runs function transforms over every
  `Package.GetGlobalFuncsWithBody()` result, runs package transforms once, and throws on impossible
  kind/type mismatches instead of silently ignoring them. The result reports whether any CHIR plugin was
  seen plus function/package run counts so callers can mirror the C++ `hasPluginForCHIR` branch.
- Restored the C++ `MetaTransform<DeclT>` default-constructor behavior for CHIR transforms: the Cangjie
  base constructor now compares `TypeInfo.of<DeclT>()` against the real sibling CHIR `Function` and
  `Package` types, assigning `FOR_CHIR_FUNC`, `FOR_CHIR_PACKAGE`, or `UNKNOWN` like the C++ `if constexpr`
  chain. Direct subclasses of `MetaTransform<CHIRFunction>` and `MetaTransform<CHIRPackage>` no longer
  need to use the convenience wrapper classes to get the correct kind.
- Matched the C++ `MetaTransformPluginManager` move-only ownership surface more closely: the Cangjie
  manager now has a move-style constructor and `MoveAssignFrom` operation that transfer the transform
  sequence in order and clear the source manager, corresponding to the C++ move constructor and move
  assignment over `std::vector<std::unique_ptr<MetaTransformConcept>>`.

Known fidelity caveats:

- The C++ implementation performs compile-time type selection with `std::is_same_v`; the Cangjie port uses
  `std.reflect.TypeInfo` equality in the base constructor because Cangjie has no template-specialization
  equivalent. This keeps behavior faithful on the supported self-hosting target where `std.reflect` is
  available, but it is still not a source-level macro/template analogue.
- Cangjie has no direct preprocessor macro equivalent for `CHIR_PLUGIN`; `MakeCHIRPluginInfo` preserves
  the registration behavior but not the C++ macro spelling.
- Cangjie does not expose C++-style nested tag declarations in the style used by `MetaKind::CHIR`, so the
  CHIR tag is represented as `MetaKindCHIR` alongside the public `MetaKind` marker.
- Cangjie does not have C++ `unique_ptr`, so manager transfers move references between managers and clear
  the source rather than enforcing single ownership at the type-system level.
- Cross-module dynamic plugin loading is still not wired through the self-hosted frontend pipeline. This
  module now exposes and validates the raw `getMetaTransformPluginInfo` symbol type, but the caller-side
  loader still needs to provide a native builder reference or adapter before native C++ plugins can
  register directly.
- CHIR has not yet been updated to call `RunCHIRMetaTransforms`; this status file tracks only the scoped
  `packages/meta_transformation/src` port.

Remaining MetaTransformation selfhost markers: 0.
