# CheckExpression dispatch witnesses

Build the product release archives first, then link the fixture to those archives:

```sh
python3 tests/check_expression_dispatch/run.py --build-tree /path/to/tree --sdk /path/to/sdk --out /path/to/evidence/dispatch
python3 tests/instantiate_value/run.py --build-tree /path/to/tree --sdk /path/to/sdk --out /path/to/evidence/instantiate
```

The SDK compiler, std, and runtime must belong to the same toolchain. The runner
records archive/SDK/ELF hashes, command, return codes, affinity, and uptime. It does
not compile a second copy of the product checker.

All witnesses enter `CHIRChecker.CheckPackage([CHECK_FUNC_BODY])`. Five malformed
expressions assert the returned Bool and their diagnostic text: an Exit with an
operand, unary/binary expressions whose operands were erased, a Load without an
operand, and a Lambda without an identifier. Valid Exit and Lambda bodies are
positive controls. `tests/instantiate_value` supplies the OTHERS route witnesses.

Upstream shape: `src/CHIR/Checker/CHIRChecker.cpp:1762-1786` constructs an enum to
callback map before parent/result checks, and narrows unary/binary expressions
inside their callbacks. Consequently the unary/binary witnesses use their real
subclasses; creating plain Expression objects would fail at the cast before the
operand-count diagnostic.

Causal controls (only in isolated build trees): forcing the map lookup to OTHERS
must fail exactly the five malformed route witnesses while the two positive
controls and instantiate-value suite retain their results. Replacing only the
unary callback with CheckOtherExpression must fail only the unary witness.
Removing the existing GET_INSTANTIATE_VALUE checker call must instead fail its
negative witnesses while these seven dispatch cases retain their results.
