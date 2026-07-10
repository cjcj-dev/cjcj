# B56/B57 diagnostic verification

Date: 2026-07-11

## Scope

- Rebased verification branch to master `74d4fe37507022550934ab515bd0b50c5e99bdf4`.
- No compiler or test-suite source was changed.
- Historical audit identity: B56 `sema_missing_redefined_func` = 168 tests; B57 `sema_missing_overridden_func` = 161 tests; total = 329.
- The deleted historical per-test TSV could not be recovered. Its 329 rows were selected from the unchanged official-first-diagnostic population, so this verification conservatively ran that complete 352-test population (B56 181 + B57 171). Include-list SHA-256: `970a5a5fbf8c254e0afbb2d2990a2802273a502e78e1bc11133e4f7d5e58d3be`.
- Comparison unit: the first non-macro `error:` line, its attached `note:` lines before the next `error:`, and macro-origin `error:`/`note:` lines. ANSI coloring and source rendering were excluded; diagnostic text and order were not normalized.

## Result

| Population | B56 exact | B57 exact | Exact total | Difference |
| --- | ---: | ---: | ---: | ---: |
| Conservative official-first-diagnostic superset | 165/181 | 155/171 | 320/352 (90.91%) | 32 |

Because the historical 329-path file is absent, an exact 329-row numerator cannot be reconstructed without inventing membership. The mechanically valid bound is:

- B56 historical 168: 152–165 exact (90.48%–98.21%).
- B57 historical 161: 145–155 exact (90.06%–96.27%).
- Combined historical 329: 297–320 exact (90.27%–97.26%).

The lower bound assumes all 23 tests outside the historical set were exact matches; the upper bound assumes those exclusions absorb as many current differences as their per-rule counts permit.

## Residual differences

All 32 residuals are one shape and one directory:

`src/tests/06_class_and_interface/02_interfaces/04_implementation_of_interfaces/01_overriding_and_overloading_when_a_class_implements_interfaces/a03/`

Files: `test_a03_164.cj` through `test_a03_195.cj`, inclusive.

- B57: `164`–`179` (16 tests).
- B56: `180`–`195` (16 tests).
- Official emits the expected B56/B57 primary diagnostic. Selfhost emits no corresponding primary diagnostic for these signature-mismatch cases. The variations cover function/operator name, arity, parameter type, subtype/supertype parameter direction, and generic function signature mismatches.
- Notes and macro notes do not form a second residual cluster: the target first diagnostic has no attached note or macro-origin note in these samples. Test 179 is a harness-level false positive caused by a non-target compilation failure; its diagnostic-block comparison still correctly records a mismatch.
- This is a verification-only classification. No root-cause fix was attempted.

## C++ anchors

- Diagnostic definitions: `/root/cj_build/cangjie_compiler/include/cangjie/Basic/DiagnosticSema.def:221-222`.
- Emitter: `StructInheritanceChecker::DiagnoseForOverriddenMember(const MemberSignature&)`, `/root/cj_build/cangjie_compiler/src/Sema/InheritanceChecker/StructInheritanceChecker.cpp:1178-1192`.
- Key emitter branches: `replaceOther` early return; cjnative `OVERRIDE`; `REDEF && STATIC`.

## Raw gate output

```text
cjpm build success
2026-07-11 03:38:16.315398: Test results: Total: 1807, Passed 1661, Failed 146, Errored 0, Skipped 0, Incomplete 0 (52.644s)
2026-07-11 04:09:45.869989: Test results: Total: 352, Passed 321, Failed 31, Errored 0, Skipped 0, Incomplete 0 (113.924s)
B5657_DIAG_COMPARE TOTAL=352 EXACT=320 DIFFERENCE=32 B56_EXACT=165/181 B57_EXACT=155/171 NOTE_DIFF=0 MACRO_NOTE_DIFF=0
```

The official raw line is the fresh 1,807-token-candidate scan from which the 352 official-first-diagnostic tests were selected. The selfhost raw line is the exact 352-test include run. Harness PASS is not used as the diagnostic verdict; the explicit diagnostic-block comparator is authoritative.

## Delivery checks

- C++ symbol/source mapping: this report adds no compiler symbol; the two audited diagnostic IDs and their emitter are anchored above.
- Platform scan: the audited C++ emitter is guarded by `#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND` at line 1185; no OS platform branch was added or changed.
- Full-branch coverage: N/A; no C++ function was ported or modified.
- 无任何 grep 不到 C++ 出处的新符号（未新增源码符号）。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的系统根已 BLOCKED 上报、未自行替代（本验证任务未撞到系统根）。

===END===
