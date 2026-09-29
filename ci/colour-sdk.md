# CI target std/runtime inputs

`prepare-colour-sdk.mjs` uses `bootstrap/sdk_build.sh` to assemble the target SDK.
It consumes a complete std prefix (modules, static archives and dynamic std,
including AST), and the current build's runtime and boundscheck. The host SDK
keeps its own runtime. `with-colour-sdk.mjs build` selects target link inputs
while retaining the official host loader; `run` selects the rebuilt consumer's
loader. Publication uses #710's `patched-runtime/lib/<tuple>` and
`CJCJ_PATCHED_RUNTIME_LIB_DIR`.

The checked-in std release is an identified input, **not currently qualified**:
its runtime is 4c4cbf53b444, while `runtime_pin.env` requests 5d35d19345d7.
Preparation reports `COLOUR_STD_NOT_RUN` before installing this mismatched pair.
#501/#135 must supply a matching Linux x86_64 std release and manifest before
updating `colour-std-pin.json`. Other platforms await #695/#473/#501; the Linux
SDK assembler must not be used to manufacture their SDKs.

With a qualified input, CI scans the linked compiler and smoke programs using
`check-colour-tlab.py`. Each JSON row retains the artifact hash and independent
assertions for old-layout absence, new-layout presence and unresolved colour
references. An input archive or ELF inspection does not establish build or smoke
completion. The wrapper tests only establish environment forwarding and input
rejection; they are not compiler acceptance.
