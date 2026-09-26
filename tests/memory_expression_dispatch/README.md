# Memory expression dispatch

Run `python3 tests/memory_expression_dispatch/run.py --build-tree TREE --sdk SDK --out OUT`
after building the product release archives. The runner links those archives;
it never compiles a checker copy. Each case enters `CHIRChecker.CheckPackage`.
Seven malformed expressions assert the returned Bool and the route diagnostic.
The empty body, valid allocation and valid load are positive controls.

The upstream anchor is `src/CHIR/Checker/CHIRChecker.cpp:4127–4153`: seven enum keys
map to callbacks and one lookup chooses a callback, with a warning on a miss.
`ExprKind` hashing uses the same index as equality. The unknown-key path has no
natural product input: `ExprKindMajor` assigns MEMORY_EXPR only to these seven
keys. A temporary lookup cut to INVALID observes that path in the product.

Causal controls in isolated product trees: changing the lookup key to INVALID
must fail the seven negative memory witnesses while controls keep passing;
replacing only the LOAD callback with CheckOtherExpression must fail only load.
Replacing the existing MEMORY_EXPR callback in CheckExpression exercises the
real baseline phase entry and must fail the seven negatives. All cases print
TARGET after CheckPackage returns, even on failure. Build/link failures never
count as a target failure. Existing expression-dispatch tests are regression
controls for routes outside this change.
