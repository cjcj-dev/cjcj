# BLOCKED-REPORT — faithful `InferMemberAccess` dependency boundary

## Status

`BLOCKED`（按比例条款正确停手）。本轮没有修改 selfhost 编译器源码，也没有删除现有
`SynMemberAccess` / `PopulateMemberAccessTargets`：完整替代尚不能编译时先删旧路径会制造回归，先保留
一份只覆盖代表样本的 `InferMemberAccess` 又会成为被禁止的简化平行实现。

正在移植的 named C++ 实体是：

```cpp
// /root/cj_build/cangjie_compiler/src/Sema/TypeCheckExpr/NameReferenceExpr.cpp:585
void TypeChecker::TypeCheckerImpl::InferMemberAccess(ASTContext& ctx, MemberAccess& ma)
```

该函数当前为 `NameReferenceExpr.cpp:585-683`，覆盖已有有效 target early-return、type argument
合成失败、base 缺失、built-in/static/partial-package/instance 四路分派、shadowed top-level type retry、
target 缺失、重载延迟、`SynTargetOnUsed`、type-alias substitute、`InstantiateReferenceType`。

## 第一个缺失的 >40 行直接依赖

按 `InferMemberAccess` 的源码顺序检查到静态访问分支时，selfhost 全树没有 named 实体
`InferStaticAccess`：

```cpp
// /root/cj_build/cangjie_compiler/src/Sema/TypeCheckExpr/NameReferenceExpr.cpp:728-794
void TypeChecker::TypeCheckerImpl::InferStaticAccess(
    const ASTContext& ctx, MemberAccess& ma, Decl& targetOfBaseExpr)
```

函数从 728 到 794 行（含签名/花括号）共 67 行，超过比例条款的 40 行上限。它不是可用现有
`ResolvePrimitiveStaticMemberAccess` 替代的设施：C++ `InferStaticAccess` 同时包含真实类型/包字段查找、
package macro 过滤及诊断、`FilterAndCheckTargetsOfNameAccess`、accessible target 选择，以及 generic-param
的 `GetMemberAccessExposedTarget(..., true)` 分支。恢复所需 API 为 TypeChecker 内同名同结构的：

```cangjie
private func InferStaticAccess(ctx: ASTContext, ma: MemberAccess, targetOfBaseExpr: Decl): Unit
```

应由单独依赖 task 完整移植 `NameReferenceExpr.cpp:728-794` 后再 resume 本 task。

机械缺失检查：

```text
$ rg -n "InferStaticAccess" packages -g '*.cj'
<no matches>
```

## 已确认的后续实例路径依赖

代表样本所走的实例分支在 C++ 中不是直接 `FieldLookup`，而是：

```cpp
// NameReferenceExpr.cpp:796-809
void TypeChecker::TypeCheckerImpl::InferInstanceAccess(const ASTContext& ctx, MemberAccess& ma)
{
    // ... InitialTy early return and InvalidTy initialization ...
    Ptr<Decl> target = GetObjMemberAccessTarget(ctx, ma, *baseExpr->GetTy());
    if (!target) {
        return;
    }
    ReplaceTarget(&ma, target);
}
```

其中 `InferInstanceAccess` 自身只有 14 行，未超过 40 行；但其前置 `GetObjMemberAccessTarget` 在
selfhost 也完全缺失：

```cpp
// NameReferenceExpr.cpp:1037-1107
Ptr<Decl> TypeChecker::TypeCheckerImpl::GetObjMemberAccessTarget(
    const ASTContext& ctx, MemberAccess& ma, Ty& baseExprTy)
```

该函数共 71 行，包含 Class / Interface / Struct / Enum / Array / VArray / Pointer / Generics / fallback
九个 type dispatch 分支；Generics 分支还忠实维护 placeholder constraint upper bounds，并调用
`GetMemberAccessExposedTarget`。因此不能把当前 `PopulateMemberAccessTargets` 的 class-like lookup 当作它的
实现。恢复实例路径需要同名 API：

```cangjie
private func GetObjMemberAccessTarget(ctx: ASTContext, ma: MemberAccess, baseExprTy: Ty): Option<Decl>
```

机械缺失检查：

```text
$ rg -n "GetObjMemberAccessTarget" packages -g '*.cj'
<no matches>
```

按 DFS 唯一负责人规则，本报告以源码顺序遇到的第一个 blocker `InferStaticAccess` 为恢复条件；上面的
`GetObjMemberAccessTarget` 是为 orchestrator 预告的下一层边界，不在本轮自行移植。

## 发明路径退场与代表样本

`SynMemberAccess`、`PopulateMemberAccessTargets`、`PopulateMemberAccessTargetsFromUpperBounds` 在完整 C++
符号扫描中均无对应 named 实体。它们覆盖的职责必须等 `InferMemberAccess` 及其 named 依赖完整落地后，
在独立 commit 中收编删除。本轮没有把这些函数改名冒充 C++ 实体，也没有仅为
`GenericStruct<Dog>(x: d).x is Dog` 增加特判。

因此 is_expr 18 样本没有宣称 FIXED，也没有复跑：编译器语义未改变，基线已记录的原始结果仍是
`TOTAL=18 SIGNATURE=18 FIXED=0 REMAINING=18 OTHER=0`。resume 条件满足后必须重跑 SHA-256 为
`3ee6c2ba73fc92489695f6bff48f15e9fffd8fd7674a28d504539baa58d1ed9a` 的同一清单。

## 冲突与平台检查

本轮未改 `TypeCheckReference.cpp` 系 `ResolveRefExpr` 函数，与 `fix_ctinvalid` 的已合入改动没有直接交点。

```text
$ rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" \
    /root/cj_build/cangjie_compiler/src/Sema/TypeCheckExpr/NameReferenceExpr.cpp
<no matches>
```

## Gate

命令：

```text
bash /tmp/audit/verify.sh /root/cj_build/wt/fix_infermember full infermember
```

原始结束输出：

```text
=== RESULTS (full, lane=infermember) ===
difftest: TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
smoke15: PASS=15 FAIL=0
bcgate: shared functions: 2490  |  byte-identical: 2490 (100.0%)  |  differing: 0 | fully-identical samples: 114/114  |  compile-errors: 0
VERIFY-EXIT=0
```

构建产物机械检查：

```text
$ stat -c 'SELFHOST_SIZE=%s' target/release/bin/cjcj::cjc
SELFHOST_SIZE=66194824
```

## 交付自检

- 本轮未新增/修改编译器函数，故不能虚假声明已覆盖 `InferMemberAccess` 的全部分支；完整覆盖等待依赖恢复。
- 无任何 grep 不到 C++ 出处的新编译器符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的缺失 named C++ 设施已 BLOCKED 上报、未自行替代。
- 没有保留临时插桩、debug 输出或 dump。

恢复条件：专门 dependency task 完整移植 `InferStaticAccess`（`NameReferenceExpr.cpp:728-794`）并合入；
随后 resume 本 task，继续按 DFS 检查/移植 `InferMemberAccess` 的其余 named 依赖。完整替代可用后，再以
独立 commit 删除发明路径并执行 full gate 与 18 样本验收。
