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

Known fidelity caveats:

- The C++ `MetaTransform<DeclT>` default constructor uses `if constexpr` to infer function/package
  transform kind from the template argument. Cangjie does not currently have an equivalent specialization
  mechanism in this port, so direct subclasses of `MetaTransform<DeclT>` must pass a kind explicitly.
  Plugins should use `CHIRFunctionMetaTransform`/`CHIRPackageMetaTransform` and the typed plugin-info
  helpers when they need the C++ macro's CHIR function/package behavior.
- A constructor-time runtime type check was tested as a possible workaround for the generic kind
  inference gap, but cjc rejects use of `this` as an expression inside abstract-class constructors.
- Cangjie has no direct preprocessor macro equivalent for `CHIR_PLUGIN`; `MakeCHIRPluginInfo` preserves
  the registration behavior but not the C++ macro spelling.
- Cangjie does not expose C++-style nested tag declarations in the style used by `MetaKind::CHIR`, so the
  CHIR tag is represented as `MetaKindCHIR` alongside the public `MetaKind` marker.
- Cross-module dynamic plugin loading is still not wired through the self-hosted frontend pipeline, and
  CHIR has not yet been updated to call `RunCHIRMetaTransforms`; this status file tracks only the scoped
  `packages/meta_transformation/src` port.

Remaining MetaTransformation selfhost markers: 0.
