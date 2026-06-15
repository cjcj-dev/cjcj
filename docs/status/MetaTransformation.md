# MetaTransformation Port Status

Date: 2026-06-16

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
- Added CHIR function/package/builder boundary interfaces and convenience abstract bases for CHIR
  function and package transforms. These provide a dependency boundary until the real CHIR package is
  ported and can implement the interfaces.
- Added `MakeCHIRPluginInfo`, the Cangjie equivalent of the C++ `CHIR_PLUGIN` macro expansion: it wraps
  a transform factory in a plugin-info registration callback that appends the produced transform to the
  CHIR plugin manager.

Known fidelity caveats:

- The C++ header names concrete `CHIR::CHIRBuilder`, `CHIR::Function`, and `CHIR::Package` types. The
  current self-hosting workspace still has only a CHIR scaffold, so this package exposes narrow CHIR
  boundary interfaces instead of importing concrete CHIR classes.
- Cangjie has no direct preprocessor macro equivalent for `CHIR_PLUGIN`; `MakeCHIRPluginInfo` preserves
  the registration behavior but not the C++ macro spelling.

Remaining MetaTransformation selfhost markers: 0.

