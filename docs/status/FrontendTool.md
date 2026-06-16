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
- The implementation is intentionally conservative where the current package graph does not yet expose the C++ surfaces
  used by FrontendTool: native `TempFileManager`, the production driver option object, shared CHIR/CodeGen models, and
  the full C++ incremental AST-diff/pollution data structures.
- `DefaultCompilerInstance` wraps `frontend.CompilerInstance` instead of inheriting from it because `CompilerInstance`
  is not currently `open` in the frontend package and this module is not allowed to edit frontend.

Residual fidelity risks:

- There are zero FrontendTool self-host TODO markers.
- Complete C++ parity still depends on the adjacent self-host packages exposing the same public contracts that the C++
  FrontendTool uses for native code generation, temp-file management, driver options, and incremental cache structures.
