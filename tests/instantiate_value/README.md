# GetInstantiateValue constraint checks

`checker.cj` constructs CHIR inputs and calls the release product's public
`CHIRChecker.CheckPackage`, with `CHECK_FUNC_BODY` as used by AST2CHIRCheck.
`run.py` links existing release archives; it never recompiles product sources.
It checks the returned Bool, execution of the TARGET assertion, and the exact
constraint argument index in the product diagnostic. Legal interface arguments,
intersection bounds, parent/function argument ordering, empty arguments and
arity mismatches are separate cases. The control has no instantiation expression.

```sh
python3 tests/instantiate_value/run.py --build-tree /path/to/product-tree \
  --sdk /path/to/host-sdk --out /path/to/evidence
python3 tests/instantiate_value/stage.py --compiler /path/to/cjcj-stage1 \
  --sdk /path/to/host-sdk --out /path/to/stage-evidence
```

The source fixtures are compiled by the actual stage1 compiler to binary CHIR.
This CLI check and the checker invariant test are separate: the release command
line hides `--chir-wfc` (`OptionTable.cj`, `CANGJIE_VISIBLE_OPTIONS_ONLY`).
Neither source compilation alone nor a CheckPackage call without CHECK_FUNC_BODY
proves the constraint checker executed.

Fault arms must change product CHIRChecker code, rebuild it, and use these same
fixture sources. Disabling the GET_INSTANTIATE_VALUE dispatch must expose the
negative cases; substituting the generic parameter for its actual argument in
one constraint predicate must expose only that argument family's negative cases.
Restoring the old IsEqualOrInstantiatedTypeOf predicates must reject the legal
intersection-bound cases, demonstrating the upstream c0a05cf0 regression.
