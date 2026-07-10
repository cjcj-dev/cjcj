# Conformance abstract modifier families

## Result

Both requested COMPILE-FAIL families were selfhost missing-diagnostic cases at baseline `74d4fe37`: the official compiler rejected every selected sample while selfhost accepted it. The fix restores the C++ diagnostic emission without changing any predicate or ordering.

| Family | Baseline direction | Official rerun | Selfhost rerun | Fixed | Remaining |
|---|---|---:|---:|---:|---:|
| `the visibility of an 'abstract' function must be 'public' or 'protected'` | official rc=1 / selfhost rc=0 | 22/22 target reject | 22/22 target reject | 22 | 0 |
| `class 'B' missing abstract modifier, otherwise abstract function or property should be implemented` | official rc=1 / selfhost rc=0 | 14/14 target reject | 14/14 target reject | 14 | 0 |

The 36-case manifest was selected mechanically from `/tmp/fix_confsweep_refresh_analysis.json` using the two exact `COMPILE-FAIL` cluster names. The rerun artifacts contain 36 rows each in `/tmp/cabsmod_official.tsv` and `/tmp/cabsmod_selfhost.tsv`.

Raw rerun summary:

```text
SIDE=official TOTAL=36
FAMILY=visibility TOTAL=22 TARGET_REJECT=22 REMAINING=0
FAMILY=missing_abstract TOTAL=14 TARGET_REJECT=14 REMAINING=0
SIDE=selfhost TOTAL=36
FAMILY=visibility TOTAL=22 TARGET_REJECT=22 REMAINING=0
FAMILY=missing_abstract TOTAL=14 TARGET_REJECT=14 REMAINING=0
```

## Root cause and C++ anchors

`DeclAttributeChecker::CheckAttributesForPropAndFuncDeclInClass` directly emits the abstract member visibility diagnostic after testing the member and enclosing class for `ABSTRACT`, then rejecting members that are neither `PUBLIC` nor `PROTECTED`:

```cpp
// src/Sema/DeclAttributeChecker.cpp:326,347-350
void DeclAttributeChecker::CheckAttributesForPropAndFuncDeclInClass(
    const ClassDecl& cd, Decl& member) const
if (member.TestAttr(Attribute::ABSTRACT) && cd.TestAttr(Attribute::ABSTRACT)) {
    if (!member.TestAttr(Attribute::PUBLIC) && !member.TestAttr(Attribute::PROTECTED)) {
        diag.DiagnoseRefactor(DiagKindRefactor::sema_invalid_member_visibility_in_class, member,
            MakeRange(member.identifier), "abstract", type);
    }
}
```

Selfhost had the same two guards but only appended an unconsumed `DeclAttributeIssue`. It now calls the same `sema_invalid_member_visibility_in_class` diagnostic with the identifier range and the C++ arguments `"abstract"` and the member kind.

`StructInheritanceChecker::DiagnoseForUnimplementedInterfaces` already mirrored the C++ collection, exclusions, ordering, diagnostic selection, and note construction. C++ creates the builder at `src/Sema/InheritanceChecker/StructInheritanceChecker.cpp:1021` and adds all notes at lines 1023-1034:

```cpp
// src/Sema/InheritanceChecker/StructInheritanceChecker.cpp:952,1014-1034
void StructInheritanceChecker::DiagnoseForUnimplementedInterfaces(
    const MemberMap& members, const Decl& structDecl)
DiagnosticBuilder builder = diag.DiagnoseRefactor(kind, structDecl, structName);
std::stable_sort(unImplementedMembers.begin(), unImplementedMembers.end(), CompMemberSignatureByPosAndTy);
for (auto member : unImplementedMembers) {
    // ... construct identifierName, abstractType, and note ...
    builder.AddNote(*member->decl, note);
}
```

The C++ builder emits on destruction in `src/Basic/DiagnosticEngine.cpp:314-323` (`DiagnosticBuilder::~DiagnosticBuilder`). Cangjie's `DiagnosticBuilder` requires explicit `Emit()`, so selfhost previously discarded this completed builder. The added `builder.Emit()` is placed after every note, preserving C++ order.

## Branch and platform audit

No C++ function or new branch was introduced in this change. The two target emission paths preserve every C++ guard:

- abstract visibility: both nested conditions at `DeclAttributeChecker.cpp:347-350` are unchanged and covered;
- missing abstract modifier: the non-empty unimplemented-member condition, class-like/other diagnostic selection, duplicate-declaration identifier form, abstract/interface note form, and all note iterations at `StructInheritanceChecker.cpp:1014-1034` are unchanged and covered.

Mechanical whole-function comparison counts were retained for audit: `CheckAttributesForPropAndFuncDeclInClass` has 10 `if`/`else if` occurrences and 2 early returns (`DeclAttributeChecker.cpp:326-377`); `DiagnoseForUnimplementedInterfaces` has 14 `if`/`else if` occurrences, 1 early return, and 4 `continue` exits (`StructInheritanceChecker.cpp:952-1037`). This patch adds or removes none of them.

Platform grep raw output:

```text
/root/cj_build/cangjie_compiler/src/Sema/InheritanceChecker/StructInheritanceChecker.cpp:347:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/InheritanceChecker/StructInheritanceChecker.cpp:813:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/InheritanceChecker/StructInheritanceChecker.cpp:911:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/InheritanceChecker/StructInheritanceChecker.cpp:1141:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/InheritanceChecker/StructInheritanceChecker.cpp:1185:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/InheritanceChecker/StructInheritanceChecker.cpp:1459:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/InheritanceChecker/StructInheritanceChecker.cpp:1503:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/DeclAttributeChecker.cpp:415:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
```

There are no `_WIN32`, `__APPLE__`, `__OHOS__`, or `__linux__` branches in either changed C++ source. The listed backend branches do not intersect the two changed emission sites, so no `@When` branch is required.

## Verification

Baseline representatives, built from unmodified `74d4fe37`:

```text
BASELINE sample=test_a09_03.cj selfhost_rc=0
BASELINE sample=test_a12_02.cj selfhost_rc=0
```

Post-fix representatives:

```text
POSTFIX sample=test_a09_03.cj selfhost_rc=1
error: the visibility of an 'abstract' function must be 'public' or 'protected'
POSTFIX sample=test_a12_02.cj selfhost_rc=1
error: class 'B' missing abstract modifier, otherwise abstract function or property should be implemented
note: unimplemented abstract function 'foo'
```

Targeted self-compile:

```text
SEMA_SELF_COMPILE rc=0 size=8342650
```

Authoritative full gate raw lines:

```text
difftest: TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
smoke15: PASS=15 FAIL=0
bcgate: shared functions: 2490  |  byte-identical: 2490 (100.0%)  |  differing: 0 | fully-identical samples: 114/114  |  compile-errors: 0
VERIFY-EXIT=0
```

## Delivery declarations

- 无任何 grep 不到 C++ 出处的新符号；本次没有新增符号，新增的两个诊断发射调用逐项锚定上述 C++ 实体。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 未撞到系统根；没有自行替代 pointer identity、ImportManager sema API、CHIR LinkTypeInfo 或 global-var attribute FFI。
