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
2026-07-11 09:20:55,498:[INFO]: Test results: Total: 23, Passed 5, Failed 18, Errored 0, Skipped 0, Incomplete 0 (71.835s)
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

包级初始化会进入 `FaithfulAST2CHIR::TranslateLitConstant` 的 Float32 分支。被拒实现先切掉 `f32` 后缀，再执行 `Float64.parse -> Float32 -> Float64`；C++ 则执行 `strtold -> float -> double`。前者先舍入到 binary64 后再次窄化，在 Float32 中点附近会发生可观测双舍入。

## 逐符号 C++ 对照

修改的 selfhost 实体：

```text
FaithfulAST2CHIR::TranslateLitConstant(AstLitConstExpr, AstTy)
packages/chir/src/FaithfulAST2CHIR.cj:3678

FaithfulAST2CHIR::TranslateLiteralValue(AstLitConstExpr)
packages/chir/src/FaithfulAST2CHIR.cj:3653

Translator::TranslateLitConstant(AstLitConstExpr)
packages/chir/src/Translator.cj:8092
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

第二个 C++ 重载及其关键行：

```cpp
Ptr<Constant> Translator::TranslateLitConstant(
    const AST::LitConstExpr& expr, AST::Ty& realTy, Ptr<Block> block)
// TranslateLitConstExpr.cpp:63

auto stringVal = expr.stringValue;                                      // :78
stringVal.erase(std::remove(stringVal.begin(), stringVal.end(), '_'),   // :79
    stringVal.end());
double value = static_cast<float>(strtold(stringVal.c_str(), nullptr)); // :80
return CreateAndAppendConstantExpression<FloatLiteral>(                 // :81
    loc, chirTyToTrans, *block, value);
```

runtime shim 逐表达式镜像这两个重载的共同转换：

```cpp
extern "C" double CJSelfhostStrtoldToFloat32(const char *Value)
// runtime_shim/cjselfhost_llvmshim.cpp:131
{
    return static_cast<float>(strtold(Value, nullptr)); // :133
}
```

selfhost 三个入口均复制文本并删除 `_`，把完整文本（包括合法 `f32` 后缀）交给 shim；`strtold(..., nullptr)` 自然在后缀前停止。shim 内先由 `strtold` 产生 `long double`，只窄化一次到 C++ `float`，再无损提升为 FFI `Float64`/CHIR `FloatLiteral` 存储。没有仓颉十进制转换器、后缀启发式或 `Float64.parse` 中间舍入。

`FaithfulAST2CHIR::TranslateLiteralValue` 是 imported literal 重放入口；其 C++ 对照在 `GlobalVarInitializer.cpp:887-892`，其中 `Translator::TranslateASTNode(*vd->initializer, trans)` 委托到 `Translator::Visit(LitConstExpr)`，最终调用上述 block 重载。因此该入口使用同一 shim，不是平行解析实现。

边界指数用于排除 `Option`/ERANGE band-aid。`let tooLarge: Float32 = 1.0e400f32` 的最终结果为：

```text
BOUNDARY_SELFHOST_RC=0
warning: magnitude of floating-point literal too large for type 'Float32', maximum is 3.40282347E38
```

与官方同为 rc=0 且保留同一 warning。

## 双舍入边界自证

审稿反例：

```cangjie
1.000000059604644776257986737988403547205962240695953369140625f32
```

这是 Float32 中点 `1 + 2^-24` 再加 `2^-60`。分别作为包级和局部变量编译并输出 `Float32.toBits()`；最终原始结果为：

```text
GLOBAL_DOUBLE_ROUND_OFFICIAL_COMPILE_RC=0
GLOBAL_DOUBLE_ROUND_SELFHOST_COMPILE_RC=0
GLOBAL_DOUBLE_ROUND_OFFICIAL_BITS=1065353217
GLOBAL_DOUBLE_ROUND_SELFHOST_BITS=1065353217
LOCAL_DOUBLE_ROUND_OFFICIAL_COMPILE_RC=0
LOCAL_DOUBLE_ROUND_SELFHOST_COMPILE_RC=0
LOCAL_DOUBLE_ROUND_OFFICIAL_BITS=1065353217
LOCAL_DOUBLE_ROUND_SELFHOST_BITS=1065353217
```

`1065353217 == 0x3f800001`。被拒实现的局部路径实测曾输出 `1065353216 == 0x3f800000`；最终包级和局部路径都与 C++ 一次窄化一致。

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

runtime shim 新增段也不含 `_WIN32`、`__APPLE__`、`__OHOS__`、`__linux__`、`#ifdef` 或 `#elif`；使用标准 C `strtold` 和 C++ `float`/`double` 转换，没有平台分支可遗漏。

## 全分支覆盖

已覆盖 C++ `Translator::TranslateLitConstant(const AST::LitConstExpr&, AST::Ty&)` 的全部 8 个语义 branch/case/early-return 组：来源是 `TranslateLitConstExpr.cpp:15-59` 的浮点 16/64/ideal、Float32、无符号整数、有符号整数、Rune、Bool、Struct、Unit/default 分组。

已覆盖 C++ `Translator::TranslateLitConstant(const AST::LitConstExpr&, AST::Ty&, Ptr<Block>)` 的全部 9 个语义 branch/case/early-return 组：来源是 `TranslateLitConstExpr.cpp:67-117` 的 Unit、浮点 16/64/ideal、Float32、无符号整数、有符号整数、Rune、Bool、Struct、default 分组。两个重载都只修改不一致的 Float32 组，其余组保持现有映射。

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

- 无任何 grep 不到 C++ 出处的新语义符号；唯一新增的 `CJSelfhostStrtoldToFloat32` 是任务明确要求的 C ABI 包装名，其函数体逐表达式对应 `TranslateLitConstExpr.cpp:25,80`。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的系统根已 BLOCKED 上报、未自行替代（本任务未撞到系统根）。
- 未留下临时插桩、调试输出或 dump。
