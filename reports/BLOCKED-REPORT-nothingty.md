# BLOCKED-REPORT: `HasTypeOfNothing` cannot pass the required option gate alone

## Outcome

The faithful candidate was implemented and measured, then removed. It fixes the
first splitter-input divergence, but it does not satisfy the task's required
coverage or no-regression gate:

```text
splitter stream: same-name exprNum differences 35 -> 34
option: shared=779 byte-identical=663 (85.1%) differing=116 | only-ref=0 only-self=0
option: shared=779 byte-identical=662 (85.0%) differing=117 | only-ref=0 only-self=0
```

The post-candidate 492-line stream had zero name/position differences. The only
removed exprNum difference was:

```text
_CNat5RangeIlE7isEmptyHv    reference=32    before=33    candidate=32
```

The next difference remains `_CNat5RangeIlE4lastHv`, reference 82 versus
selfhost 79. Its direction (selfhost has three fewer expressions) cannot be
caused by the missing if-result allocation, which only removes one selfhost
expression when corrected. The other 33 later differences likewise remain in
the complete mechanical comparison. Therefore the premise that this predicate
covers all 35 functions is false for the measured tree.

Per the no-regression rule, the candidate and the temporary splitter output
line were reverted. The rebuilt source state restored the focused gate:

```text
REVERT_BUILD_EXIT=0
option: shared=779 byte-identical=663 (85.1%) differing=116 | only-ref=0 only-self=0
```

No fix commit was created. `verify.sh delta` and the O0 bcgate were not run on a
candidate that had already failed the mandatory focused gate; reporting those
on the reverted, zero-source-diff state would not validate the rejected change.

## Complete C++ call-point audit

The complete source-tree search found exactly three overloads and four call
sites:

```text
TranslateIfExpr.cpp:103  HasTypeOfNothing(const AST::IfExpr&)
TranslateIfExpr.cpp:433  one call: result-allocation condition
TranslateMatchExpr.cpp:87 HasTypeOfNothing(const AST::MatchExpr&)
TranslateMatchExpr.cpp:110 one call: result-allocation condition
TranslateTryExpr.cpp:16  HasTypeOfNothing(const AST::TryExpr&)
TranslateTryExpr.cpp:55  first call: suppress try-body store
TranslateTryExpr.cpp:92  second call: suppress returned value
```

The match overload and its sole use already exist in selfhost at
`packages/chir/src/Translator.cj:2223` and `:4385-4400`, with the C++
`matchMode` split and all-of semantics. The try overload and return-side use
exist at `:2326` and `:3947-3966`, but the C++ try-body call at
`TranslateTryExpr.cpp:55` was missing: selfhost called `StoreTryResult`
unconditionally at `Translator.cj:2304`. The complete candidate added the
missing `if (!HasTypeOfNothing(expr))` guard and tightened the existing try
predicate to the same unconditional try-block check plus all catch-block
checks as C++. It did not change any option exprNum row or the negative gate
result. There is no loop overload or loop call site of `HasTypeOfNothing` in
the C++ tree.

Thus there is no additional predicate call point available to port to turn
35 -> 34 into a large convergence. Adding match/loop heuristics would have no
C++ source and is forbidden.

## Candidate source mapping

Every candidate symbol and branch had a direct C++ source:

1. `HasTypeOfNothing(AstIfExpr)` mirrored
   `TranslateIfExpr.cpp:103-108`. It checked all three short-circuit operands:
   else-body presence, then-body `IsNothing()`, and else-body `IsNothing()`.
2. `IsEmptyIf(AstIfExpr)` mirrored `TranslateIfExpr.cpp:393-410`, including
   nonempty-then early return, block else, recursive else-if, non-block fallback,
   and absent-else success.
3. `IsEmptyBlock(AstBlock)` mirrored `TranslateIfExpr.cpp:412-422`, including
   the one-node literal/unit case, one-node nonliteral case, and empty-body case.
4. The missing try-body call mirrored `TranslateTryExpr.cpp:53-69`: the
   debug-location/store construction was entered only when
   `!HasTypeOfNothing(tryExpr)`.
5. The allocation condition mirrored `TranslateIfExpr.cpp:430-435` exactly:
   `((!HasTypeOfNothing && !IsUnit) || forceGenerateUnit)`.
6. The load-expression `SkipCheck(SKIP_DCE_WARNING)` mirrored
   `TranslateIfExpr.cpp:445-449` and used the existing `LocalVar.GetExpr()` and
   `Base.SetSkipCheck()` APIs.

All branches/early returns of the candidate helpers were covered: 3
short-circuit predicates in the if overload, the try overload's 1 early return
plus catch-block all-of path, 5 return paths in `IsEmptyIf`, and 3 return paths
in `IsEmptyBlock`, counted directly from the cited bodies.

The candidate was 1:1 but was not retained because faithfulness of a local
translation does not override the mandatory package-level no-regression gate.

## Measurement artifacts

Inputs retained from the prior splitter investigation:

```text
/root/cj_build/reports/splitin-option-ref-stream.tsv
  lines=492
  sha256=4a969bdfc4b85ed25a1e9722f4cc015f611727b4927875683875942d18456edf
/root/cj_build/reports/splitin-option-self-stream.tsv
  lines=492
  sha256=cfc7a1a64a73304193a40a5a370d2cad2fe18a0f89ae8dec43dbf253efbfbf25
```

Complete candidate stream (if plus missing try call) and full remaining-difference list:

```text
/tmp/nothingty-option-self-complete.tsv
  lines=492
  sha256=dc63a1941d858b02e534b64b36eb75823d2446e976b71e13da44b1a9a7ecbe1b
/tmp/nothingty-option-complete-diffs.tsv
  lines=34
NAME_POSITION_DIFF=0
EXPRNUM_DIFF=34
```

The temporary output called the real `Function.GetExpressionsNum()` at the
entry loop over `GetGlobalFuncsWithBody()` in `CHIRSplitter.cj:325`, matching
the prior splitin measurement method. It was removed before final rebuild.

The O0 minimal reproduction compiled successfully:

```text
MIN_REPRO_O0_EXIT=0
```

The compile-debug reproduction reached an independent, already explicit
downstream blocker and was not bypassed:

```text
IllegalStateException: BLOCKED: DIBuilder full debug type lowering is not ported from C++ DIBuilder.cpp:566-1563
MIN_REPRO_O0_EXIT=0 DEBUG_EXIT=1
```

This does not justify deleting the C++ `forceGenerateUnit` branch; any future
landing must retain that branch and validate it after the named DIBuilder
facility is ported by its dedicated owner.

## Platform audit

Raw platform scan for the modified C++ source:

```text
$ rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" TranslateIfExpr.cpp
<no matches>
```

There are no platform branches to mirror.

## Resume contract

Resume only after enough independent splitter-input roots have been fixed to
make the combined faithful change non-regressing. The immediate next root is
`_CNat5RangeIlE4lastHv` (82 versus 79); it needs its own C++-anchored
investigation. Continue through the saved 34-row difference list. Once the
combined input stream makes the option split membership converge, reapply the
audited `HasTypeOfNothing` candidate unchanged and rerun option sc gate,
O0 bcgate, and `verify.sh delta`.

## Required declarations

1. 无任何 grep 不到 C++ 出处的新符号；候选全部符号均有上述 C++ 锚，最终源码候选已回退。
2. 未改业务源码绕过、未加 band-aid 吞 bug。
3. 撞到的 debug 下游缺失设施已精确上报，未自行替代；没有碰触任何列明的系统根。
