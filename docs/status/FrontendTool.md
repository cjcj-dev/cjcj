# FrontendTool

Ported files:

- `FrontendTool.cj`
- `DefaultCompilerInstance.cj`
- `IncrementalCompilerInstance.cj`
- `CjdCompilerInstance.cj`

Current status:

- Frontend entry orchestration, dump actions, empty-input diagnostics, CJD compile skipping, default stage profiling,
  CJO/result saving, and driver-result handoff are implemented against the current self-host `frontend` package.
- AST screen dumping, object-only builtin dependency normalization, and FrontendTool incremental no-change/change
  detection are implemented with the public data exposed by the current self-host frontend package.
- The FrontendTool incremental instance now imports the real `incremental_compilation.IncreKind`,
  `CachedMangleMap`, and `IncrementalCompilationLogger` instead of carrying local compatibility copies of those
  types.
- FrontendTool incremental cache comparison now validates the cache format version, rolls back when plugins are
  enabled, and treats source-file summary changes as incremental work instead of incorrectly reporting no-change.
- FrontendTool incremental scope analysis now rolls back for multi-source-package inputs instead of trying to reuse a
  single-package cache path, matching the C++ incremental precondition that exactly one source package is analysed.
- Incremental logging now reports analysis result kind, recompiled/deleted cache-summary sets, semantic full/incremental
  decisions, and CJO-saving decisions through the real `IncrementalCompilationLogger`.
- FrontendTool incremental fallback now emits explicit rollback reasons for missing/unreadable cache data, cache-version
  mismatch, and compile-argument changes, matching the C++ habit of explaining each rollback path.
- FrontendTool incremental result dumping now uses the same delimiter/count-oriented shape as
  `incremental_compilation.IncreResult.Dump()` and includes source-file summary additions/removals alongside
  declaration summary changes.
- Incremental result saving now propagates failures from `.frontend_tool.incr` and cached CJO summary writes instead of
  silently ignoring them, so the frontend result status reflects cache/signature persistence failures.
- Incremental changed-struct collection is filtered by the same declaration-summary keys used by the cache delta, so
  incremental codegen metadata no longer marks every struct as changed on every incremental compile.
- Common-part/CJMP-style CJO output is delayed to result saving, matching the C++ FrontendTool split between
  `PerformCjoSaving` and `PerformResultsSaving`.
- Multi-package CJO saving now pre-mangles source declarations that still lack package-scoped names before writing
  package summaries, mirroring the C++ sibling-package export-id stabilization within the current frontend AST model.
- FrontendTool-local CJO summaries include nested declaration identities and mangled names so saved package output
  preserves the public declaration surface exposed by the current self-host frontend AST.
- `NeedCreateIncrementalCompilerInstance` also exposes an overload for the richer `option.GlobalOptions` model with
  the same mock, coverage, CHIR-output, and common-part-CJO guards and incremental logger side effects as the C++
  helper; the current frontend-options overload now uses the same available common-part-CJO guard instead of adding
  CJD/common-part-CHIR exclusions.
- The local `ExecuteFrontendByDriver` handoff preserves the frontend option state currently exposed by the self-host
  frontend package, including object inputs, package/import/plugin paths, CJMP inputs, output paths, and cache fields.
- The FrontendTool driver-handoff compatibility object now uses real `option.TempFileInfo` and `option.OrderedInput`
  payloads for frontend output files and ordered library inputs, and has a richer `option.GlobalOptions` copy overload
  that carries frontend outputs, ordered libraries, builtin dependency sets, cache paths, and localized-symbol metadata.
- A richer `option.GlobalOptions` object-only frontend helper now mirrors the C++ `inputLibraryOrder` transform: it
  removes standard `cangjie-*` library entries, converts them to indirect builtin `.cjo` dependencies, and preserves
  non-standard library order entries.
- The implementation is intentionally conservative where the current package graph does not yet expose the C++ surfaces
  used by FrontendTool: native `TempFileManager`, the production driver option object, shared CHIR/CodeGen models, and
  the full C++ incremental AST-diff/pollution data structures.
- CJO and FrontendTool incremental cache writes use the shared `utils.FileUtil.WriteToFile` path so parent directories
  are created consistently with the shared file utility behavior.
- `CjdCompilerInstance` profiles the result-saving CJO write path with `ProfileRecorder("Main Stage", "Save results")`
  when it actually emits CJO output, matching the C++ CJD override structure.
- `DefaultCompilerInstance` wraps `frontend.CompilerInstance` instead of inheriting from it because `CompilerInstance`
  is not currently `open` in the frontend package and this module is not allowed to edit frontend.

Residual fidelity risks:

- There are zero FrontendTool self-host TODO markers.
- Complete C++ parity still depends on the adjacent self-host packages exposing the same public contracts that the C++
  FrontendTool uses for native code generation, temp-file management, production driver options, and full incremental
  AST-diff/pollution analysis.
