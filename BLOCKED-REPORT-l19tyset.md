# BLOCKED-REPORT: L19 TySet transaction apply

## Status

Correctly blocked on the named pointer-identity container facility required by the C++ implementation. No `.cj` compiler source is changed.

The requested transaction is not merely the indexing expression at `packages/sema/src/CommonTypeAlias.cj:209-218`. In C++, `LowerBounds`, `UpperBounds`, and `TyVarBounds::eq` are `PSet<Ptr<AST::Ty>>` (`include/cangjie/Sema/CommonTypeAlias.h:49-50,62-70`). `PSet` stores `std::set<T>` data and logs the same `T` values (`include/cangjie/Utils/PartiallyPersistent.h:343-350`), so membership, rollback, stash, and apply all preserve `Ty*` pointer identity.

Selfhost has no faithful `PSet<Ptr<AST::Ty>>` counterpart. Its generic `PSet<T>` requires `T <: Comparable<T>` (`packages/utils/src/PartiallyPersistent.cj:25`), while `Ty` has no `Comparable<Ty>` implementation. The local `TySet` substitutes `SameTy` in `Contains` and `erase` (`packages/sema/src/CommonTypeAlias.cj:129-136,246-255`). `SameTy` is semantic type comparison, not the raw `Ty*` identity used by C++. Replacing it with `objectId`, a name, or structural equality would be a locally invented pointer-identity surrogate forbidden by `AGENTS.md`.

The existing `TySet.apply` shape already mirrors the generic C++ `PSet::apply` branches at `include/cangjie/Utils/PartiallyPersistent.h:313-323`: dummy version returns, nonzero version is converted to a zero-based index, the stash size is asserted, and each saved log entry is applied. Adding a release-mode bounds check or skipping a missing version would therefore be a band-aid with no C++ source.

## Blocked target and dependency

- Target transaction: `PData::Stash(Constraint&)` and `PData::Apply(Constraint&, CstVersionID&)`, `src/Sema/Utils.cpp:615-636`.
- Direct data dependency: `LowerBounds = PSet<Ptr<AST::Ty>>`, `UpperBounds = PSet<Ptr<AST::Ty>>`, and `TyVarBounds::eq`, `include/cangjie/Sema/CommonTypeAlias.h:49-50,62-70`.
- Missing named facility: a faithful selfhost representation of `PSet<Ptr<AST::Ty>>` whose set membership, log entries, reset, stash, and apply use canonical `Ty*` identity as in `include/cangjie/Utils/PartiallyPersistent.h:290-382`.
- System-root reason: this is explicitly the prohibited `Ty*` pointer-identity root. It is not eligible for the <=40-line proportional exception because the missing identity/container facility spans the `Ty` identity model plus the persistent set and its callers, not a self-contained <=40-line helper whose prerequisites already exist.

No partial implementation was retained. The current `PData::Stash/Apply` call timing in `packages/sema/src/TypeCheckCall.cj:3791-3857` already follows C++ `src/Sema/TypeCheckCall.cpp:2037-2177`: reset each rejected candidate, stash each accepted candidate after checking, and apply the selected candidate before replaying diagnostics and reinference.

## Required restoration API

Resume L19 only after the pointer-identity owner provides an official selfhost facility equivalent to:

```text
PSet<Ptr<AST::Ty>>
  commit() -> Unit
  reset() -> Unit
  stash() -> VersionID
  apply(VersionID) -> Unit
  resetSoft() -> Unit
```

The element key must be canonical `Ty*` identity, including logged insert/erase values; it must not be `SameTy`, type names, hashes, or an L19-local ID shim. Once available, `TyVarBounds.lbs/ubs/sum/eq` can use that facility and the already-present `CstVersionID`/`PData::Stash`/`PData::Apply` flow can be revalidated against `Utils.cpp:615-640`.

## Mechanical evidence

```text
$ rg -n "using LowerBounds|using UpperBounds|PSet<Ptr<AST::Ty>>|using CstVersionID" /root/cj_build/cangjie_compiler/include/cangjie/Sema/CommonTypeAlias.h
49:using LowerBounds = PSet<Ptr<AST::Ty>>;
50:using UpperBounds = PSet<Ptr<AST::Ty>>;
70:    PSet<Ptr<AST::Ty>> eq{};
183:using CstVersionID = std::map<Ptr<TyVar>, std::tuple<VersionID, VersionID, VersionID, VersionID>>;

$ rg -n "Comparable<Ty>|extend Ty <: Comparable|class PSet" packages/ast/src packages/utils/src
packages/utils/src/PartiallyPersistent.cj:25:public class PSet<T> where T <: Comparable<T> {

$ rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" /root/cj_build/cangjie_compiler/src/Sema/Utils.cpp /root/cj_build/cangjie_compiler/include/cangjie/Sema/CommonTypeAlias.h /root/cj_build/cangjie_compiler/include/cangjie/Utils/PartiallyPersistent.h
<no matches>
```

## Branch coverage and delivery declarations

- No target function was ported, so full-branch coverage is N/A. The blocked C++ `PSet::apply` has one `if`, one early `return`, and one range loop (`PartiallyPersistent.h:313-323`); all are already present in the current selfhost shape, but its element identity is not faithful.
- `PData::Stash` has one range loop and no conditional/early-return branch; `PData::Apply` has one range loop and no conditional/early-return branch (`Utils.cpp:615-636`). Their current selfhost call ordering was audited but not modified.
- 无任何 grep 不到 C++ 出处的新符号；本报告没有新增编译器符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的系统根已 BLOCKED 上报、未自行替代。
- No temporary instrumentation or debug output was added.

## Gate

`/root/cj_build/audit_persist/verify.sh /root/cj_build/wt/fix_l19tyset delta fix_l19tyset` was invoked. It emitted no build or result line because it remained queued on `/tmp/verify_global.lock` behind more than ten other verification processes. The still-waiting process was interrupted; the tool reported `exit_code=1` with raw output `^C`. Since no validation stage started and there is no compiler-source diff, no green gate is claimed.
