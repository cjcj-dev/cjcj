# BLOCKED-REPORT — Conformance faithful AST2CHIR `is_expr`

## Status

`BLOCKED`（正确停手交付）。干净基线复跑结果为 `FIXED=0`、`REMAINING=18`；本轮没有保留编译器源码改动。

阻塞原因不是 CHIR 缺少可直接移植的 `Visit(IsExpr)`。C++ AST2CHIR 没有该 overload，而是只翻译 Sema 已经降解为 `MatchExpr` 的节点。代表样本的字段级插桩证明，前三个 `is` 正常得到 `desugarExpr`，第 4 个 `GenericStruct<Dog>(x: d).x is Dog` 在进入 `DesugarIsExpr` 前已经是 `InvalidTy`，其左侧泛型字段访问也是 `InvalidTy`。C++ `DesugarIsExpr` 对这种节点按原样 early-return；随后 selfhost CHIR 才暴露 `is_expr` 未降解异常。

真正缺失的 named C++ 设施是 `TypeChecker::TypeCheckerImpl::InferMemberAccess`（`src/Sema/TypeCheckExpr/NameReferenceExpr.cpp:585-683`）。selfhost 树中没有该函数；当前 `SynMemberAccess`/`PopulateMemberAccessTargets` 是 C++ 树 grep 不到的简化路径，未覆盖 C++ 的完整实例字段解析。`InferMemberAccess` 本体约 99 行，超过比例条款的 40 行上限，因此本 task 不得顺手移植，必须由专门依赖 task 完整移植后再恢复。

## 18 样本复跑

样本从 `/tmp/fix_confsweep_refresh_self/results.log.json` 的异常签名恢复，再与 `CONF_SWEEP.tsv` 的 `official_rc=0/selfhost_rc=1/COMPILE-FAIL` 相交；另有两个相同异常但官方也失败的 DIAG-DIFF 样本，不计本族。

清单排序 SHA-256：

```text
3ee6c2ba73fc92489695f6bff48f15e9fffd8fd7674a28d504539baa58d1ed9a  /tmp/cisexpr18.samples
```

干净二进制按原 harness 的 utils 链接参数逐个编译，原始汇总行：

```text
TOTAL=18 SIGNATURE=18 FIXED=0 REMAINING=18 OTHER=0
```

样本清单：

```text
src/tests/09_generics/02_generic_constraints/a02/test_a02_01.cj
src/tests/09_generics/02_generic_constraints/a03/test_a03_01.cj
src/tests/09_generics/02_generic_constraints/a04/test_a04_01.cj
src/tests/09_generics/02_generic_constraints/a05/test_a05_01.cj
src/tests/09_generics/02_generic_constraints/a05/test_a05_02.cj
src/tests/09_generics/02_generic_constraints/a06/test_a06_01.cj
src/tests/09_generics/02_generic_constraints/a06/test_a06_02.cj
src/tests/09_generics/02_generic_constraints/a06/test_a06_03.cj
src/tests/09_generics/02_generic_constraints/a06/test_a06_04.cj
src/tests/09_generics/02_generic_constraints/a06/test_a06_05.cj
src/tests/09_generics/02_generic_constraints/a07/test_a07_01.cj
src/tests/09_generics/02_generic_constraints/a07/test_a07_02.cj
src/tests/09_generics/02_generic_constraints/a08/test_a08_01.cj
src/tests/09_generics/02_generic_constraints/a09/test_a09_01.cj
src/tests/09_generics/02_generic_constraints/a10/test_a10_01.cj
src/tests/09_generics/02_generic_constraints/a11/test_a11_01.cj
src/tests/09_generics/02_generic_constraints/a11/test_a11_02.cj
src/tests/09_generics/02_generic_constraints/a11/test_a11_03.cj
```

## 最小复现与原始证据

普通非泛型 `take(Animal() is Animal)` 可由基线 selfhost 编译；带本族形态的泛型字段访问会先产生 Invalid/Unknown 前沿。完整代表样本 `a02/test_a02_01.cj` 的临时插桩原始行：

```text
CISDBG desugar id=33 correct=true bool=true left=true isTy=true sugar=false
CISDBG made id=33 sugar=true
CISDBG desugar id=52 correct=true bool=true left=true isTy=true sugar=false
CISDBG made id=52 sugar=true
CISDBG desugar id=93 correct=true bool=true left=true isTy=true sugar=false
CISDBG made id=93 sugar=true
CISDBG desugar id=151 correct=false bool=false left=false isTy=true sugar=false
CISDBG chir id=151 compiler=false
IllegalArgumentException: not yet ported in faithful AST2CHIR: is_expr
```

源码顺序确认 `id=151` 对应代表样本第 83 行：

```text
Assert.isTrue(GenericStruct<Dog>(x: d).x is Dog)
```

这排除了 GenericInstantiation 克隆丢 `desugarExpr`：失败节点 `compiler=false`，且在 AfterTypeCheck 时已经 Invalid。

## C++ 逐符号证据与恢复 API

C++ Sema 降解入口：

