# Modules Port Status

Date: 2026-06-16

Build: `cjpm build` passes.

## Summary

The Modules package has been expanded from a single scaffold into a multi-file Cangjie package mirroring the C++ Modules layout. It now contains public module-local models for packages, files, imports, declarations, package declarations, access levels, diagnostics, CJO manager state, AST serialization wrappers, dependency graphs, and package dependency ordering.

This pass de-isolated compiler options: `packages/modules` now depends on the real `cangjie_compiler::option` package and uses its `GlobalOptions`, `OutputMode`, and `OptimizationLevel` rather than local compatibility copies. The package still carries local AST/Basic/diagnostic models because the real AST import representation (`Identifier`, `Modifier`, `AttributePack`, typed decl subclasses) does not yet match the simplified Modules call sites without a broader conversion pass.

## Implemented

- Replaced `ModulesScaffold.cj` with per-component source files under `packages/modules/src`.
- Ported package/import name handling, including `::` organization names, `.cjo` file naming, test package suffix handling, access-level comparison, package relation classification, super-package checks, import-kind behavior, and visibility filtering.
- Added module-local equivalents for `Package`, `File`, `Decl`, `PackageDecl`, `ImportSpec`, `ImportContent`, `ExternalLibCfg`, `DepType`, `ExportConfig`, and diagnostics needed by the ported logic.
- Replaced the module-local `GlobalOptions`, `OutputMode`, `OptimizationLevel`, and option environment copies with imports from `cangjie_compiler::option`; option serialization now preserves `Os` and `Oz`.
- Implemented `CjoManager` state for source/imported package registration, package/member maps, implicit members, CJO path cache, CJO data cache, macro-only package marking, search path updates, package declaration lookup, re-export member map construction, on-demand loader traversal with common-part loader participation, and resolved re-export dependency checks.
- Matched the C++ `GetPackageCjo` in-group source package rule: a registered source package candidate now outranks a less-specific on-disk ancestor CJO, and in-memory cached CJO data now returns the cached CJO name path just like the C++ helper.
- Matched additional CJO manager lifecycle behavior: common-part reloads now remove previously loaded `FROM_COMMON_PART` files before appending fresh common files, `DeleteASTLoaders` clears loader handles, rebuild-index clearing clears package loaders while preserving common-part loader/cache state, and silent CJO read failures return an empty loader like the C++ helper.
- Implemented `ImportManager` behavior for implicit imports, import header resolution, CJO path recording, standard-library dependency classification, source package import indexing, imported declaration lookup, imported-declaration provenance queries, source-imported package retention after indexing, macro-used declaration tracking, direct dependency collection using the same CJO lookup-name form as the C++ reference, macro package collection, reindexing after macro expansion, package accessibility checks with source ranges, local declaration shadowing checks for useless imports, package feature consistency validation, duplicate import warnings, dependency JSON generation with per-import source ranges and standard-library dependency entries, BCHIR/CJO cache plumbing, and package loading from CJO.
- Implemented `DependencyGraph` direct/transitive dependency collection with macro re-export handling and cache invalidation.
- Implemented `PackageManager` Tarjan SCC ordering and source package reordering behavior.
- Added a compiling local AST writer/loader wire format so exported package/import/member data can round-trip inside this package while the real flatbuffer/AST dependencies are unavailable.
- Continued the local serialization layer with type interning, cached declaration diffing, resolved dependency-name extraction, import reference loading, expression table serialization/deserialization, reference resolution maps, incremental removed-mangle parsing, node source-range/attribute preservation, and package file ownership normalization.
- Added local-format CJMP common-part validation matching the C++ loader control flow for package-name mismatch, common/specific feature-set subset diagnostics, serialized debug/optimization option checks, and option-mismatch aborts before later compilation stages.

## Important Blockers

- Real C++ parity still requires dependencies on AST, Basic diagnostics/source manager, Sema/TypeManager, and flatbuffers/native CJO format support. Option is now wired to the real package.
- The local serialization format is not the production `.cjo` flatbuffer format. It is a compiling, behavior-bearing bridge for the isolated package, not a faithful replacement for C++ AST serialization.
- Type/reference/expression/incremental deserialization has package-local working logic, but it still cannot consume the production C++ flatbuffer schema until real AST/Sema dependencies are available.

## Remaining Work

- Replace module-local AST/Basic compatibility models with the real packages and adapt Modules call sites to AST `Identifier`, `Modifier`, `AttributePack`, and typed declaration subclasses.
- Bind the real flatbuffer module format and implement full `ASTWriter`, `ASTLoader`, expression writer/loader, reference loader, production CJMP common-part loading, and incremental cache loading.
- Wire diagnostics to the real `DiagnosticEngine` and diagnostic IDs from the Basic module.
- Audit import/package lookup behavior against the C++ test corpus after downstream Sema/Frontend callers are available.

Remaining Modules selfhost markers: 0.
