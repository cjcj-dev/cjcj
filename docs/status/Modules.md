# Modules Port Status

Date: 2026-06-18

Build: `cjpm build` passes.

## Summary

The Modules package has been expanded from a single scaffold into a multi-file Cangjie package mirroring the C++ Modules layout. It now contains public module-local models for packages, files, imports, declarations, package declarations, access levels, diagnostics, CJO manager state, AST serialization wrappers, dependency graphs, and package dependency ordering.

This pass de-isolated compiler options, Basic source locations, and the first layer of Modules diagnostics: `packages/modules` now depends on the real `cangjie_compiler::option` and `cangjie_compiler::basic` packages, uses real `GlobalOptions`, `OutputMode`, `OptimizationLevel`, `Position`, `Range`, delegates `MakeRange` to Basic, and forwards recognized module/import diagnostic IDs into a real Basic `DiagnosticEngine` while preserving the current module-local diagnostic record for compatibility. The package still carries local AST models because the real AST import representation (`Identifier`, `Modifier`, `AttributePack`, typed decl subclasses) does not yet match the simplified Modules call sites without a broader conversion pass.

This deepening pass moved qualified-name splitting onto the real Basic helper while preserving the Modules `ArrayList` API, matched `Decl.IsExportedDecl` with the AST/C++ internal `noSubPkg` rule, and made the local AST serialization bridge round-trip `exportedInternalDecls` while skipping `doNotExport` declarations like the C++ writer.

This continuation aligned more `ImportManager`/`CjoManager` behavior with C++: `ExportDeclsWithContent` now caches a pre-saved writer for later `ExportAST` reuse, `DeleteASTWriters` clears that cache, standard-library dependency JSON now recursively records each std package's imported packages instead of emitting empty arrays, and `CjoManagerImpl.UpdateSearchPath` always appends the `cangjieModules` path entry like the reference implementation.

This pass filled another import-resolution edge case from the C++ `HandleAlreadyParsedPackage` path: when an imported package resolves to an already-loaded source package while the current package was imported, Modules now reports `module_same_name_with_indirect_dependent_pkg` and fails that import resolution instead of silently accepting the collision. The diagnostic bridge now forwards that module diagnostic to Basic. The public `SetImportedPackageFromASTNode` API was also added and delegates to `CjoManager.AddImportedPackageFromASTNode`, matching the C++ ImportManager surface within the local ownership model.

This pass de-isolated CJO filename/path utilities to the real `cangjie_compiler::utils.FileUtil`: `ToCjoFileName`, `ToPackageName`, and `CjoManager` CJO discovery now use the same shared utility behavior as the C++ implementation, including nested module-directory lookup before direct-path fallback and the C++ cache-hit return value for `GetPackageCjoPath`.

This pass tightened two state-management details against the C++ reference: changing `ImportManager.SetSourceCodeImportStatus` now also updates the CJO manager state used by future AST loaders, matching the C++ shared `importSrcCode` reference, and dependency CJO/CJD path recording now preserves the first recorded path and derives `.cj.d` sidecar paths with the same substring rule as `SaveDepPkgCjoPath`.

This pass de-isolated standard-library package recognition and shared package constants to `cangjie_compiler::utils`, added the C++ package-name re-export import diagnostic path, made local text serialization deterministic for expression attributes and incremental removed mangles, and expanded reference indexing to include package declarations plus exported-internal declarations.

This continuation tightened import-indexing and LSP/macros behavior against the C++ reference: alias provenance is now recorded for wildcard imports and full explicit-import candidate sets, `LoadPackageFromCjo` recursively loads dependency headers before on-demand declaration loading, macro debug file replacement clones implicit import nodes instead of sharing them, and dependency JSON escaping now emits `\u00XX` for all control bytes like the C++ `Jsonfy` helper.

