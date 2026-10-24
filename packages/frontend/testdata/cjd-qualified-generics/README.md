# CJD qualified generic overload regression

These are pending end-to-end inputs, not an executed test receipt. Use the
candidate compiler and its approved matching SDK in an isolated directory.
Do not use an unrelated installed compiler to qualify this change.

1. Build the `types` and `api` producer packages without APILevel annotations.
   Keep their CJO files and static libraries in the isolated import/link directory.
2. Place `api.cj.d` beside the generated `api.cjo` (the frontend derives the
   sidecar path from the CJO path). Keep the producer CJO unchanged.
3. Compile `call64.cj` and `call32.cj` separately using that import directory
   and `--cfg APILevel_level=20`. Each must fail specifically with an APILevel
   diagnostic, not with import, parser, linker or startup failure.
4. At level 21, call64 must compile and call32 must still produce the APILevel
   diagnostic. At level 22, both must compile. Save each program's own status
   and output; a nonzero exit alone is not the negative assertion.
5. For a controlled wiring check, rebuild an isolated candidate with both the
   qualified-type argument comparisons and the consumed-member guard reverted
   to the baseline, keeping these inputs and the independent positive controls
   fixed. At least one of the level-20 rejection assertions must fail. Restore
   both changes and rebuild before accepting the recovery result.

The package tests in `src/MergeAnnoFromCjd_test.cj` cover the comparison and
annotation transfer directly. They do not replace this CLI/producer/CJO/CJD/
consumer gate. Neither those tests nor this gate has been run for the initial
candidate; compiler/SDK and remote workspace admission are prerequisites.

This fixture does not cover two unrelated packages exporting the same short
type name, import aliases/re-exports, or native plugin ABI registration.
