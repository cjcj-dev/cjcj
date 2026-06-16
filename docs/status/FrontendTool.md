# FrontendTool

Ported files:

- `FrontendTool.cj`
- `DefaultCompilerInstance.cj`
- `IncrementalCompilerInstance.cj`
- `CjdCompilerInstance.cj`

Current status:

- Frontend entry orchestration, dump actions, empty-input diagnostics, CJD compile skipping, default stage profiling,
  CJO/result saving, and driver-result handoff are implemented against the current self-host `frontend` package.
- The implementation is intentionally conservative where the current package graph does not yet expose the C++ surfaces
  used by FrontendTool: native `TempFileManager`, ordered driver library inputs, shared CHIR/CodeGen models, and full
  incremental AST-diff/pollution data structures.
- `DefaultCompilerInstance` wraps `frontend.CompilerInstance` instead of inheriting from it because `CompilerInstance`
  is not currently `open` in the frontend package and this module is not allowed to edit frontend.

Remaining work:

- Remove the remaining FrontendTool self-host TODO markers after the frontend/codegen/incremental package boundaries
  expose the missing C++-equivalent models.
