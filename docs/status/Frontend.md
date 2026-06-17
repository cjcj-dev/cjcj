# Frontend Port Status

Date: 2026-06-17

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
package/import access-modifier header parsing, import-all normalization,
annotation/macro-call parsing for declarations,
function parameter/return type capture, generic parameter capture, simple
inherited-type and variable/type-alias target capture, top-level/member
declaration separation, observer dispatch, compile-stage ordering, numbered AST
dump directory creation, incremental summary collection, generic declaration
collection, deterministic CHIR summary generation, result/CJO summary writing,
cache-path handling, and CHIR-data bookkeeping.

This deepening pass added a real Frontend dependency on `cangjie_compiler::basic`
and removed Frontend-local copies of Basic `Position`, `Range`, `Source`, and
`SourceManager`. Diagnostics now use Basic's diagnostic engine for counting,
category grouping, and emission behind a thin Frontend adapter that preserves the
existing C++-shaped convenience calls. It also tightened several C++ reference
behaviors: comment tokens dump without comment text, empty-package detection now
honors package specs and non-compiler-added imports, AST cache calculation stops
on existing diagnostics or empty packages, test-only verbose mode lists source
files after macro expansion, and mangling now includes imported
`exportedInternalDecls` plus nominal imported generic instantiations.

This continuation added a real dependency on `cangjie_compiler::lex` and removed
the hand-written Frontend scanner. `FrontendLexer` now delegates to the real Lex
lexer, adapts tokens only at the current Frontend compatibility boundary, keeps
the real token kind names for `DumpTokens`, and feeds real lexer comments into
Basic `SourceManager.AddComments` when comment attachment is enabled. The parse
strategy now also propagates source-read failures back to
`FullCompileStrategy.Parse()` instead of losing them through a by-value Boolean.

## Important Blocker

`packages/frontend/cjpm.toml` now imports the real `basic` and `lex` packages. A
faithful production Frontend port must still import and wire the real `ast`,
`parse`, `conditional_compilation`, `modules`, `macro`, `sema`, `mangle`, `chir`,
and incremental-compilation packages. This pass keeps local compatibility models
for those still-unwired layers so the workspace can compile while Basic source,
diagnostic primitives, and Lex tokenization are no longer duplicated.

Remaining Frontend self-host markers: 0.

## Remaining Work

- Replace local compatibility AST/option/front-pipeline models with the real
  sibling package APIs and remove the remaining adapters once downstream APIs
  are wired.
- Wire the local conditional compilation, macro expansion, Sema desugar/typecheck,
  incremental AST cache/diff, generic instantiation, CHIR lowering, plugin FFI,
  and result serialization compatibility paths to the real implementations.
- Audit behavior against the C++ frontend tests after dependency wiring.