This pass aligned additional CJO manager details with the C++ implementation: tool-added packages registered through `AddImportedPackageFromASTNode` are no longer marked as normal imported CJO packages, CJO read failures now use the `module_read_file_to_buffer_failed` diagnostic kind and Basic forwarding, and standard-library dependency recording now requires an existing CJO path like the reference `HandleStdPackage` path.

This pass aligned dependency graph and package-order dependency collection with the C++ assumption that imports are already resolved before these phases run: unresolved imports are now skipped instead of re-running CJO lookup during graph construction or Tarjan dependency collection, and `GetAllDependencyPackageNames` uses the same full-package-name cache key shape as the C++ implementation.

This pass tightened import validation and diagnostics against the C++ reference: named declaration imports now check member existence using package visibility only, with import access level reserved for imported-declaration map insertion, import-all short-circuits before package-name import checks, and warning diagnostics now retain the secondary note locations for shadowed imports, conflicting imports, and repeated feature names.

This pass tightened package-order and import-node fidelity: `PackageManager` now uses a single monotonically increasing Tarjan discovery index like the C++ implementation, recursive standard-library dependency handling records CJO/CJD sidecar paths before classifying the dependency, and local import nodes now render C++-style alias and multi-import strings through `ToString`. The local `Package.IsEmpty` helper now follows the C++ AST rule that a package with only compiler-added imports and no declarations is empty.

This pass de-isolated the first AST enum layer used by Modules: `AccessLevel`, `Attribute`, and `ImportKind` now alias the real `cangjie_compiler::ast` definitions instead of local compatibility enums. Attribute wire conversion now accepts the full real AST attribute name set, preserves the existing legacy `MACRO_EXPAND_DECL` spelling by mapping it to `MACRO_EXPANDED_NODE`, and Modules call sites use local comparison helpers because imported enum equality operators are not exported across the package alias boundary.

This continuation de-isolated the package declaration spec used by Modules files to the real `cangjie_compiler::ast.PackageSpec`, preserved it through the local AST serialization bridge, and restored the C++ `CheckPackageSpecsIdentical` build-index validation for root-package visibility and cross-file package-name/access consistency. The new path uses real Lex `TokenKind` data from AST modifiers while keeping a compatibility fallback for package-level data until all callers populate real package specs.

## Implemented

