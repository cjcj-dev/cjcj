# CI host/runtime boundary

`install_patched_runtime.mjs <artifact-dir> [install-root]` verifies the runtime
pin and artifact SHA-256, then copies it into
`<install-root>/lib/<platform>/libcangjie-runtime.{so,dylib}`. The default root
is `patched-runtime` in the working directory. It must resolve outside
`CANGJIE_HOME`; nested destination directories cannot escape through symlinks.
The official SDK is not modified.

The only exported setting is `CJCJ_PATCHED_RUNTIME_LIB_DIR` in `GITHUB_ENV`.
It is an explicit input for consumers rebuilt with matching coloured std and
runtime. It does not change `LD_LIBRARY_PATH`, `DYLD_LIBRARY_PATH`, or the
compiler host SDK. The native gc_unit build already uses its own build output.
The CI host compiler and smoke/std pairing migration belongs to #715; this
variable alone does not establish that pairing.

On Linux/glibc, `node ci/with-runtime-audit.mjs -- command ...` executes the CI
host command with a loader audit inherited by subprocesses. It records actual
loaded runtime paths and SHA-256 before their initializers run. Official SDK
executables are identified by resolved SDK path, or by the content hash of an
executable ELF in the SDK (copying the binary outside the SDK does not rebuild
it). A runtime is coloured if its resolved path or SHA-256 matches the isolated
runtime. Pairing the two produces `OFFICIAL_RUNTIME_MISMATCH` and exit 86;
other child exit codes are preserved. The parent checks the audit record even
when an intermediate command absorbs a rejected child's exit status.

The audit requires a C compiler and OpenSSL development headers/library. The
`RUNTIME_AUDIT` record includes the audit DSO SHA-256 and log path. It is a CI
check for ordinary inherited process environments, not a security boundary
against commands that deliberately remove loader instrumentation. Non-glibc
platforms require a separate loader implementation before using this entry.


`setup_sdk.mjs` also retains the official `opt`, `llc`, and native LLD. It
verifies the target tuple, publishes those tools via
`install_patched_llvm_tool.mjs` into `patched-llvm/bin`, and exports
`CJCJ_PATCHED_LLVM_BIN`. It does not put that directory on the host PATH.
Official SDK caches use the `cjv-host-tools-isolated` namespace so earlier
mutated SDK caches cannot be reused. A cached tool already matching the
coloured artifact is rejected; it is not silently accepted as official.

When an isolated LLVM directory is supplied, the audit also checks executable
path/hash before main and follows `/proc` ancestry through intermediate
shells. An official `cjc`/`cjc-frontend` ancestor paired with a coloured
optimizer, backend, or linker produces `OFFICIAL_TOOLCHAIN_MISMATCH` (86).
Explicit use by a rebuilt compiler is recorded as `LLVM_TOOL_LOAD`.
