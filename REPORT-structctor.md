# REPORT — structctor / missing constructor body

## 结论

`DIAG-DIFF | NoneValueException` 的 rank7 文本聚类不是单根族。`FULL_CONF_SWEEP2.tsv` 与原始
`results.log.json` 交叉后得到 151 条 `DIAG-DIFF + NoneValueException`（榜单聚类记 150），按第一栈帧拆成
10 个独立根；本任务指定的 struct 构造路径是其中 15 条，第一帧均为
`TypeChecker::CheckCtorFuncBody(...):2823`。

根因有上下游两个缺口：

1. parser 未移植 C++ `ParserImpl::CheckInitCtorDeclBody`，所以缺失构造器体时没有发射官方的
   `body of constructor is missing`，AST 的 `FuncBody::body` 合法地保持 null/`None`。
2. selfhost `CheckCtorFuncBody` 对 `fb.body` 直接 `getOrThrow()`；C++ 则把 nullable `fb.body.get()`
   传给 `Synthesize`，其 `PerformBasicChecksForSynthesize` 明确定义 null → `InvalidTy`。

修复补回 parser 的缺体诊断与 class/struct 属性传播，并把 sema 的 nullable synthesis 恢复为穷尽的
`Some(body) → SynthesizeBlock`、`None → InvalidTy`。这不是 `if-Some` 跳过：两个状态都有 C++ 明确语义。
抽样时另暴露同一路径缺失的 named 小设施 `ParserImpl::CheckConstructorBody`，按比例条款（实现不足 40 行、
依赖已在树）完整移植，恢复 constructor return-type 诊断。

## 族清单与最小代表

榜单锚：`/root/cj_build/reports/FULL_CONF_FAMILIES2.md:19`：

```text
| 7 | 150 | DIAG-DIFF | READY | 4 | `DIAG-DIFF | NoneValueException` | .../a30/test_a30_03.cj |
```

交叉统计原始输出：

```text
DIAG_NONE_TOTAL=151
34 sema::DeclAttributeCheckerImpl::CheckClassAttribute ... DeclAttributeChecker.cj:228
34 mangle::BaseMangler::MangleVarDecl ... BaseMangler.cj:1287
29 ast::Decl::GetMemberDeclPtrs ... DeclNodes.cj:80
22 frontend::ToCHIR::DoCFFIFuncWrapper ... CodeGenBridge.cj:359
15 sema.TypeCheckExpr::TypeChecker::CheckCtorFuncBody ... TypeChecker.cj:2823
9 sema::CheckPropDecl ... TypeCheckDecl.cj:278
5 sema.TypeCheckExpr::TypeChecker::CheckNormalFuncBody ... TypeChecker.cj:2712
1 codegen::GenerateApply ... ApplyImpl.cj:104
1 codegen::CGEnumType::CalculateSizeAndAlign ... CGEnumType.cj:530
1 chir::UpdateMemberVarPath::UpdateToField ... UpdateMemberVarPath.cj:74
```

因此没有把相同异常文本的其他 136 条误当成 structctor 同根。15 条构造路径中选取 8 个代表：

```text
src/tests/02_types/01_value_types/10_struct_type/02_constructors/a30/test_a30_03.cj
src/tests/02_types/01_value_types/10_struct_type/02_constructors/a30/test_a30_04.cj
src/tests/06_class_and_interface/01_class/02_class_members/01_constructors/a34/test_a34_079.cj
src/tests/06_class_and_interface/01_class/02_class_members/01_constructors/a36/test_a36_06.cj
src/tests/06_class_and_interface/01_class/02_class_members/01_constructors/a36/test_a36_10.cj
src/tests/06_class_and_interface/01_class/02_class_members/01_constructors/a36/test_a36_13.cj
src/tests/06_class_and_interface/01_class/02_class_members/02_static_initializers/a03/test_a03_030.cj
src/tests/06_class_and_interface/01_class/02_class_members/02_static_initializers/a03/test_a03_033.cj
```

最小复现 `a30/test_a30_03.cj` 的修复前原始栈头：

