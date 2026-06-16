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
checks, dependency-scan JSON data, symbol-table JSON output, APILevel custom
annotation merging from `.cj.d` packages, observer dispatch, compile-stage
ordering, dump AST rendering, cache-path handling, and CHIR-data bookkeeping.

## Important Blocker

`packages/frontend/cjpm.toml` currently has no dependencies, and this task
forbids editing manifests. A faithful production Frontend port must import the
real `basic`, `parse`, `conditional_compilation`, `modules`, `macro`, `sema`,
`mangle`, `chir`, and incremental-compilation packages. This pass keeps a local
compatibility model so the workspace can still compile, but the stage delegates
that require sibling packages remain explicitly marked with
`TODO(selfhost:Frontend)`.

Remaining Frontend self-host markers: 15.

## Remaining Work

- Replace local compatibility AST/source/diagnostic/option models with the real
  sibling package APIs once manifest changes are allowed.
- Wire conditional compilation, macro expansion, Sema desugar/typecheck,
  incremental AST cache/diff, generic instantiation, CHIR lowering, plugin FFI,
  and result serialization to the real implementations.
- Audit behavior against the C++ frontend tests after dependency wiring.
