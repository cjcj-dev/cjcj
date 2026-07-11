# parseloop 修复报告

## 结论

根因是 selfhost 的统一 `ParseClassLikeBody` 循环漏接 C++ class/interface/struct/extend body 每轮执行的无进展检测。错误 token `public (` 同时满足：

- `SeeingDecl()` 因 `public` 是 modifier 而返回 true，因此 `ImplementConsumeStrategy` 不消费；
- `ParseModifiers` 因 `SeeingKeywordAndOperater()` 识别 `public (` 为 contextual-keyword/operator 形态而不消费；
- selfhost body 循环没有 C++ 的 `DetectPrematureEnd()` 调用，因而再次用同一 token 调 `ParseDecl`。

修复在统一 body 循环入口接回 C++ 的 deadlock 分支：第一轮无进展置 `deadlocked=true`，第二轮由 `DetectPrematureEnd` 调 `Next()` 推进一个 token；随后按 body 种类设置 `IS_BROKEN`，走 `DiagExpectedRightDelimiter`，并返回调用者继续顶层恢复。未增加计数器、超时阈值或跳过式兜底。

## 复现与实证

代表样本：

`src/tests/02_types/01_value_types/10_struct_type/02_constructors/a02/test_a02_126.cj`

基线 30 秒原始结果：

```text
SELF_RC=124 SELF_SIZE=0
```

临时 token 插桩（已删除）跑 1 秒的原始摘要：

```text
INSTRUMENT_RC=124 LINES=63103 BYTES=2587217
PARSELOOP token={ line=60 column=5
PARSELOOP token=public line=60 column=13
PARSELOOP token=public line=60 column=13
...
```

即 1 秒内在 `public` 60:13 重复 63102 次，直接证明循环未推进。

修复后代表样本：

```text
SELF_RC=1 SELF_BYTES=1580
REF_RC=1 REF_BYTES=1580
feca75ca061b1bb3ba085db69c1598e154cd4a8bed78b2b365ae29419e7057bb  self.out
feca75ca061b1bb3ba085db69c1598e154cd4a8bed78b2b365ae29419e7057bb  ref.out
BYTE_EQUAL=0
```

`BYTE_EQUAL=0` 是 `cmp` 的成功退出码，诊断逐字相同。

## 逐符号 C++ 对照

本次没有新增函数、类、类型或字段；只修改现有 `ParserImpl.ParseClassLikeBody` 的恢复分支。

1. `DetectPrematureEnd()`

   C++ `src/Parse/ParserUtils.cpp:644-652`：

   ```cpp
   bool ParserImpl::DetectPrematureEnd()
   {
       if (deadlocked || Seeing(TokenKind::END)) {
           Next();
           return true;
       } else {
           deadlocked = true;
           return false;
       }
   }
   ```

   selfhost 已有同名同分支实现（`packages/parse/src/ParserUtils.cj:227-234`）；本次只在缺失的 body 循环调用点接线。

2. class/interface/struct body 的 broken 属性、诊断与退出

   C++ `src/Parse/ParseDecl.cpp:1089-1100`：

   ```cpp
   template <typename T> bool ParserImpl::CheckSkipRcurOrPrematureEnd(T& ret)
   {
       if (Skip(TokenKind::RCURL)) {
           ret->rightCurlPos = lastToken.Begin();
           return true;
       }
       if (DetectPrematureEnd() && !ret->TestAttr(Attribute::HAS_BROKEN)) {
           ret->EnableAttr(Attribute::IS_BROKEN);
           DiagExpectedRightDelimiter("{", ret->leftCurlPos);
           return true;
       }
       return false;
   }
   ```

   调用点分别是 `ParseClassBody`（`ParseDecl.cpp:1117-1125`）、`ParseInterfaceBody`（:1170-1175）和 `ParseStructBody`（:1593-1599）。selfhost 的统一表示据 `scopeKind` 共用一个循环，因此对 `ClassBody/InterfaceBody/StructBody` 各自设置同一 `IS_BROKEN` 属性。

