# Macro

Status: continued partial self-host port, build passing.

The Macro package now replaces the scaffold with a multi-file Cangjie implementation mirroring the C++ component split:
macro collection and expansion, macro call state and resolution, token and node serialization, macro evaluation client/server plumbing, native invoke configuration, macro generated-source processing, and test entry construction.

Current constraints:

- `packages/macro/cjpm.toml` has no package dependencies, so this port includes a local compatibility model for the Basic, AST, and Parse surfaces that Macro needs.
- Native dynamic loading now uses C FFI (`dlopen`/`dlsym`/`dlclose` or Windows equivalents), runtime init/fini symbols are resolved through the native library, and macro function pointers can be invoked with serialized token buffers.
- Message and AST serialization use deterministic compiling codecs because generated flatbuffer schema packages are not available to this isolated package.
- Generated-token parsing uses a local bridge until the real Parse entry point can be imported without changing package manifests.

Verification:

- `cjpm build` passes.

Remaining source markers for this module: 0.
