# smallports r2 report

## Root cause and evidence

1. Replayed the four excluded commits as `3d50b9fc`, `761da46e`,
   `966a03be`, and `43550e2c`, then invoked:

   ```text
   /tmp/audit/verify.sh /root/cj_build/wt/fix_smallports_r2 quick smallports_r2
   ```

2. The first minimal smoke failure was `conditional_compilation`:

   ```text
   NoneValueException
       at cjcj::chir::CHIRBuilder::CreateLambda(...)(packages/chir/src/CHIRBuilder.cj:642)
       at cjcj::chir::Translator::Visit(...LambdaExpr)(packages/chir/src/Translator.cj:1304)
   ```

   The differential run reported `difftest: TOTAL=114  PASS=88 MISMATCH=0 FAIL=26`.

3. `Translator.Visit(LambdaExpr)` creates a `BlockGroup`, then creates the
   lambda, and only afterwards calls `Lambda.InitBody` (selfhost
   `Translator.cj:1303-1306`).  Therefore the added
   `expr.GetFuncOrLambdaBody().getOrThrow()` ran before the lambda had a body.

4. The corresponding C++ allocation sequence is
   `CHIRBuilder::CreateExpression` in
   `include/cangjie/CHIR/IR/CHIRBuilder.h:186-194`: it records both the
   expression and its `LocalVar` result in the allocation bucket.  The lambda
   construction order is in
   `src/CHIR/AST2CHIR/TranslateASTNode/TranslateLambdaExpr.cpp:24-32`, and
   `Lambda::InitBody` establishes the owned body in
   `src/CHIR/IR/Expression/Expression.cpp:2100-2110`.

## Fix

`CHIRBuilder.CreateLambda(FuncType, ...)` now takes the allocation bucket from
its already-established parent block, then registers the `Lambda` and its
`LocalVar` result in that bucket.  This preserves the C++
`CreateExpression` two-object tracking sequence without a missing-value
fallback.  The overload that receives an already-initialized body is unchanged.

There are no platform branches in the cited C++ sources (`rg` for `_WIN32`,
`__APPLE__`, `__OHOS__`, `__linux__`, `#ifdef`, and `#elif` returned no lines).
The changed construction sequence has no conditional branch; all 0 branches,
cases, and early returns of this translated fragment are covered.

## Verification

The required quick verification was invoked after the repair:

```text
/tmp/audit/verify.sh /root/cj_build/wt/fix_smallports_r2 quick smallports_r2
```

Result: pending the shared verifier lock.

## Fidelity checklist

- No newly introduced named symbol lacks a C++ counterpart: `bg`, `expr`, and
  `res` mirror the `CHIRBuilder::CreateExpression` sequence at
  `CHIRBuilder.h:186-194`.
- No business source was changed and no band-aid, null fallback, or skipped
  allocation was added.
- No system-root dependency was encountered or substituted.
