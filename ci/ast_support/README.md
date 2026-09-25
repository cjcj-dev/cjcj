# Bootstrap AST archive pins

`build-ast-support.yml` uses `ci/source_pin.env` and `ci/llvm_pin.env` to
build upstream's `cangjie-ast-support` target, including its dependencies.
It disables the C++ compiler target and enables position-independent code:
stdlib links this archive into `libcangjie-std-ast.so`. Upstream sources and
CMake files are not patched.

To publish an update:

1. Start a new **Bootstrap AST support** workflow run on the candidate branch.
   For a cold-cache control, select `cold_cache`; use a separate new run for
   the warm-cache comparison.
2. Download each successful platform artifact. Check `PROVENANCE` against the
   source pins, platform, run ID and attempt, then recompute the archive's
   SHA256 and compare it with `SHA256SUMS`.
3. Explicitly commit that platform's run ID, attempt, artifact ID and archive
   SHA256 in its `.env` file here. A successful build does not update pins.
4. Run the source SDK workflow with those pins. Check both the original and
   installed archive digests in stage0, and record where the source build ends.

Do not rerun a workflow run referenced by these pins: rerunning can remove
the previous attempt's artifacts. Use a new workflow run for validation.
Artifacts have 90-day retention; durable storage is tracked by cjcj#87.

`prepare_bootstrap_inputs.mjs` shares the tuple artifact's selection/digest
routine. A selected AST artifact cannot silently fall back if it is missing
or has a different digest. Explicit and kkk2 build-directory fallbacks must
match the same reviewed archive digest.

The alpha.06 input artifact also contains `include/cangjie`,
`include/flatbuffers/StdAstFormat_generated.h`, and `schema/StdAstFormat.fbs`
from the same compiler commit as the archive. The complete
`third_party/flatbuffers/{bin,include,cangjie,modules}` tree is physically
copied from official nightly `1.3.0-alpha.20260924001050`, preserving the
matching Cangjie module and generator. `SHA256SUMS` covers all these files.
`ci/install_std_sdk_inputs.py` installs them before bootstrap/final std builds.
The compiler source authority is `https://gitcode.com/Cangjie/cangjie_compiler.git`;
the former Zxilly mirror does not contain the alpha.06 compiler commit.

Std compilation uses `ci/build_resources.sh`: requested heap defaults to 96GB,
clamped to 75% of measured physical memory so the official host runtime does
not reject the setting and fall back to its small default heap (#131).
Hosts with less than a 96GB budget compile one std package at a time;
large build hosts use every core. The selected heap, memory and parallelism
are printed. Windows qualification is `build-windows-runtime.yml`: it calls
`ci/build_ast_support.sh` with `cmake/mingw_x86_64_toolchain.cmake`, installs
that artifact, cross-builds `std/ast.o`, then `build_windows_std_ast.mjs`
rejects a swapped schema, header or archive before the DLL export guard.
