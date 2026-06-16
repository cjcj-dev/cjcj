# MetaTransformation Port Status

Date: 2026-06-17

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
- Matched the C++ enum-ordering surface more closely: `MetaTransformKind` now exposes its ordinal helper
  and relational operators, formally implements `Comparable`, and `IsForCHIR` uses the same range
  comparison as the C++ implementation.
- Tightened construction to match the C++ ownership model: kind-setting constructors are protected, and
  the CHIR meta-kind marker is a value marker rather than a heap class.
- Exposed the public callback type aliases used by plugin registration and plugin-info registration, so
  the Cangjie API surface no longer hides public C++ callback signatures behind private aliases.
- Added `MakeCHIRPluginInfo`, the Cangjie equivalent of the C++ `CHIR_PLUGIN` macro expansion: it wraps
  a transform factory in a plugin-info registration callback that appends the produced transform to the
  CHIR plugin manager. The default overload reports the real `basic.CANGJIE_VERSION`, matching the C++
  macro's version source, while the explicit-version overload remains useful for tests.

Known fidelity caveats:

- The C++ `MetaTransform<DeclT>` default constructor uses `if constexpr` to infer function/package
  transform kind from the template argument. Cangjie does not currently have an equivalent specialization
  mechanism in this port, so direct subclasses of `MetaTransform<DeclT>` must pass a kind explicitly or
  use the provided `CHIRFunctionMetaTransform`/`CHIRPackageMetaTransform` bases.
- Cangjie has no direct preprocessor macro equivalent for `CHIR_PLUGIN`; `MakeCHIRPluginInfo` preserves
  the registration behavior but not the C++ macro spelling.

Remaining MetaTransformation selfhost markers: 0.