3. extend body 分支

   C++ `src/Parse/Parser.cpp:532-547` 直接在 `DetectPrematureEnd()` 为真时对 `ExtendDecl` 设置 `IS_BROKEN`、调用 `DiagExpectedRightDelimiter` 并退出。本次 `ExtendDecl` 分支逐项对位。

4. `DiagExpectedRightDelimiter`

   C++ 签名与关键行为位于 `src/Parse/ParserDiag.cpp:837-846`：

   ```cpp
   void ParserImpl::DiagExpectedRightDelimiter(const std::string& del, const Position& pos)
   ```

   它用 `lastToken.End()` 发射主诊断并以 `pos` 标记左分隔符。selfhost 调用 `DiagExpectedRightDelimiter("{", leftCurl)`，字段级参数一致；代表样本最终诊断 byte-identical。

5. 提前返回前的 `ret.end = lastToken.End()`

   对位 C++ `ParseClassBody` 尾部 `ParseDecl.cpp:1156`、`ParseStructBody` 尾部 :1616-1618 及外层 `ParseExtendDecl` :1752-1755。selfhost 的统一函数直接持有 inheritable decl，故在返回前写同一 token 终点。

## 分支与平台审计

`CheckSkipRcurOrPrematureEnd` 有 3 个控制结果（来源：2 个 `if`、3 个 `return`，`ParseDecl.cpp:1091-1100`）：

1. 看到 `RCURL`：既有循环终止与 `Expect(RCURL)` 路径；
2. 无进展/END：本次补齐 `DetectPrematureEnd`、broken 属性、分隔符诊断与返回；
3. 正常有进展：继续 `ParseDecl`。

已覆盖本次对位恢复设施的全部 3 个 branch/outcome；缺失的是第 2 个，现已补齐。没有平台条件代码。机械 grep 原始输出：

```text
PLATFORM_PARSEDECL
880:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
PLATFORM_PARSERUTILS
```

`ParseDecl.cpp:880` 位于未改动的 CFunc 后端逻辑，与本次 1089-1755 的恢复路径无关；相关函数没有 `_WIN32/__APPLE__/__OHOS__/__linux__/#ifdef/#elif` 分支。

仓颉语法：本次只复用树内既有的 `if-let as`、`getOrThrow`、`EnableAttr`、early return 写法，没有不确定语言特性，未调用 cj-mcp。

## 20 样本抽测

从 FULL_CONF_SWEEP2 的 89 样本首簇按序号等距选取 20 个，覆盖 struct constructor、pattern 与 class constructor 子目录。最终原始汇总：

```text
TIMEOUT20_TOTAL=20 NO_TIMEOUT=20 EXACT_DIAG=13 DIFF=7 TIMEOUT=0
```

修复覆盖数为 20/20 不再超时；其中 13/20 与官方诊断逐字一致。满足“5+ 个代表样本不超时且诊断一致”的样本包括：

- struct a02: `test_a02_099`、`test_a02_111`、`test_a02_123`、`test_a02_126`
- struct a06: `test_a06_05`、`test_a06_10`
- struct a30: `test_a30_75`
- class a02: `test_a02_099`、`test_a02_112`、`test_a02_126`
- class a06: `test_a06_06`
- class a35: `test_a35_74`、`test_a35_80`

另 7 个样本均 self/ref RC=1、无超时，但保留既存诊断差异，本任务未以额外散弹改动扩大范围。

## Gate 原始输出

本机构建：

```text
FINAL_BUILD_RC=0
2 warnings generated, 2 warnings printed.
cjpm build success
```

quick：

```text
QUICK_FINAL_RC=0
================================================================
TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
---- gap tally (selfhost faithful-pipeline failures, ranked) ----
```

按协同门策略未运行全量 `verify.sh`。

## 交付声明

- 无任何 grep 不到 C++ 出处的新符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的系统根已 BLOCKED 上报、未自行替代（本任务未撞到系统根）。
- 临时 `PARSELOOP` 插桩已删除；`rg -n "PARSELOOP|eprintln" packages/parse/src/ParseDecl.cj` 无输出。