```cpp
// src/Sema/Desugar/AfterTypeCheck.cpp:619-621
case ASTKind::IS_EXPR:
    DesugarIsExpr(typeManager, *StaticAs<ASTKind::IS_EXPR>(node));
    break;
```

C++ `IsExpr` 全部翻译路径：

```cpp
// src/Sema/Desugar/AfterTypeCheck/IsExpr.cpp:28-32
void DesugarIsExpr(TypeManager& typeManager, IsExpr& ie)
{
    if (!Ty::IsTyCorrect(ie.GetTy()) || !ie.GetTy()->IsBoolean() || ie.desugarExpr) {
        return;
    }
```

该函数随后在 `IsExpr.cpp:33-54` 构造两个 `MatchCase`，并把 `ie.desugarExpr` 设为 `SugarKind::IS` 的 `MatchExpr`。失败节点为 Invalid，故 C++ 的第一个 early-return 条件已足以解释为什么不能在 CHIR 下游补偿。

C++ CHIR 只沿 `desugarExpr` 前进：

```cpp
// include/cangjie/CHIR/AST2CHIR/TranslateASTNode/Translator.h:69-74
static Ptr<Value> TranslateASTNode(const AST::Node& node, Translator& trans)
{
    auto base = &node;
    auto backBlock = trans.currentBlock;
    auto nodePtr = GetDesugaredExpr(node);

// Translator.h:461-469
static const Ptr<const AST::Node> GetDesugaredExpr(const AST::Node& node)
{
    auto expr = DynamicCast<AST::Expr*>(&node);
    auto nodePtr = &node;
    while (expr != nullptr && expr->desugarExpr != nullptr) {
        nodePtr = expr->desugarExpr.get();
        expr = DynamicCast<AST::Expr*>(nodePtr);
    }
    return nodePtr;
}
```

`Translator.h:766-801` 的 overload 清单没有 `Visit(const AST::IsExpr&)`；未降解节点只会进入 `Visit(const AST::Node&)`（`802-808`）的 `CJC_ASSERT(false && "Should not reach here!")`。因此新增 selfhost `Visit(IsExpr)` 没有 C++ 出处。

缺失依赖签名及范围：

```cpp
// src/Sema/TypeCheckExpr/NameReferenceExpr.cpp:585-683
void TypeChecker::TypeCheckerImpl::InferMemberAccess(ASTContext& ctx, MemberAccess& ma)
```

该完整函数覆盖：已有有效 target early-return、typeArguments 合法性、base synthesis、built-in/static/partial-package/instance 四路分派、shadowed top-level type retry、target 缺失 return、重载延迟、`SynTargetOnUsed`、type-alias substitute、`InstantiateReferenceType`。恢复后需要 selfhost 提供同名同结构的 `InferMemberAccess(ctx, ma)`，并由 `SynthesizeNameReference` 对 `MemberAccess` 调用；不能继续依赖 C++ 无出处的 `PopulateMemberAccessTargets` 简化路径。

与 `fix_ctinvalid` 不重合：该 lane 的 `a4b2131f` 只删除 `ResolveRefExpr` 对空 targets 的提前静默返回，使其进入 `FilterAndCheckTargetsOfRef` 对应 C++ `TypeCheckReference.cpp:343-345` 的诊断；targets 为空时仍返回 false 并置 Invalid。本例是泛型构造结果的实例字段 `.x` 解析，所需 named 设施为上述 `InferMemberAccess`。

## 构建、平台与门控

清理插桩后按手册重新构建，原始结束行：

```text
linked runtime layout: /root/cj_build/wt/fix_cisexpr/target/release/runtime -> /root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029/runtime
cjpm build success
SELFHOST_SIZE=66191400
```

平台分支机械检查：

```text
$ rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" src/Sema/TypeCheckExpr/NameReferenceExpr.cpp src/Sema/Desugar/AfterTypeCheck/IsExpr.cpp include/cangjie/CHIR/AST2CHIR/TranslateASTNode/Translator.h
<no matches>
```

`bash /tmp/audit/verify.sh ... full cisexpr` 未运行：没有可保留的编译器修复，18/18 在 verify 前的 Sema 缺失依赖处稳定复现。full gate 不能授权本 lane 移植超过 40 行的共享 named 依赖，也不能把该 blocker 变绿。

## 交付自检

- 工作树没有保留临时插桩、调试输出或编译器源码 diff；仅提交本报告。
- 本轮没有新增/修改编译器函数，因此没有待声明的移植分支覆盖数。
- 无任何 grep 不到 C++ 出处的新编译器符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的缺失 named C++ 设施已 BLOCKED 上报、未自行替代。
- 未在 faithful AST2CHIR 增加 C++ 不存在的 `Visit(IsExpr)`。

恢复条件：由专门 dependency task 完整移植 `InferMemberAccess`（`NameReferenceExpr.cpp:585-683`）及其缺失依赖并合入基线；随后更新本 worktree，复跑 18 样本。此时既有 `DesugarIsExpr` 应生成 `MatchExpr`，CHIR 将自然沿 `GetDesugaredExpr` 翻译，无需新增 `IsExpr` case。
