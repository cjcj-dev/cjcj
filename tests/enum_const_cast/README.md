# Enum static-cast constant propagation

Regression for upstream `20d75dd027b2a6a0f806c4dd6e3cfb4330fb6bef`,
`include/cangjie/CHIR/Analysis/ConstAnalysis.h:1020–1037`.
The upstream commit contains no tests.

Run with a built stage1 compiler and its matching host SDK environment:

```sh
python3 tests/enum_const_cast/verify.py --compiler /path/to/cjcj-stage1 --out /path/to/evidence
```

The runner compiles the fixture through the real frontend and optimizer, checks
its exit code, and reads the final CHIR dump. `knownChoice` must store `22` to
its return allocation without a `MultiBranch`; this requires propagation through
both UInt32 → enum and enum → UInt32. `dynamicChoice` must retain its branch,
and the ordinary numeric conversion must still fold to `8`.

Each assertion is evaluated and printed independently. Removing either enum
propagation direction in the product must fail only `enum_round_trip_propagates`.
Compilation or loading failures are recorded separately and are not valid
mutation-test evidence. `result.json` records the actual function bodies,
compiler and fixture hashes, command, return code, and assertion outcomes.
