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
