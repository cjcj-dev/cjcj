# Native Mach-O LTO command regression

`commands.cj` links the existing production archives. It calls
`CJNATIVEBackend.Generate()` and asserts the `Tool` arguments returned by
`GetBackendCmds()`: native archive mode, bitcode-only input collection, standard
library selection/deduplication, and temporary opt output. It also checks the
stripped iOS dylib install name and that final links still include the runtime.

The matrix covers iOS device/simulator, full/thin LTO, normal/incremental input,
static/dynamic std and native/bitcode archives. Each case runs in its own process
and directory. Assertions print their names and values even on success.

Darwin native archives are rejected by the upstream CLI, and the upstream backend
returns after opt. The four `darwin-component` cases therefore call the public
`MachO.ProcessGeneration` interface on the production Darwin toolchain. These are
component tests, not evidence that Darwin native LTO is CLI-accessible.

Run on a host SDK matching the product archives:

```sh
python3 test/macho_lto_staticlib/run.py \
  --sdk /path/to/private/host-sdk \
  --llvm-library /path/to/pinned/libLLVM-15.so \
  --product /path/to/built/product-tree --out /path/to/evidence
```

The compiler used to build the observer and the product archives must use the
same native host ABI. `--llvm-library` supplies the LLVM API used by the compiler
shim; the observer still uses the host SDK's compiler and runtime.

This regression verifies command construction. It does not claim that Apple
archives were linked or run on the Linux host. The separate stage1 smoke compile
checks that the actual compiler executable can compile a Cangjie source fixture.
