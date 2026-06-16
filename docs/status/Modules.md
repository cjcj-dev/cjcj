# Modules Port Status

Date: 2026-06-17

Build: `cjpm build` passes.

## Summary

The Modules package has been expanded from a single scaffold into a multi-file Cangjie package mirroring the C++ Modules layout. It now contains public module-local models for packages, files, imports, declarations, package declarations, access levels, diagnostics, CJO manager state, AST serialization wrappers, dependency graphs, and package dependency ordering.

This pass de-isolated compiler options, Basic source locations, and the first layer of Modules diagnostics: `packages/modules` now depends on the real `cangjie_compiler::option` and `cangjie_compiler::basic` packages, uses real `GlobalOptions`, `OutputMode`, `OptimizationLevel`, `Position`, `Range`, delegates `MakeRange` to Basic, and forwards recognized module/import diagnostic IDs into a real Basic `DiagnosticEngine` while preserving the current module-local diagnostic record for compatibility. The package still carries local AST models because the real AST import representation (`Identifier`, `Modifier`, `AttributePack`, typed decl subclasses) does not yet match the simplified Modules call sites without a broader conversion pass.

This deepening pass moved qualified-name splitting onto the real Basic helper while preserving the Modules `ArrayList` API, matched `Decl.IsExportedDecl` with the AST/C++ internal `noSubPkg` rule, and made the local AST serialization bridge round-trip `exportedInternalDecls` while skipping `doNotExport` declarations like the C++ writer.

## Implemented

- Replaced `ModulesScaffold.cj` with per-component source files under `packages/modules/src`.
- Ported package/import name handling, including `::` organization names, `.cjo` file naming, test package suffix handling, access-level comparison, package relation classification, super-package checks, import-kind behavior, and visibility filtering.
- Added module-local equivalents for `Package`, `File`, `Decl`, `PackageDecl`, `ImportSpec`, `ImportContent`, `ExternalLibCfg`, `DepType`, `ExportConfig`, and diagnostics needed by the ported logic.
- Replaced the module-local `GlobalOptions`, `OutputMode`, `OptimizationLevel`, and option environment copies with imports from `cangjie_compiler::option`; option serialization now preserves `Os` and `Oz`.
- Replaced module-local `Position`/`Range` compatibility structs with public aliases to `cangjie_compiler::basic` and delegated range construction to Basic `MakeRange`.
- Replaced the module-local qualified-name splitting algorithm with a wrapper around `cangjie_compiler::basic.SplitQualifiedName`, keeping the existing Modules return type for callers.
- Added a Basic diagnostic bridge for Modules diagnostics: the compatibility `DiagnosticEngine` now wraps a real `cangjie_compiler::basic.DiagnosticEngine`, exposes it for downstream integration, resets it with local diagnostics, and forwards recognized module/import diagnostic kind strings to real `DiagKindRefactor` IDs.
- Implemented `CjoManager` state for source/imported package registration, package/member maps, implicit members, CJO path cache, CJO data cache, macro-only package marking, search path updates, package declaration lookup, re-export member map construction, on-demand loader traversal with common-part loader participation, and resolved re-export dependency checks.
- Matched the C++ `GetPackageCjo` in-group source package rule: a registered source package candidate now outranks a less-specific on-disk ancestor CJO, and in-memory cached CJO data now returns the cached CJO name path just like the C++ helper.
- Matched additional CJO manager lifecycle behavior: common-part reloads now remove previously loaded `FROM_COMMON_PART` files before appending fresh common files, `DeleteASTLoaders` clears loader handles, rebuild-index clearing clears package loaders while preserving common-part loader/cache state, and silent CJO read failures return an empty loader like the C++ helper.
- Matched additional CJO manager loader behavior: common-part loader lookup now reports a missing common-part path for CJMP-specific compilation, uses normal read diagnostics for configured common CJO paths, and propagates the manager `importSrcCode` flag to every created AST loader.
- Implemented `ImportManager` behavior for implicit imports, import header resolution, CJO path recording, standard-library dependency classification, source package import indexing, imported declaration lookup, imported-declaration provenance queries, source-imported package retention after indexing, macro-used declaration tracking, direct dependency collection using the same CJO lookup-name form as the C++ reference, macro package collection, reindexing after macro expansion, package accessibility checks with source ranges, local declaration shadowing checks for useless imports, package feature consistency validation, duplicate import warnings, dependency JSON generation with per-import source ranges and standard-library dependency entries, BCHIR/CJO cache plumbing, and package loading from CJO.
- Implemented `DependencyGraph` direct/transitive dependency collection with macro re-export handling and cache invalidation.
- Implemented `PackageManager` Tarjan SCC ordering and source package reordering behavior.
- Added a compiling local AST writer/loader wire format so exported package/import/member data can round-trip inside this package while the real flatbuffer/AST dependencies are unavailable.
- Improved that local AST writer/loader bridge to preserve `exportedInternalDecls` records, reload them into `File.exportedInternalDecls`, and suppress `doNotExport` declarations during serialization in line with the C++ writer's export filtering.
- Continued the local serialization layer with type interning, cached declaration diffing, resolved dependency-name extraction, import reference loading, expression table serialization/deserialization, reference resolution maps, incremental removed-mangle parsing, node source-range/attribute preservation, and package file ownership normalization.
- Added local-format CJMP common-part validation matching the C++ loader control flow for package-name mismatch, common/specific feature-set subset diagnostics, serialized debug/optimization option checks, and option-mismatch aborts before later compilation stages.

## Important Blockers

- Real C++ parity still requires dependencies on AST, full Basic diagnostic builder/source-manager call-site conversion, Sema/TypeManager, and flatbuffers/native CJO format support. Option, Basic source location types, and a first diagnostic forwarding bridge are now wired to the real packages.
- The local serialization format is not the production `.cjo` flatbuffer format. It is a compiling, behavior-bearing bridge for the isolated package, not a faithful replacement for C++ AST serialization.
- Type/reference/expression/incremental deserialization has package-local working logic, but it still cannot consume the production C++ flatbuffer schema until real AST/Sema dependencies are available.

## Remaining Work

- Replace module-local AST/Basic compatibility models with the real packages and adapt Modules call sites to AST `Identifier`, `Modifier`, `AttributePack`, and typed declaration subclasses.
- Bind the real flatbuffer module format and implement full `ASTWriter`, `ASTLoader`, expression writer/loader, reference loader, production CJMP common-part loading, and incremental cache loading.
- Replace remaining free-form compatibility diagnostics with exact Basic diagnostic builder calls and C++ note/hint structure.
- Audit import/package lookup behavior against the C++ test corpus after downstream Sema/Frontend callers are available.

Remaining Modules selfhost markers: 0.