```text
An exception has occurred:
NoneValueException
 at cjcj::sema.TypeCheckExpr::TypeChecker::CheckCtorFuncBody(cjcj::ast::ASTContext, cjcj::ast::FuncBody)(/root/cj_build/wt/fix_confsweep2/packages/sema/src/TypeCheckExpr/TypeChecker.cj:2823)
 at cjcj::sema.TypeCheckExpr::TypeChecker::CheckFuncBody(cjcj::ast::ASTContext, cjcj::ast::FuncBody)(/root/cj_build/wt/fix_confsweep2/packages/sema/src/TypeCheckExpr/TypeChecker.cj:2652)
 at cjcj::sema.TypeCheckExpr::TypeChecker::SynthesizeFuncBody(cjcj::ast::ASTContext, cjcj::ast::FuncBody)(/root/cj_build/wt/fix_confsweep2/packages/sema/src/TypeCheckExpr/TypeChecker.cj:3167)
```

`FULL_CONF_SWEEP2.tsv` 中代表行原文：

```text
src/tests/02_types/01_value_types/10_struct_type/02_constructors/a30/test_a30_03.cj  1  1  DIAG-DIFF
src/tests/02_types/01_value_types/10_struct_type/02_constructors/a30/test_a30_04.cj  1  1  DIAG-DIFF
src/tests/06_class_and_interface/01_class/02_class_members/01_constructors/a36/test_a36_06.cj  1  1  DIAG-DIFF
src/tests/06_class_and_interface/01_class/02_class_members/01_constructors/a36/test_a36_10.cj  1  1  DIAG-DIFF
```

## 逐符号 C++ 贴源

### `CheckInitCtorDeclBody`

C++ `/root/cj_build/cangjie_compiler/src/Parse/ParseDecl.cpp:510-519`：

```cpp
void ParserImpl::CheckInitCtorDeclBody(FuncDecl& ctor)
{
    auto& fb = ctor.funcBody;
    if ((!fb || !fb->body) &&
        !ctor.TestAnyAttr(Attribute::COMMON, Attribute::JAVA_MIRROR, Attribute::OBJ_C_MIRROR)) {
        DiagMissingBody("constructor", "", ctor.end);
        if (!parseDeclFile) {
            ctor.EnableAttr(Attribute::HAS_BROKEN);
        }
    }
}
```

selfhost `packages/parse/src/ParseDecl.cj:826-838` 同样穷尽 `funcBody None`、`body None`，使用相同三属性门、
相同 `DiagMissingBody`、相同 `!parseDeclFile → HAS_BROKEN`。

C++ 的两个调用变体也全部接入：

- class：`ParseDecl.cpp:1125-1134`，先传播 `JAVA_MIRROR`、`OBJ_C_MIRROR`，再检查 body；
- struct：`ParseDecl.cpp:1599-1605`，先传播 `JAVA_MIRROR`，再检查 body。

selfhost 合并的 `ParseClassLikeBody` 对位于 `packages/parse/src/ParseDecl.cj:1697-1713`，检查顺序仍在
invalid-member 过滤之前，与 C++ 一致。

### `CheckConstructorBody`

C++ `/root/cj_build/cangjie_compiler/src/Parse/ParserImpl.cpp:286-304`：

```cpp
void ParserImpl::CheckConstructorBody(AST::FuncDecl& ctor, ScopeKind scopeKind, bool inMacro)
{
    CJC_ASSERT(ctor.TestAttr(Attribute::CONSTRUCTOR));
    if (ctor.funcBody && ctor.funcBody->retType) {
        ParseDiagnoseRefactor(
            DiagKindRefactor::parse_invalid_return_type, *ctor.funcBody->retType, "constructor");
        ctor.EnableAttr(Attribute::HAS_BROKEN);
    }
    auto isInClassLike = scopeKind == ScopeKind::CLASS_BODY || scopeKind == ScopeKind::STRUCT_BODY;
    if ((!isInClassLike || inMacro) && (!ctor.funcBody || !ctor.funcBody->body) &&
        !ctor.TestAttr(Attribute::COMMON)) {
        DiagMissingBody("constructor", "", ctor.end);
        ctor.EnableAttr(Attribute::HAS_BROKEN);
    }
}
```

selfhost `packages/parse/src/ParseDecl.cj:840-859` 保留 assert、return-type Node 诊断通道、`HAS_BROKEN`、
class/struct 与 `inMacro` 条件以及 `COMMON` 例外。常规构造器调用对位 C++
`ParseDecl.cpp:984-1023` 的 `:1022`，selfhost 位于 `ParseDecl.cj:2042`。

### `CheckCtorFuncBody` 的 nullable synthesis

C++ `/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:438-467` 的末行：

