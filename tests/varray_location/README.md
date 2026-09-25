# VArray compound assignment source ranges

Run on kkk2 with a built product stage1 and a matching workspace SDK:

```sh
python3 tests/varray_location/run.py --compiler /absolute/cjcj-stage1 \
  --sdk /absolute/sdk-host --out /absolute/evidence/candidate
```

`compound.cj` exercises all thirteen compound operators and ordinary assignment.
The checker reads the actual binary CHIR. It checks the GET range against the
assignment's full range, including the file and file ID. SET ranges and intrinsic
counts are independent controls; all three assertions run even if one fails.

For the cut arm, undo only the product location propagation in
`TranslateVArrayAssign`, rebuild stage1 in a separate directory, and run the same
command with that compiler. Only `compound_get_assignment_location` must fail.
Restore the source, rebuild, and run again. Do not alter assertions between arms.

Upstream: 55ee950e75ee9e69fc01303ecc182e7afeb4f4c0,
`src/CHIR/AST2CHIR/TranslateASTNode/TranslateAssignExpr.cpp:86`.