- Replaced `ModulesScaffold.cj` with per-component source files under `packages/modules/src`.
- Ported package/import name handling, including `::` organization names, `.cjo` file naming, test package suffix handling, access-level comparison, package relation classification, super-package checks, import-kind behavior, and visibility filtering.
- Added module-local equivalents for `Package`, `File`, `Decl`, `PackageDecl`, `ImportSpec`, `ImportContent`, `ExternalLibCfg`, `DepType`, `ExportConfig`, and diagnostics needed by the ported logic.
- Replaced the module-local `AccessLevel`, `Attribute`, and `ImportKind` compatibility enums with aliases to the real `cangjie_compiler::ast` enums and added Modules-local comparison helpers for those imported enum values.
- Added a real `cangjie_compiler::ast.PackageSpec` slot to the local `File` model and preserved it in the local serializer/loader bridge.
- Expanded attribute serialization/deserialization to the full real AST attribute set, including compatibility handling for the old Modules-only `MACRO_EXPAND_DECL` spelling.
- Replaced the module-local `GlobalOptions`, `OutputMode`, `OptimizationLevel`, and option environment copies with imports from `cangjie_compiler::option`; option serialization now preserves `Os` and `Oz`.
- Replaced module-local `Position`/`Range` compatibility structs with public aliases to `cangjie_compiler::basic` and delegated range construction to Basic `MakeRange`.
- Replaced the module-local qualified-name splitting algorithm with a wrapper around `cangjie_compiler::basic.SplitQualifiedName`, keeping the existing Modules return type for callers.
- Added a Basic diagnostic bridge for Modules diagnostics: the compatibility `DiagnosticEngine` now wraps a real `cangjie_compiler::basic.DiagnosticEngine`, exposes it for downstream integration, resets it with local diagnostics, and forwards recognized module/import diagnostic kind strings to real `DiagKindRefactor` IDs.
- Preserved C++-style diagnostic note locations for shadowed imports, conflicting imports, and repeated package feature names in the local diagnostic stream.
- Implemented `CjoManager` state for source/imported package registration, package/member maps, implicit members, CJO path cache, CJO data cache, macro-only package marking, search path updates, package declaration lookup, re-export member map construction, on-demand loader traversal with common-part loader participation, and resolved re-export dependency checks.
- Matched the C++ `GetPackageCjo` in-group source package rule: a registered source package candidate now outranks a less-specific on-disk ancestor CJO, and in-memory cached CJO data now returns the cached CJO name path just like the C++ helper.
- Matched additional CJO manager lifecycle behavior: common-part reloads now remove previously loaded `FROM_COMMON_PART` files before appending fresh common files, `DeleteASTLoaders` clears loader handles, rebuild-index clearing clears package loaders while preserving common-part loader/cache state, and silent CJO read failures return an empty loader like the C++ helper.
- Matched additional CJO manager loader behavior: common-part loader lookup now reports a missing common-part path for CJMP-specific compilation, uses normal read diagnostics for configured common CJO paths, and propagates the manager `importSrcCode` flag to every created AST loader.
- Matched more CJO manager state and diagnostics: AST-node-provided packages are marked `TOOL_ADD` without the normal `IMPORTED` attribute, CJO read failures report `module_read_file_to_buffer_failed`, and that diagnostic now forwards to Basic.
- Implemented `ImportManager` behavior for implicit imports, import header resolution, CJO path recording, standard-library dependency classification, source package import indexing, imported declaration lookup, imported-declaration provenance queries, source-imported package retention after indexing, macro-used declaration tracking, direct dependency collection using the same CJO lookup-name form as the C++ reference, macro package collection, reindexing after macro expansion, package accessibility checks with source ranges, local declaration shadowing checks for useless imports, package feature consistency validation, duplicate import warnings, dependency JSON generation with per-import source ranges and standard-library dependency entries, BCHIR/CJO cache plumbing, and package loading from CJO.
- Matched the C++ AST writer lifecycle more closely: content export pre-save now stores a writer per package, later AST export reuses that writer, and writer deletion clears the cache.
- Matched the C++ standard-library dependency JSON shape more closely by recursively loading std package headers and recording each std package's import set.
- Added the C++ already-parsed package collision behavior for source packages that shadow indirect dependencies, plus the corresponding Basic diagnostic forwarding.
- Added `ImportManager.SetImportedPackageFromASTNode` to register tool-provided package AST nodes through the CJO manager.
- Added a real dependency on `cangjie_compiler::utils` for Modules CJO filename conversion and serialization-file discovery, replacing local ad hoc lookup with `FileUtil.FindSerializationFile`.
- Replaced the module-local standard-library name list and duplicated core/sync/ast/default package constants with the real `cangjie_compiler::utils` standard-library map and exported package constants.
- Matched `ImportManager` source-code import status propagation into `CjoManagerImpl` so newly created AST loaders observe LSP/source-import toggles.
- Matched C++ dependency path bookkeeping for first-write CJO path storage and unconditional `.cj.d` sidecar derivation.
- Matched C++ standard-library dependency filtering by recording std CJO paths only when the resolved path exists.
- Matched the C++ package-name re-export import check by reporting `package_re_export_package_name` for re-exported package imports and forwarding that diagnostic to Basic.
- Matched C++ named import validation by filtering declaration existence with `IsVisible` only, rather than also applying the import access modifier during `CheckImports`.
- Matched the C++ `CheckImports` branch order by skipping import-all declarations before package-name import diagnostics.
- Matched more C++ imported-declaration alias provenance: wildcard imports now remember declaration identifiers that differ from the imported map key, and explicit alias/single imports record aliases from the full candidate member set before visibility filtering.
- Matched the C++ `LoadPackageFromCjo` LSP path by recursively loading dependent package headers before loading declarations and references on demand.
- Matched the C++ macro-debug file replacement path by cloning compiler-added implicit import nodes into the replacement file rather than reusing mutable import nodes from the old file.
- Implemented `DependencyGraph` direct/transitive dependency collection with macro re-export handling and cache invalidation.
- Matched C++ dependency graph traversal by using the resolved `GetPackageNameByImport` mapping directly during graph construction and skipping unresolved imports instead of invoking CJO lookup again.
- Matched the C++ dependency-name cache keying for `DependencyGraph.GetAllDependencyPackageNames`.
- Implemented `PackageManager` Tarjan SCC ordering and source package reordering behavior.
- Matched C++ package-manager dependency collection by using resolved package names only, preventing package-order analysis from mutating import resolution state.
- Matched the C++ Tarjan traversal more closely by keeping the DFS discovery counter in traversal state instead of recomputing recursive indices from the number of visited packages.
- Matched C++ recursive standard-library dependency path bookkeeping by recording dependent std package CJO and `.cj.d` paths before adding them to direct/indirect std dependency sets.
- Matched C++ import-node string behavior for alias imports, import-all spelling, explicit import modifiers, and multi-import formatting in the local compatibility AST.
- Added `Package.IsEmpty` behavior for the local package model, returning true only when files contain no declarations and only compiler-added imports.
- Restored C++ package declaration consistency checks during `BuildIndex`, including root-package public-visibility diagnostics and duplicate package-name/access detection across files.
- Added a compiling local AST writer/loader wire format so exported package/import/member data can round-trip inside this package while the real flatbuffer/AST dependencies are unavailable.
- Improved that local AST writer/loader bridge to preserve `exportedInternalDecls` records, reload them into `File.exportedInternalDecls`, and suppress `doNotExport` declarations during serialization in line with the C++ writer's export filtering.
- Continued the local serialization layer with type interning, cached declaration diffing, resolved dependency-name extraction, import reference loading, deterministic expression table serialization/deserialization, reference resolution maps, deterministic incremental removed-mangle serialization/parsing, C++-style JSON control-byte escaping, node source-range/attribute preservation, and package file ownership normalization.
- Extended reference indexing to register package declarations and `exportedInternalDecls`, matching the declarations the writer can now preserve.
- Added local-format CJMP common-part validation matching the C++ loader control flow for package-name mismatch, common/specific feature-set subset diagnostics, serialized debug/optimization option checks, and option-mismatch aborts before later compilation stages.

