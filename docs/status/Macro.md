# Macro

Status: continued partial self-host port, build passing.

The Macro package now replaces the scaffold with a multi-file Cangjie implementation mirroring the C++ component split:
macro collection and expansion, macro call state and resolution, token and node serialization, macro evaluation client/server plumbing, native invoke configuration, macro generated-source processing, and test entry construction.

Current constraints:

- `packages/macro/cjpm.toml` has no package dependencies, so this port includes a local compatibility model for the Basic, AST, and Parse surfaces that Macro needs.
- Native dynamic loading now uses C FFI (`dlopen`/`dlsym`/`dlclose` or Windows equivalents), runtime init/fini symbols are resolved through the native library, and macro function pointers can be invoked with serialized token buffers.
- The in-package macro server path now classifies staged/server exits, deserializes macro-call batches, evaluates calls, serializes results, and resets per-stage state through the local process-message bridge.
- Macro-call collection now follows represented expression fields (function parameter defaults, function arguments, call bases, member bases, returns, if conditions, and binary operands) and writes expanded expression replacements back to their parent AST fields.
- The local generated-token scanner now handles comments, escaped string and rune forms, multiline/raw strings, built-in type keywords, and the common multi-character operators used when reparsing macro output.
- Test-entry construction now participates in the package expansion flow, handles `$test` main-package pairing, models primitive/ref/variable declaration nodes locally, checks `@Test`/`@TestCase` Unit-return and constructor constraints, and collects macro calls in variable initializers.
- Message and AST serialization use deterministic compiling codecs because generated flatbuffer schema packages are not available to this isolated package.
- Generated-token parsing uses a local bridge until the real Parse entry point can be imported without changing package manifests.
- Token/native decoding and the deterministic node codec now preserve quoted/raw token widths, primitive/ref types, variable initializers, function parameters and returns, call arguments, if bodies, and block statement payloads for the local AST surface.

Verification:

- `cjpm build` passes.

Remaining source markers for this module: 0.
