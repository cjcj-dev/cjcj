# In-process LLVM input

`build-llvm-dylib.yml` produces a separate `depot/dylib` directory on GitHub's
Linux x64 and AArch64 runners. Both builds enable X86, ARM, and AArch64 and use
`LLVM_SHA` from `ci/llvm_pin.env`. The existing sccache composite action supplies
both compiler launchers and the disk cache (the GHA sccache backend stays off).

A publication is a candidate, not an automatic pin update. Record its run ID,
attempt, artifact ID and library SHA256 in the reviewed platform pin. Source
jobs download that exact artifact into the depot's `dylib/` subdirectory.
The platform pins are the current artifact coordinates; `release.json` records
the matching persistent prerelease assets and their independent archive and
manifest digests. Consumers continue to use the exact Actions artifact IDs.
`prepare_bootstrap_inputs.mjs` accepts `CJCJ_BOOTSTRAP_DYLIB_ARTIFACT`, otherwise
`CJCJ_BOOTSTRAP_COLOUR_DYLIB`, otherwise the pinned depot's `dylib/`. It validates
`LLVM_DYLIB_SHA256` before exporting `CJCJ_BOOTSTRAP_COLOUR_LLVM_SO` and
`CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256`. A missing or mismatched selected artifact is
an error; it never falls through to the official host library.

The official `CJCJ_BOOTSTRAP_HOST_LLVM_SO` remains a separate input. Installing
the colour library into the cjcj runtime SDK is tracked by cjcj#92. The standalone
C API check proves that this dylib can be loaded and called; it does not claim
that the bootstrap compiler has loaded it. Static tuple publication and its
eight payloads are unchanged.

`test-llvm-tuple.yml` downloads each platform's pinned artifact on its native
Linux runner. It checks the source pin, run/attempt and target list, then runs
`verify.py` against the reviewed library digest. A one-character manifest digest
change must fail before the original manifest is restored and verified again.

For a new publication, dispatch `build-llvm-dylib.yml` at the reviewed cjcj
commit and wait for both native jobs to finish. Preserve each original Actions
artifact ZIP and its manifest in a draft prerelease, together with SHA256SUMS.
Read back every asset and compare its bytes before publishing with
`--prerelease --latest=false`. Record the immutable release/asset IDs in
`release.json` and update the two `.env` pins from those verified manifests.
Do not substitute a local build for a GitHub artifact or overwrite an old asset.

Darwin and Windows dylibs are not supported by the existing producer or Linux
bootstrap entry point; the broader platform matrix is tracked in cjcj#73.
