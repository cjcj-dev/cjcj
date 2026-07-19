# Prebuilt -O2-fixed `llc`

The stock nightly SDK's `llc` miscompiles Cangjie's `-O2` output: a non-deterministic
memory corruption in the SelectionDAG backend (`visitGCRelocate` lowers a relocate of an
`undef` GC pointer to a non-materializable `getTargetConstant<0xFEFEFEFE>`, which `getVR`
then uses as a register → `addRegOperandToUseList` heap corruption → SIGSEGV). This blocks
building `cjcj` itself at `-O2`.

The fix is in **`llc` (SelectionDAG backend) only** — `opt` and `libLLVM` are untouched
(`cjc` runs `opt` for IR-level `-O2`, which needs no fix, then `llc` for codegen). So the
minimal, ABI-safe integration is: **replace only the SDK's `llc`** with the self-contained
static build here. `ci/setup_sdk.sh` does this idempotently.

## Source

- fork: https://github.com/cjcj-dev/cjcj_llvm  branch `fix/scheddag-memcorrupt`
  - `edd69670`  [SelectionDAG] Fix relocate of undef producing an unusable TargetConstant
  - `17c6e735`  [CJStackPointerInserter] Skip constant GC-pointer operands in filterGCPointer
- base `2429f2f48` = gitcode Cangjie/llvm-project dev (LLVM 15.0.4 patched).
- build: Release, assertions OFF, `LLVM_TARGETS_TO_BUILD=X86`, static (no `libLLVM` dep),
  clang-15, `-std=c++17`. Full recipe: `reports/llvmfix/BUILD_INFO.txt`.

## Files

| file | platform | decompressed sha256 |
|---|---|---|
| `linux_x86_64/llc.gz` | linux x86_64 | `98fba7b69e344da812d3a4d74289819417c99a14e110c8caa434abffcfbb6b83` |

Validated: SDK + only this `llc` swapped (libLLVM untouched) → full `cjc -O2` build rc=0,
zero crashes, zero ABI symptoms, produced a working `cjcj` binary; plus 680+100 llc stress
runs zero-crash.

## TODO

- **linux_aarch64**: an aarch64-target build of the fixed `llc` is still needed for building
  `cjcj` at `-O2` on aarch64. Depends on task#7 (release matrix) adding aarch64 to the `cjcj`
  build matrix — no CI job builds `cjcj` on aarch64 today, so this is not yet blocking.
