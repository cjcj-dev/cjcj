# Cangjie macro host lifecycle (#258)

`minmac/defs.cj` defines an identity macro. `use.cj` invokes it and must produce
`expandedById` in binary CHIR and exit normally. `repeated.cj` calls the same
macro package twice to exercise image ownership. `plain.cj` is the no-macro
control. `run.py` evaluates every assertion even if an earlier assertion fails.
It records compiler rc, decoded function names, ELF/runtime SHA256, process maps,
loader bindings, CPU affinity, uptime and wall time. It uses no product probes.

Build the macro with the official host compiler, in `imports/minmac`:

```sh
cjc --compile-macro defs.cj
```

Place the tested stage1 at an isolated SDK's `bin/cjcj-stage1`. Both compiler and
macro use official std/runtime from the same SDK version. Run two layouts:

- `same`: `LD_LIBRARY_PATH` selects the runtime at the tested compiler's
  `../runtime/lib/linux_x86_64_cjnative` (same inode).
- `copy`: that relative runtime is a physical copy, while `LD_LIBRARY_PATH`
  selects the original host SDK runtime (different inode, identical bytes).

For each layout, set `CANGJIE_HOME` to the isolated SDK and run:

```sh
python3 tests/macro_host_runtime/run.py \
  --compiler /path/sdk/bin/cjcj-stage1 --macro-import /path/imports \
  --host-runtime /path/loaded/libcangjie-runtime.so --out /path/new-evidence
```

The output directory must be new. On Linux the loader binding assertions require
both `RunCJTask` and `ReleaseHandle` to resolve to `--host-runtime`, and the
macro image to remain mapped until host shutdown (no premature link-map
destruction event). C++ upstream finishes its runtime before unloading macro
images (`src/Macro/InvokeUtil.cpp:113-129`); this Cangjie host must leave its
runtime alive. The lifetime rule follows the #258 advisor correction of
2026-09-25 16:41.
Add `--parallel` to cover `--parallel-macro-expansion`. The lifecycle
assertion includes the process exit after CHIR generation, rather than accepting
an artifact left by a failed process. Run the same suite on the baseline and on
product mutations restoring foreign-runtime binding and process-level shutdown;
also restore the old macro-image unload call as a separate mutation;
record each mutation's source diff and binary identity. The plain input must
continue to pass. macOS/Windows source branches are not covered by this Linux
integration runner.
