# Macro

Status: partial self-host port, build passing.

The Macro package now replaces the scaffold with a multi-file Cangjie implementation mirroring the C++ component split:
macro collection and expansion, macro call state and resolution, token and node serialization, macro evaluation client/server plumbing, native invoke configuration, macro generated-source processing, and test entry construction.

Current constraints:

- `packages/macro/cjpm.toml` has no package dependencies, so this port includes a local compatibility model for the Basic, AST, and Parse surfaces that Macro needs.
- Runtime macro invocation is wired through the C++-faithful state machine, but native dynamic loading and cjnative runtime calls are still guarded by `TODO(selfhost:Macro)` markers until the C FFI boundary is introduced.
- Message and AST serialization use deterministic compiling codecs, with explicit markers where generated flatbuffer schemas must replace them.
- Generated-token parsing uses a local bridge until the real Parse entry point can be imported without changing package manifests.

Verification:

- `cjpm build` passes.

Remaining `TODO(selfhost:Macro)` markers: 5.
