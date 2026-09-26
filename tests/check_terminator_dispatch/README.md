# CheckTerminator dispatch witnesses

Build the compiler's release archives, then run:

```sh
python3 tests/check_terminator_dispatch/run.py --build-tree /path/to/tree --sdk /path/to/sdk --out /path/to/evidence
```

The fixture links existing product archives. It does not recompile the checker,
change its visibility, or add a product hook. All cases call the public
`CHIRChecker.CheckPackage([CHECK_FUNC_BODY])` entry. Each prints the observed Bool
before checking it; the runner separately checks the product diagnostic.

The 22 keys correspond to upstream `src/CHIR/Checker/CHIRChecker.cpp:1791`.
Twenty-one cases use malformed IR to exercise each callback's existing operand
or successor invariant (MultiBranch instead checks the condition's Int type). `numeric` checks the intentional no-op at upstream
`CHIRChecker.cpp:3030`; `control` supplies a valid Exit. Both must produce true
and no checker error or unknown-kind warning. Removed operands include successor
links, using the real IR mutation API so predecessor checks remain consistent.

Controlled mutations must be applied in isolated product build trees:

- Route TERMINATOR to CheckOtherExpression in CheckExpression: the 21 malformed
  cases fail their Bool/diagnostic assertions; numeric and control keep true.
  Run the existing expression-dispatch suite as well to show unrelated routes
  retain their results (only its malformed Exit should change).
- Remove only TRY_ADD from the map: only `add` fails, with the real unknown-kind
  warning. This tests the map miss branch without a test-only product entry.
- Change CheckExit's operand equality check to an at-least check: only `exit`
  fails, while valid Exit and the other callbacks retain their results.

Source alignment (one key per callback and narrowing inside the callback) is a
separate read claim. Passing behavior tests alone cannot distinguish a match
from the required map. ExprKind.hashCode uses the same ExprKindIndex as equality.

Runtime SO tests are inapplicable: the changed checker is a compiler archive.
Record the fixture source, archive, linked ELF, SDK/std/runtime hashes, build
return codes, affinity and uptime for every arm. Restoring retained candidate
archives must restore both their hashes and all assertions.
