# Frontend Port Status

Date: 2026-06-16

Build: `cjpm build` passes.

## Summary

Replaced the single Frontend scaffold with a multi-file Cangjie package mirroring
the C++ Frontend component split:

- `FrontendOptions.cj`
- `CompilerInvocation.cj`
- `CompilerInstance.cj`
- `CompileStrategy.cj`
- `FrontendObserver.cj`
- `MergeAnnoFromCjd.cj`
- `PrintSymbolTable.cj`
- `FrontendModel.cj`
- `SourceText.cj`

The package now contains real argument parsing for frontend actions, source
management, tokenization for `DumpTokens`, package/file/declaration bookkeeping,
module/package parsing from source files or cache buffers, package consistency
checks, `--cfg` and `--int-overflow` option handling, cfg-file loading with
quoted TOML string/comment semantics, common-part option ingestion,
conditional directive pruning, APILevel macro-declaration materialization,
dependency-scan JSON data with direct import dependencies, import search-path
indexing for CJD hints, symbol-table JSON output, APILevel custom annotation
merging from `.cj.d` packages with import-path fallback lookup,
annotation/macro-call parsing for declarations,
function parameter/return type capture, generic parameter capture, simple
inherited-type and variable/type-alias target capture, top-level/member
declaration separation, observer dispatch, compile-stage ordering, numbered AST
dump directory creation, incremental summary collection, generic declaration
collection, deterministic CHIR summary generation, result/CJO summary writing,
cache-path handling, and CHIR-data bookkeeping.

## Important Blocker

`packages/frontend/cjpm.toml` currently has no dependencies, and this task
forbids editing manifests. A faithful production Frontend port must import the
real `basic`, `parse`, `conditional_compilation`, `modules`, `macro`, `sema`,
`mangle`, `chir`, and incremental-compilation packages. This pass keeps a local
compatibility model so the workspace can still compile without manifest edits.
The remaining incompleteness is architectural rather than hidden behind
Frontend self-host marker comments.

Remaining Frontend self-host markers: 0.

## Remaining Work

- Replace local compatibility AST/source/diagnostic/option models with the real
  sibling package APIs once manifest changes are allowed.
- Wire the local conditional compilation, macro expansion, Sema desugar/typecheck,
  incremental AST cache/diff, generic instantiation, CHIR lowering, plugin FFI,
  and result serialization compatibility paths to the real implementations.
- Audit behavior against the C++ frontend tests after dependency wiring.
