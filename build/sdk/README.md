# build/sdk — unified SDK production line

`node build/cli.mjs sdk <plan|build|package|verify>` is the only SDK production entry.

| module | responsibility |
|---|---|
| `source_pin.env`, `wasi_pin.env` | fixed source commits and the WASI sysroot URL + SHA-256 |
| `pins.mjs` | parse and validate the pins once |
| `targets.mjs` | host platforms, target tuples, the 15 formal release assets, release-set validation |
| `bootstrap.mjs` | Stage1 (seed std) -> std-bootstrap in a std-free view -> stage1-initial -> stage1-std -> Stage2 -> final std -> Stage3 -> final install (`chainPlan`, guarded by `assertSameSourceChain`; H1 order of ci/bootstrap/sdk-targets.mjs:325-334) |
| `native.mjs` | native LLVM/AST/cjdb configuration and the paired runtime + boundscheck build |
| `std.mjs` | one std configuration: `--experimental --enable-local-mode --cfg local_mode_api=off` for every tuple, `local_mode_api=on` only for the Linux x64 native std; Wasm std package argv (`wasmStdPackageArgv`): std.core prelude, ordinary packages with `--no-sub-pkg`, aggregate root `std` without it, -O2 then default-level fallback |
| `tools.mjs` | stdx, Java interop and the 10 cangjie_tools consumers of the installed SDK |
| `install.mjs` | the single installer; product `runtime/lib/<target>`, `.compiler-exec/` and untouched official `.host/runtime/lib/<host>` stay separate; failed installs are removed |
| `verify.mjs` | one verifier for installed and relocated SDKs |
| `archive.mjs` | tar.gz/zip, `SHA256SUMS`, relocation (original install moved away before verification) |
| `run.mjs` | process supervision and rc/resource records |

Tests: `node --test build/sdk/test/*.test.mjs`.
