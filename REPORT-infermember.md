# BLOCKED-REPORT — `InferStaticAccess` + `InferMemberAccess` family

## Status

`BLOCKED`（本轮扩容后正确停手）。没有修改 selfhost 编译器源码，也没有提前删除
`SynMemberAccess` / `PopulateMemberAccessTargets`：完整替代尚缺一个跨文件 reference-resolution
设施，先删旧路径或只接代表样本都会形成不可接受的简化平行实现。

本轮按源码顺序展开了：

```cpp
// src/Sema/TypeCheckExpr/NameReferenceExpr.cpp:585-683
void TypeChecker::TypeCheckerImpl::InferMemberAccess(ASTContext& ctx, MemberAccess& ma)

// src/Sema/TypeCheckExpr/NameReferenceExpr.cpp:728-794
void TypeChecker::TypeCheckerImpl::InferStaticAccess(
    const ASTContext& ctx, MemberAccess& ma, Decl& targetOfBaseExpr)
```

并审计了它们所需的同文件 helper。r1 的 `InferStaticAccess` 边界已被本任务扩容覆盖；其 package
诊断所需的 `SemaImportManager.GetPackageMembersByName` 也已存在于
`packages/modules/src/SemaImportManager.cj:32` 和 `ImportManager.cj:239-240`，不是 blocker。

## 下一层缺失依赖

`InferMemberAccess` 的 instance 分支调用：

```cpp
// src/Sema/TypeCheckExpr/NameReferenceExpr.cpp:796-809
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

同文件 `GetObjMemberAccessTarget`（`NameReferenceExpr.cpp:1037-1107`，71 行）在本轮 ≤80 行
族内扩容范围内，不能据此停手；但它的 Class / Interface / Struct / Enum / Array / Pointer / fallback
分支都直接依赖下面这个跨文件 named 设施：

```cpp
// src/Sema/TypeCheckReference.cpp:505-554
Ptr<Decl> TypeChecker::TypeCheckerImpl::FilterAndGetTargetsOfObjAccess(
    const ASTContext& ctx, MemberAccess& ma, std::vector<Ptr<Decl>>& targets)
```

该函数从 505 到 554 行共 50 行，位于 `TypeCheckReference.cpp`，不属于本轮
`NameReferenceExpr.cpp` 族内扩容；selfhost 全树没有同名实体：

```text
$ rg -n "FilterAndGetTargetsOfObjAccess" packages -g '*.cj'
<no matches>
```

它不是现有 `PopulateMemberAccessTargets` 或单次 `FieldLookup` 可替代的 helper。C++ 全部分支依次包含：

1. targets 为空诊断并返回；
2. `FilterTargetsInExtend` 失败诊断并返回；
3. 删除 static target，同时把函数候选写入 `ma.targets`；
4. 删除后为空时诊断 object-cannot-access-static；
5. 无 target type 的函数引用路径：空检查、accessible 集、`FilterTargetsForFuncReference`、首 target 选择；
6. 其余路径：`GetAccessibleDecl` fallback、合并 call target 状态、`CheckForQuestFuncRetType`。

恢复所需 API 为 TypeChecker 内同名同结构的：

```cangjie
private func FilterAndGetTargetsOfObjAccess(
    ctx: ASTContext, ma: MemberAccess, targets: ArrayList<Decl>): Option<Decl>
```

按任务“跨文件新子系统才 BLOCKED”和 AGENTS 唯一依赖负责人规则，本轮必须停在这里，不能把
`PopulateMemberAccessTargets` 改名或拼接现有零散过滤函数来伪装完整移植。

## 发明路径退场

`SynMemberAccess`、`PopulateMemberAccessTargets`、`PopulateMemberAccessTargetsFromUpperBounds` 在完整 C++
符号扫描中没有对应 named 实体。它们的职责只有在 `InferMemberAccess`、`InferStaticAccess`、同文件族内
helper 以及上述跨文件依赖全部可用后才能一次性收编退场。本轮未删除 load-bearing 旧路径，也未增加
`GenericStruct<Dog>(x: d).x is Dog` 特判。

## is_expr 18 样本复跑

清单 SHA-256：

```text
3ee6c2ba73fc92489695f6bff48f15e9fffd8fd7674a28d504539baa58d1ed9a  /tmp/cisexpr18.samples
```

使用当前绝对 selfhost 编译器路径、原 harness 的 `utils_utils` 链接与 import 参数逐个实际复跑，原始汇总：

```text
TOTAL=18 SIGNATURE=18 FIXED=0 REMAINING=18 OTHER=0
```

没有完整接入成员访问族，因此 18 个样本仍在 `not yet ported in faithful AST2CHIR: is_expr` 前沿，未虚报
FIXED。

## ctinvalid 冲突预案

本轮没有修改 `packages/sema/src/TypeCheckReference.cj` 或 `ResolveRefExpr`。`fix_ctinvalid` 的已有改动是
空 `RefExpr` targets 的诊断路径；本 blocker 是缺失的 object `MemberAccess` target 过滤函数。后续专门依赖
task 将落在 `TypeCheckReference.cj`，届时应先合入/重放 ctinvalid 最新提交再移植，避免同文件冲突；当前
报告提交与其无源码交点。

## 平台检查

```text
$ rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" \
    /root/cj_build/cangjie_compiler/src/Sema/TypeCheckExpr/NameReferenceExpr.cpp \
    /root/cj_build/cangjie_compiler/src/Sema/TypeCheckReference.cpp
<no matches>
```

## Gate

命令：

```text
bash /tmp/audit/verify.sh /root/cj_build/wt/fix_infermember full infermember
```

本轮重复请求在全局 gate 锁前排队超过 11 分钟，尚未获得锁；为避免继续占据已有十余任务的共享队列，
在未执行任何 gate 子步骤时中止，原始状态为：

```text
bash /tmp/audit/verify.sh /root/cj_build/wt/fix_infermember full infermember
<blocked in: flock -w 14400 9>
VERIFY-RERUN-EXIT=130
```

当前编译器源码、构建产物与 r1 `b073a2d0` 门控时完全相同（本轮唯一 diff 是本报告）；同一绝对编译器
路径的最近完整原始结束输出为：

```text
=== RESULTS (full, lane=infermember) ===
difftest: TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
smoke15: PASS=15 FAIL=0
bcgate: shared functions: 2490  |  byte-identical: 2490 (100.0%)  |  differing: 0 | fully-identical samples: 114/114  |  compile-errors: 0
VERIFY-EXIT=0
```

因此已有 gate 是绿的，但不把本轮未拿到锁的重复请求伪报成新一次完成。

构建产物：

```text
SELFHOST_SIZE=66194824
```

## 交付自检

- 本轮未新增/修改编译器函数，因此不能虚假声明主函数已完成全分支移植；阻塞函数自身已枚举全部 6 组 branch/early-return。
- 无任何 grep 不到 C++ 出处的新符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的跨文件缺失 named 设施已 BLOCKED 上报、未自行替代；未撞到缺失的系统根。
- 没有保留临时插桩、debug 输出或 dump。

恢复条件：由专门 dependency task 完整移植 `FilterAndGetTargetsOfObjAccess`
（`TypeCheckReference.cpp:505-554`）并合入；随后 resume 本 task，完成 `NameReferenceExpr.cpp` 成员访问族、
发明退场、18 样本与 full gate 验收。