```cpp
void TypeChecker::TypeCheckerImpl::CheckCtorFuncBody(ASTContext& ctx, FuncBody& fb)
// ...
Synthesize({ctx, SynPos::UNUSED}, fb.body.get());
```

这里 `fb.body.get()` 是 nullable。C++ `/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:751-768`：

```cpp
std::optional<Ptr<Ty>> TypeChecker::TypeCheckerImpl::PerformBasicChecksForSynthesize(
    ASTContext& ctx, Ptr<Node> node) const
{
    if (!node) {
        return {TypeManager::GetInvalidTy()};
    }
    // ...
}
```

selfhost `packages/sema/src/TypeCheckExpr/TypeChecker.cj:2823-2826` 因现有 `SynthesizeBlock` 接收非 Option，
用穷尽 match 逐态镜像：`Some(body)` 调相同 synthesis，`None` 返回 `TypeManager.GetInvalidTy()`。

辅助调用 `CJC_ASSERT` 对位 C++ `ParserImpl.cpp:288`；`ParseDiagnoseRefactor` 使用 retType Node overload，
没有改成 range-only 通道；`DiagMissingBody` 的 Position 通道与 C++ 原调用完全相同。

## 全分支覆盖与平台扫描

- 已覆盖 C++ `CheckInitCtorDeclBody` 的全部 2 个 `if`、0 个 `case`、0 个 early-return；外层条件内的
  funcBody/body nullable、三属性排除以及内层 `parseDeclFile` 两态均对位，并覆盖全部 2 个 class/struct
  调用变体。
- 已覆盖 C++ `CheckConstructorBody` 的全部 2 个 `if`、0 个 `case`、0 个 early-return：第一个 `if`
  的 retType present/absent，以及第二个 `if` 的 class/struct scope、`inMacro`、body nullable、`COMMON`
  例外和诊断/属性路径均保留。
- 已覆盖本次变更所对位 nullable `Synthesize` 的全部 2 个 case：nonnull 与 null；没有 early-return 遗漏。

上述 N 的机械来源：

```text
sed -n '510,519p' ParseDecl.cpp | rg -o '\bif\b|\bcase\b|\breturn\b' | sort | uniq -c
      2 if
sed -n '286,304p' ParserImpl.cpp | rg -o '\bif\b|\bcase\b|\breturn\b' | sort | uniq -c
      2 if
```

平台扫描原始输出：

```text
/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:969:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:2086:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:2385:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Sema/TypeChecker.cpp:2502:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
/root/cj_build/cangjie_compiler/src/Parse/ParseDecl.cpp:880:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
```

`ParserImpl.cpp` 无命中；以上 5 个 backend 条件均不在本次对位函数内，C++ 对位函数没有 OS 平台分支，
因此无需新增 `@When`。

## 仓颉语法核查

写入前通过 cj-mcp 查询了：

1. `Option<Block>`/泛型 Option 参数与隐式包装、overload resolution；返回 0 条文档结果。实际编译证明
   `Block` 对 `Option<Block>` 的隐式包装会令同名 overload 歧义，因此没有保留自创 Option overload。
2. `if-let` 与布尔组合/`match` 穷尽 Option；返回 0 条文档结果。最终采用仓内既有 `match (option) {
   case Some(...) ... case None ... }` 同构写法，并由 parse/cjc build 验证。

## 验证

构建原始尾行：

```text
cjpm build -m packages/parse -j 8
cjpm build success
cjpm build -m packages/cjc -j 8
cjpm build success
```

15 个原崩溃样本全部复跑，另加 5 个 struct constructor 控制样本；比较官方与 selfhost 的退出码和
去 ANSI 后完整诊断文本：

```text
STRUCTCTOR_SAMPLE_TOTAL=20 PASS=20 MISMATCH=0
```

其中 `a30/test_a30_03.cj` 修复后双方均 `rc=1`，完整诊断为 `body of constructor is missing`；
`a36/test_a36_10.cj` 至 `a36/test_a36_13.cj` 双方均同时发射 return-type 与 missing-body 两条诊断。

quick 原始汇总：

```text
TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
```

按协同基建门策略未运行 `verify.sh` 全门。

## 交付声明

1. 无任何 grep 不到 C++ 出处的新符号。
2. 未改业务源码绕过、未加 band-aid 吞 bug。
3. 本轮未撞到系统根；没有自行构造替代设施。两个缺失 named parser 设施均满足 ≤40 行比例条款，
   且全部前置已在树，故已逐行忠实移植并给出锚点。

===END===
