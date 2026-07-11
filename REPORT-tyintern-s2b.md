# sema Ty interning S2-B: `AllocTyVar` cache routing

## Scope and result

This batch covers all ten S1 TSV rows in the `S2-B` / `AllocTyVar` pattern.
The single allocation root, TY-0203, now calls the existing
`TypeManager.GetGenericsTy` cache path. The nine request sites inherit that
route without call-site edits. No identity key was changed. In particular,
the three request sites under `packages/sema/src/TypeCheckExpr/` were not
edited.

| Site | Status | Selfhost anchor | C++ correspondence |
|---|---|---|---|
| TY-0062 | CHANGED-VIA-ROOT | `packages/sema/src/MultiTypeSubstUtils.cj:215` calls `AllocTyVar` | `MultiTypeSubstUtils.cpp:299` calls `AllocTyVar`; allocation route is `TypeManager.cpp:2099-2105` |
| TY-0099 | CHANGED-VIA-ROOT | `packages/sema/src/TypeCheckCall.cj:1548` calls `AllocTyVar` | `TypeCheckCall.cpp:2863-2865` calls `AllocTyVar`; allocation route is `TypeManager.cpp:2099-2105` |
| TY-0111 | CHANGED-VIA-ROOT; CALL SITE UNEDITED | `packages/sema/src/TypeCheckExpr/LambdaExpr.cj:61` calls `AllocTyVar` | `TypeCheckExpr/LambdaExpr.cpp:273` calls `AllocTyVar`; allocation route is `TypeManager.cpp:2099-2105` |
| TY-0112 | CHANGED-VIA-ROOT; CALL SITE UNEDITED | `packages/sema/src/TypeCheckExpr/LambdaExpr.cj:72` calls `AllocTyVar` | same C++ Lambda allocation family at `TypeCheckExpr/LambdaExpr.cpp:273`; cache route is `TypeManager.cpp:2099-2105` |
| TY-0137 | CHANGED-VIA-ROOT; CALL SITE UNEDITED | `packages/sema/src/TypeCheckExpr/TypeChecker.cj:3697` calls `AllocTyVar` | Lambda fresh-variable route uses `AllocTyVar` at `TypeCheckExpr/LambdaExpr.cpp:273`; cache route is `TypeManager.cpp:2099-2105` |
| TY-0143 | CHANGED-VIA-ROOT | `packages/sema/src/TypeManager.cj:149` calls `AllocTyVar` | `TypeManager.cpp:468,487,503,537` calls `AllocTyVar`; cache route is `TypeManager.cpp:2099-2105` |
| TY-0197 | CHANGED-VIA-ROOT | `packages/sema/src/TypeManager.cj:767` calls `AllocTyVar` | `TypeManager.cpp:468,487,503,537` calls `AllocTyVar`; cache route is `TypeManager.cpp:2099-2105` |
| TY-0201 | CHANGED-VIA-ROOT | `packages/sema/src/TypeManager.cj:2356` calls `AllocTyVar` | `TypeManager.cpp:2277,2298` calls `AllocTyVar("T-Fly", true, &tv)`; cache route is `TypeManager.cpp:2099-2105` |
| TY-0202 | CHANGED-VIA-ROOT | `packages/sema/src/TypeManager.cj:2371` calls `AllocTyVar` | `TypeManager.cpp:2277,2298` calls `AllocTyVar("T-Fly", true, &tv)`; cache route is `TypeManager.cpp:2099-2105` |
| TY-0203 | CHANGED | `packages/sema/src/TypeManager.cj:2497`: `GetGenericsTy(decl)` | `TypeManager::AllocTyVar`, `TypeManager.cpp:2099-2105`: creates `GenericParamDecl`, then calls `GetGenericsTy(*dummyDecl)` |

There are no `KEEP-AS-IS` sites in this ten-row pattern. The separate
ephemeral diagnostic allocation TY-0068 remains excluded as recorded by S1:
C++ `Diags.cpp:313` also directly creates the temporary `ClassTy`.

## C++ cache semantics and symbol correspondence

The changed call mirrors this named C++ entity:

```cpp
Ptr<AST::GenericsTy> TypeManager::AllocTyVar(
    const std::string& srcId, bool needSolving, Ptr<TyVar> derivedFrom)
// TypeManager.cpp:2099
auto dummyDecl = MakeOwned<GenericParamDecl>();
auto newVar = GetGenericsTy(*dummyDecl); // TypeManager.cpp:2104-2105
```

`TypeManager::GetGenericsTy` inserts or retrieves the type from
`allocatedTys` at `TypeManager.cpp:94-104`. Its key is exactly the generic
declaration identity: `GenericsTy::Hash` hashes `decl` at `Types.cpp:138-143`,
and `GenericsTy::operator==` compares `decl` at `Types.cpp:1125-1129`.
Selfhost already has the same field-level semantics: `GenericsTy.Hash` uses
`GenericParamDecl.objectId` and equality uses `refEq` at
`packages/ast/src/Types.cj:1551-1565`; `GetGenericsTy` routes through
`internAllocatedTy` at `packages/sema/src/TypeManager.cj:449-453`.

No new function, helper, type, field, branch, cache-key kind, or identity key
was introduced.

## Branch and platform completeness

The changed expression is in the allocation arm of
`TypeManager::AllocTyVar`. This S2 slice changes only its construction route;
all existing selfhost branches remain in place. The C++ function has:

- one allocation/pool `if/else` at `TypeManager.cpp:2103-2120`;
- one `derivedFrom` scope `if/else` at `TypeManager.cpp:2122-2129`;
- one `needSolving` `if` at `TypeManager.cpp:2130-2133`;
- one final return at `TypeManager.cpp:2134`.

Thus the cache-routing change covers the only bare-allocation branch (1/1),
and does not omit or reorder any other branch. The complete function's three
conditionals, two `else` arms, and one return remain represented by the
pre-existing selfhost implementation.

Platform scan command:

```text
rg -n '_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif' \
  /root/cj_build/cangjie_compiler/src/Sema/TypeManager.cpp \
  /root/cj_build/cangjie_compiler/include/cangjie/Sema/TypeManager.h
```

Raw result:

```text
/root/cj_build/cangjie_compiler/include/cangjie/Sema/TypeManager.h:364:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/TypeManager.cpp:798:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/TypeManager.cpp:1981:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
```

None surrounds `GetGenericsTy` or `AllocTyVar`; this slice has no platform
branch to port.

## Verification

Command:

```text
/tmp/audit/verify.sh /root/cj_build/wt/fix_tyintern_s2b quick tyintern_s2b
```

Raw build tail and gate output:

```text
2 warnings generated, 2 warnings printed.
cjpm build success
=== VERIFY (quick) 并发阶段 ===
=== RESULTS (quick, lane=tyintern_s2b) ===
difftest: TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
smoke15: PASS=15 FAIL=0
VERIFY-EXIT=0
```

The required quick mode did not emit a bcgate summary line. Its complete
result section is reproduced above without synthesizing one.

## Required declarations

- No new symbol lacks a grepable C++ origin.
- No business source was changed to dodge the issue, and no band-aid was added to suppress a bug.
- No encountered system root was substituted; none was required by this slice.

After S2-A and this batch, zero actionable bare allocation sites remain in
the S1 inventory. TY-0068 remains the single `NO_EPHEMERAL` exempt site
because the corresponding C++ diagnostic code is also a direct temporary
construction.
