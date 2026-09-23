# Runtime parameter ABI regression

`generate.py` extracts the five `@C` declarations and constructors verbatim from
`packages/macro/src/InvokeUtil.cj`. It does not maintain a second model of them.
The candidate compiler builds that source and writes one marked field at a time
into native memory. `compare.py` compares the observed marker offset and the
field's `sizeOf` with a separately compiled C++ `offsetof`/`sizeof` table from the
specified runtime `Cangjie.h`. The consumer field inventory comes independently
from that header, so omitted producer fields remain expected assertions.
The probe supports the 64-bit little-endian ABI used by this gate; the C++ probe
asserts pointer and bool widths and standard-layout properties.

Run on the build host, with `CANGJIE_HOME` and the compiler's host loader already
configured:

```sh
PRODUCT_LD_LIBRARY_PATH="$target_runtime:$target_stdlib" \
  bash test/runtime_param_layout/run.sh "$candidate_repo" "$runtime_header" \
  "$evidence_dir" "$candidate_cjc"
```

The output retains every compilation/run rc, hashes of the compiler and both
probe ELFs, source/header hashes, raw bytes, and the complete comparison.
`comparison.rc` fails on any difference, including alignment. The separately
reported `layout-contract.rc` covers sizes and field offsets; it must not be
presented as success of `alignment-contract.rc`. The known compiler `alignOf`
issue is tracked as cjcj#125; this test does not suppress those assertions.

For the negative control, restore the old `RuntimeGCParamC` declaration and its
five-argument construction in a separate product tree, rebuild that compiler,
and use that tree for the probe. Only the GC layout and the containing runtime
layout should gain failures. Restore the candidate source and repeat using the
same runtime/header and comparison tool. This is declaration-layout evidence,
not proof of runtime GC behavior.

`macro/def.cj` and `macro/use.cj` form the independent integration fixture. Build
the definition with `--compile-macro`, compile the use with its output directory
as `--import-path`, then execute the resulting ELF under the target runtime.
Success requires all three rc values to be zero and `MACRO_VALUE_ASSERT value=42`.
A failure before that assertion is not a successful integration test.
