# cffiwrap — frontend `DoCFFIFuncWrapper` NoneValueException

## 结论

本 lane 的 frontend 首栈根已清除。22 个修复前均以
`ToCHIR::DoCFFIFuncWrapper` 为异常首帧的样本，修复后该首帧计数为 0：

```text
CFFIWRAP_SAMPLE_TOTAL=22 PRE_FRONTEND_EXCEPTION=22 POST_FRONTEND_EXCEPTION=0 RC_MATCH=15 RC_MISMATCH=7
```

修复不是在 `CodeGenBridge.cj` 对 `Option` 做 `if-Some` 跳过。真实根因在更上游的
ClosureConversion：两条把 `Lambda` 提升为全局 `Function` 的路径都设置了
`FuncKind.LAMBDA`，但遗漏了 C++ 同点必填的 `originalLambdaInfo`。因此 CFFI wrapper 在忠实执行
`curFunc.GetOriginalLambdaType()` 时取得 `None`。本提交恢复两条 C++ 填充路径，保持 consumer 的
强不变量不变。

## 样本提取与代表

基线 verdict 来自 `/root/cj_build/reports/FULL_CONF_SWEEP2.tsv`。原 sweep 的 raw JSON 已不在任务书
记录的位置，因此以该 TSV 的 `DIAG-DIFF` 集合与 corpus 中 `CFunc<...>` 用例相交得到 26 个候选，
再用基线 selfhost 二进制逐项重放并按首栈帧精确筛选，得到 22 个 frontend 样本。完整清单及
逐样本修复前/后首帧、双方 RC 在 `cffiwrap-samples.tsv`。

用于最小化/分支覆盖的代表为：

- `a04/test_a04_01.cj`：普通捕获 lambda 提升路径，命中 `LiftLambdaToGlobalFunc`；
- `a09/test_a09_01.cj`：CFunc lambda 参数类型路径，命中 `LiftNestedFunctionWithCFuncType`；
- `a09/test_a09_16.cj`：CFunc lambda + VArray 返回类型；
- `a09/test_a09_21.cj`：复合非法 CFunc 参数；
- `varray_type/a03/test_a03_02.cj`：跨章节 VArray CFunc 返回类型。

修复前代表栈原文：

```text
An exception has occurred:
NoneValueException
    at cjcj::frontend::ToCHIR::DoCFFIFuncWrapper(...)(packages/frontend/src/CodeGenBridge.cj:360)
    at cjcj::frontend::ToCHIR::CFFIFuncWrapper()(packages/frontend/src/CodeGenBridge.cj:301)
```

## C++ 逐符号对位

### CFunc lambda 提升

C++ `ClosureConversion::LiftNestedFunctionWithCFuncType`，
`src/CHIR/Transformation/ClosureConversion.cpp:1185-1205`：

```cpp
void ClosureConversion::LiftNestedFunctionWithCFuncType(Lambda& nestedFunc)
{
    // ...
    SetLiftedLambdaAttr(*globalFunc, nestedFunc);
    auto sigInfo = FuncSigInfo{
        .funcName = nestedFunc.GetSrcCodeIdentifier(),
        .funcType = nestedFunc.GetFuncType(),
        .genericTypeParams = nestedFunc.GetGenericTypeParams()
    };
    globalFunc->SetOriginalLambdaInfo(sigInfo);
```

Selfhost `packages/chir/src/ClosureConversion.cj:1096-1108` 现在同序构造 `FuncSigInfo` 并调用
`SetOriginalLambdaInfo`。`getOrThrow` 只用于 C++ 裸指针 `nestedFunc.GetFuncType()` 的既有 selfhost
类型映射；它不是对缺失 metadata 的兜底。

### 捕获 lambda 提升

C++ `ClosureConversion::LiftLambdaToGlobalFunc`，
`src/CHIR/Transformation/ClosureConversion.cpp:1932-1967`：

```cpp
Function* ClosureConversion::LiftLambdaToGlobalFunc(/* ... */)
{
    // ...
    SetLiftedLambdaAttr(*globalFunc, nestedFunc);
    auto sigInfo = FuncSigInfo{
        .funcName = nestedFunc.GetSrcCodeIdentifier(),
        .funcType = nestedFunc.GetFuncType(),
        .genericTypeParams = nestedFunc.GetGenericTypeParams()
    };
    globalFunc->SetOriginalLambdaInfo(sigInfo);
```

Selfhost `packages/chir/src/ClosureConversion.cj:855-879` 同序填入原 lambda 的函数类型、源码名与泛型
参数，然后调用既有 `Function.SetOriginalLambdaInfo`。

新增 helper 调用 `SetOriginalLambdaInfo` 的 C++ 被调实体为
`src/CHIR/IR/Value/Value.cpp:1206-1210`：

```cpp
void Function::SetOriginalLambdaInfo(const FuncSigInfo& info)
{
    CJC_ASSERT(funcKind == FuncKind::LAMBDA);
    originalLambdaInfo = info;
}
```

调用顺序也一致：两侧均先 `SetLiftedLambdaAttr` 将 kind 设为 `LAMBDA`，再写 metadata。

## 分支与平台审计

本次恢复的是两个 C++ 函数内各一段连续、无条件的 metadata 填充块；两块各有 0 个
branch/case/early-return。两条 producer 路径全部覆盖：普通捕获 lambda 与 CFunc lambda，没有
第三条同类 `SetLiftedLambdaAttr` 后缺失 metadata 的路径。

平台 grep 原始输出为空：

```text
$ rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" src/CHIR/Transformation/ClosureConversion.cpp
<no output>
```

未使用不确定的仓颉语法；新增代码只复用同包既有 `FuncSigInfo` 构造和
`SetOriginalLambdaInfo` 调用形式，因此未触发 cj-mcp 查询。

## 定向双侧结果

官方与修复后 selfhost 均由 Conformance harness 对 22 个样本逐项重放。原始整行：

```text
official: Test results: Total: 22, Passed 22, Failed 0, Errored 0, Skipped 0, Incomplete 0 (14.003s)
selfhost: Test results: Total: 22, Passed 15, Failed 7, Errored 0, Skipped 0, Incomplete 0 (39.771s)
CFFIWRAP_SAMPLE_TOTAL=22 PRE_FRONTEND_EXCEPTION=22 POST_FRONTEND_EXCEPTION=0 RC_MATCH=15 RC_MISMATCH=7
```

7 个 RC mismatch 与其余诊断文本差异没有被本 lane 冒充为已修：这些非法 CFunc 样本在官方的
前置 sema 诊断点停止，而 selfhost 仍缺对应的 CType/VArray 诊断，属于 frontend 首栈消失后暴露的
后续独立根。本提交没有在 CHIR/downstream 补偿这些诊断，也没有扩大范围。

## Build 与 quick

完整 selfhost build 原始终行及产物：

```text
cjpm build success
SELFHOST_SIZE=84461272
Cangjie Compiler: 1.2.0-alpha.20260619020029 (cjnative)
Target: x86_64-unknown-linux-gnu
```

quick 原始整行：

```text
TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
```

按协同门策略未运行 `verify.sh` 全门。

## 交付自检

- 已覆盖本次移植的两个无条件 metadata 填充块全部 0 个 branch/case/early-return，并覆盖两条 producer 路径。
- 无任何 grep 不到 C++ 出处的新符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的系统根已 BLOCKED 上报、未自行替代；本 lane 未撞到系统根。
- 无临时插桩、调试输出或 dump 留在生产源码。

===END===
