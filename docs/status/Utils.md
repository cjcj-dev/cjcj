# Utils Port Status

Date: 2026-06-15

Build: `cjpm build` passes.

Implemented:

- Replaced the Utils scaffold with a multi-file Cangjie package mirroring the C++ Utils component layout.
- Added working ports for constants, check/assert helpers, pointer wrappers, partially persistent stack/vector/map helpers, SipHash, string/numeric helpers, file/path helpers, Unicode conversion/range helpers, floating point formatting, ICE helpers, semaphore/task queue/profile recorder utilities, user profiling output, signal placeholders, casting helpers, and standard-library metadata maps.
- Preserved native/back-end boundaries by keeping LLVM and other native runtime behavior out of this package; native memory trimming and process signal installation are left as explicit FFI TODOs.
- Kept the package self-contained within `packages/utils` and avoided manifest or cross-module package edits.

Known fidelity caveats:

- Full generated Unicode NFC and width tables from `NormalisationData.generated.inc` and `WidthData.generated.inc` are not yet ported; current logic includes Hangul normalization and broad width handling, but not byte-for-byte generated-table parity.
- XID identifier classification uses a reduced generated-table subset and must be regenerated from the upstream Unicode data for full compiler fidelity.
- Signal/crash handler installation and platform memory-pressure release require C FFI bindings to the same platform APIs used by the C++ implementation.
- `ParallelUtil` cannot expose the C++ CHIRBuilder/Translator entrypoint until the CHIR-facing Cangjie types exist in the selfhost packages.
- `TaskQueue` is buildable and deterministic, but it does not yet reproduce the C++ thread-pool execution model.

Remaining Utils selfhost markers: 7.