## Important Blockers

- Real C++ parity still requires full AST node/declaration integration, full Basic diagnostic builder/source-manager call-site conversion, Sema/TypeManager, and flatbuffers/native CJO format support. Option, Basic source location types, Utils package constants/stdlib lookup, AST access/import/attribute/package-spec types, and a first diagnostic forwarding bridge are now wired to the real packages.
- The local serialization format is not the production `.cjo` flatbuffer format. It is a compiling, behavior-bearing bridge for the isolated package, not a faithful replacement for C++ AST serialization.
- Type/reference/expression/incremental deserialization has package-local working logic, but it still cannot consume the production C++ flatbuffer schema until real AST/Sema dependencies are available.

## Remaining Work

- Replace the remaining module-local AST/Basic compatibility models with the real packages and adapt Modules call sites to AST `Identifier`, `Modifier`, `AttributePack`, and typed declaration subclasses.
- Bind the real flatbuffer module format and implement full `ASTWriter`, `ASTLoader`, expression writer/loader, reference loader, production CJMP common-part loading, and incremental cache loading.
- Replace remaining free-form compatibility diagnostics with exact Basic diagnostic builder calls and C++ note/hint structure.
- Audit import/package lookup behavior against the C++ test corpus after downstream Sema/Frontend callers are available.

Remaining Modules selfhost markers: 0.
