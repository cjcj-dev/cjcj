# In-process LLVM input

`build-llvm-dylib.yml` produces a separate `depot/dylib` directory on GitHub's
Linux x64 and AArch64 runners. Both builds enable X86, ARM, and AArch64 and use
`LLVM_SHA` from `ci/llvm_pin.env`. The existing sccache composite action supplies
both compiler launchers and the disk cache (the GHA sccache backend stays off).

A publication is a candidate, not an automatic pin update. Record its run ID,
attempt, artifact ID and library SHA256 in the reviewed platform pin. Source
jobs download that exact artifact into the depot's `dylib/` subdirectory.
The platform pins currently refer to build-fixed-llc run 35805605717,
attempt 1 (x86_64 artifact 10728985379, AArch64 artifact 10728610568).
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
