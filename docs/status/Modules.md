# Modules Port Status

Date: 2026-06-16

Build: `cjpm build` passes.

## Summary

The Modules package has been expanded from a single scaffold into a multi-file Cangjie package mirroring the C++ Modules layout. It now contains public module-local models for packages, files, imports, declarations, package declarations, access levels, diagnostics, CJO manager state, AST serialization wrappers, dependency graphs, and package dependency ordering.

This pass keeps the package self-contained because `packages/modules/cjpm.toml` currently declares no dependencies and the task disallows manifest edits. As a result, the package cannot yet import the real `ast`, `basic`, `option`, `sema`, or flatbuffers-facing APIs used by the C++ implementation.

## Implemented

- Replaced `ModulesScaffold.cj` with per-component source files under `packages/modules/src`.
- Ported package/import name handling, including `::` organization names, `.cjo` file naming, test package suffix handling, access-level comparison, package relation classification, super-package checks, import-kind behavior, and visibility filtering.
- Added module-local equivalents for `Package`, `File`, `Decl`, `PackageDecl`, `ImportSpec`, `ImportContent`, `ExternalLibCfg`, `DepType`, `ExportConfig`, diagnostics, and global options needed by the ported logic.
- Implemented `CjoManager` state for source/imported package registration, package/member maps, implicit members, CJO path cache, CJO data cache, macro-only package marking, search path updates, package declaration lookup, re-export member map construction, and on-demand loader traversal.
- Implemented `ImportManager` behavior for implicit imports, import header resolution, CJO path recording, standard-library dependency classification, source package import indexing, imported declaration lookup, imported-declaration provenance queries, source-imported package retention after indexing, macro-used declaration tracking, direct dependency collection, macro package collection, reindexing after macro expansion, package accessibility checks, local declaration shadowing checks for useless imports, package feature consistency validation, duplicate import warnings, dependency JSON generation with per-import source ranges and standard-library dependency entries, BCHIR/CJO cache plumbing, and package loading from CJO.
- Implemented `DependencyGraph` direct/transitive dependency collection with macro re-export handling and cache invalidation.
- Implemented `PackageManager` Tarjan SCC ordering and source package reordering behavior.
- Added a compiling local AST writer/loader wire format so exported package/import/member data can round-trip inside this package while the real flatbuffer/AST dependencies are unavailable.
- Continued the local serialization layer with type interning, cached declaration diffing, import reference loading, expression table serialization/deserialization, reference resolution maps, incremental removed-mangle parsing, node source-range/attribute preservation, and package file ownership normalization.

## Important Blockers

- Real C++ parity requires dependencies on AST, Basic, Option, Sema/TypeManager, and flatbuffers/native CJO format support. Those cannot be wired without editing manifests or porting additional dependency surfaces.
- The local serialization format is not the production `.cjo` flatbuffer format. It is a compiling, behavior-bearing bridge for the isolated package, not a faithful replacement for C++ AST serialization.
- Type/reference/expression/incremental deserialization has package-local working logic, but it still cannot consume the production C++ flatbuffer schema until real AST/Sema dependencies are available.

## Remaining Work

- Replace module-local AST/Basic/Option compatibility models with the real packages once manifest/dependency edits are allowed.
- Bind the real flatbuffer module format and implement full `ASTWriter`, `ASTLoader`, expression writer/loader, reference loader, CJMP common-part loading, and incremental cache loading.
- Wire diagnostics to the real `DiagnosticEngine` and diagnostic IDs from the Basic module.
- Audit import/package lookup behavior against the C++ test corpus after downstream Sema/Frontend callers are available.

Remaining Modules selfhost markers: 0.
