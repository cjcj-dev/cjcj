# FrontendTool

Ported files:

- `FrontendTool.cj`
- `DefaultCompilerInstance.cj`
- `IncrementalCompilerInstance.cj`
- `CjdCompilerInstance.cj`

Current status:

- Frontend entry orchestration, dump actions, empty-input diagnostics, CJD compile skipping, default stage profiling,
  CJO/result saving, and driver-result handoff are implemented against the current self-host `frontend` package.
- AST screen dumping, object-only builtin dependency normalization, and FrontendTool-local incremental no-change/change
  detection are implemented with the public data exposed by the current self-host frontend package.
- Common-part/CJMP-style CJO output is delayed to result saving, matching the C++ FrontendTool split between
  `PerformCjoSaving` and `PerformResultsSaving`.
- Multi-package CJO saving now pre-mangles source declarations that still lack package-scoped names before writing
  package summaries, mirroring the C++ sibling-package export-id stabilization within the current frontend AST model.
- FrontendTool-local CJO summaries include nested declaration identities and mangled names so saved package output
  preserves the public declaration surface exposed by the current self-host frontend AST.
- `NeedCreateIncrementalCompilerInstance` also exposes an overload for the richer `option.GlobalOptions` model with
  the same mock, coverage, CHIR-output, and common-part-CJO guards as the C++ helper.
- The implementation is intentionally conservative where the current package graph does not yet expose the C++ surfaces
  used by FrontendTool: native `TempFileManager`, the production driver option object, shared CHIR/CodeGen models, and
  the full C++ incremental AST-diff/pollution data structures.
- `DefaultCompilerInstance` wraps `frontend.CompilerInstance` instead of inheriting from it because `CompilerInstance`
  is not currently `open` in the frontend package and this module is not allowed to edit frontend.

Residual fidelity risks:

- There are zero FrontendTool self-host TODO markers.
- Complete C++ parity still depends on the adjacent self-host packages exposing the same public contracts that the C++
  FrontendTool uses for native code generation, temp-file management, driver options, and incremental cache structures.
