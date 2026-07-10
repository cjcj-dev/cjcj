# REPORT-cfloatlit

## 结论

本任务的旧族签名已全部消失：

```text
FAMILY_TOTAL=23 SIGNATURE_FIXED=23 OLD_SIGNATURE_REMAINING=0
HARNESS_RESULTS=FAILED=18 PASSED=5
```

23 个原 `COMPILE-FAIL | IllegalArgumentException: The string does not comply with the floating point number syntax.` 样本中，5 个已端到端通过；其余 18 个已越过浮点解析根，暴露为其他既有问题（8 个 `CallExpr has no resolvedFunction`、5 个 `UnknownType`、5 个无该编译异常的 harness/runtime 失败）。本任务未扩散处理这些其他根。

族复跑原始整行：

```text
2026-07-11 04:11:09.426467: Test results: Total: 23, Passed 5, Failed 18, Errored 0, Skipped 0, Incomplete 0 (20.943s)
```

## 基线复现与根因证据

当前基线 `74d4fe37` 的最小复现是包级 Float32 常量：

```cangjie
let value: Float32 = 32.0f32

main(): Unit {
    println(value)
}
```

官方原始结果为 `OFFICIAL_RC=0`；selfhost 原始结果为：

```text
IllegalArgumentException: The string does not comply with the floating point number syntax.
 at std.convert::Float64::parse(std.core::String)(std/convert/parsable.cj:1291)
 at cjcj::chir::FaithfulAST2CHIR::TranslateLitConstant(...)(packages/chir/src/FaithfulAST2CHIR.cj:3674)
```

局部 Float32 常量不触发；包级初始化会进入 `FaithfulAST2CHIR::TranslateLitConstant` 的 Float32 分支。selfhost 把仍含合法 `f32` 后缀的完整文本交给要求整串匹配的 `Float64.parse`，而 C++ 使用允许停止于后缀的 `strtold`。

## 逐符号 C++ 对照

修改的 selfhost 实体：

```text
FaithfulAST2CHIR::TranslateLitConstant(AstLitConstExpr, AstTy)
packages/chir/src/FaithfulAST2CHIR.cj:3667
```

对应 C++ 签名与关键行：

```cpp
Ptr<LiteralValue> Translator::TranslateLitConstant(
    const AST::LitConstExpr& expr, AST::Ty& realTy)
// /root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateASTNode/TranslateLitConstExpr.cpp:12

auto stringVal = expr.stringValue;                                      // :23
stringVal.erase(std::remove(stringVal.begin(), stringVal.end(), '_'),   // :24
    stringVal.end());
double value = static_cast<float>(strtold(stringVal.c_str(), nullptr)); // :25
return builder.CreateLiteralValue<FloatLiteral>(chirTyToTrans, value);  // :26
```

selfhost 对应结构为：复制字面量文本并删除 `_`；用 `endsWith("f32")` 加切片显式表达 C `strtold(..., nullptr)` 在合法类型后缀前完成前缀转换的行为；调用现有 `Float64.parse` 后立即转 `Float32`，再升为 CHIR `FloatLiteral` 的 `Float64` 存储。没有新增函数、helper、类型或字段。

边界指数用于排除 `Option`/ERANGE band-aid。`let tooLarge: Float32 = 1.0e400f32` 的最终结果为：

```text
BOUNDARY_SELFHOST_RC=0
warning: magnitude of floating-point literal too large for type 'Float32', maximum is 3.40282347E38
```

与官方同为 rc=0 且保留同一 warning。

## 语法形态定向验证

包级 Float32 覆盖十进制后缀、下划线、指数和十六进制：

```text
FORMS_OFFICIAL_RC=0
FORMS_SELFHOST_RC=0
32.000000,12.500000,125.000000,6.000000
32.000000,12.500000,125.000000,6.000000
```

## 平台分支完整性

执行：

```text
rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" /root/cj_build/cangjie_compiler/src/CHIR/AST2CHIR/TranslateASTNode/TranslateLitConstExpr.cpp
```

原始输出为空；该 C++ 文件没有平台条件分支，因此无需新增 `@When`。

## 全分支覆盖

已审计 C++ `Translator::TranslateLitConstant(const AST::LitConstExpr&, AST::Ty&)` 的全部 8 个语义 branch/case 组：浮点 16/64/ideal、Float32、无符号整数、有符号整数、Rune、Bool、Struct、Unit/default。来源是 `TranslateLitConstExpr.cpp:15-59` 的 switch case 分组。仅 Float32 组与 C++ 不一致并被修改，其余 7 组保持现有逐分支映射。

## Gate 原始输出

构建：

```text
cjpm build success
```

权威 full verify：

```text
difftest: TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
smoke15: PASS=15 FAIL=0
bcgate: shared functions: 2490  |  byte-identical: 2490 (100.0%)  |  differing: 0 | fully-identical samples: 114/114  |  compile-errors: 0
VERIFY-EXIT=0
```

## 交付自检

- 无任何 grep 不到 C++ 出处的新符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的系统根已 BLOCKED 上报、未自行替代（本任务未撞到系统根）。
- 未留下临时插桩、调试输出或 dump。
