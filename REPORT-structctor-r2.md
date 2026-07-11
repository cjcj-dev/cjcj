# REPORT — structctor_r2

## 结论

复审的两个 blocker 均已闭环：

1. `packages/parse/src/ParseMacro.cj` 在宏输入节点解析后恢复 constructor 判定，并调用
   `CheckConstructorBody(ctor, scopeKind, inMacro: true)`，使已移植的 `inMacro` 分支可达。
2. 下表保留全部 15 个原 `CheckCtorFuncBody` 崩溃样本的 post-fix 双侧机械证据；双方退出码和去 ANSI
   后完整诊断字节均一致。

生产源码只增加上述调用点，并将 `CheckConstructorBody` 从仓颉文件级 `private` 改为默认 internal，原因是
C++ 中它是同一 `ParserImpl` 的私有成员，可从 `ParseMacro.cpp` 调用；selfhost 的 `ParserImpl` 实现拆在
`ParseDecl.cj`/`ParseMacro.cj` 两个文件，文件级 `private` 无法表达该 C++ 可见性。

## BLOCKER-1：宏解析调用点

C++ `/root/cj_build/cangjie_compiler/src/Parse/ParseMacro.cpp:104-111`：

```cpp
if (scopeKind) {
    if (isParamMacro) {
        node = ParseParamInParamList(*scopeKind, namedParameter, memberParam);
    } else if (CheckIfSeeingDecl(*scopeKind)) {
        node = nodes.empty() ? ParseDecl(*scopeKind, modifiers, std::move(annos)) : ParseDecl(*scopeKind);
    } else {
        node = ParseExpr();
    }

    if (auto ctor = As<ASTKind::FUNC_DECL>(node.get()); ctor && ctor->TestAttr(Attribute::CONSTRUCTOR)) {
        CheckConstructorBody(*ctor, *scopeKind, true);
    }
}
```

selfhost `packages/parse/src/ParseMacro.cj` 在 `ParseParamInParamList`/`ParseDecl` 汇合后逐态对位：

```cangjie
if (let Some(ctor) <- (parsedDecl as FuncDecl)) {
    if (ctor.TestAttr(Attribute.CONSTRUCTOR)) {
        CheckConstructorBody(ctor, scopeKind, inMacro: true)
    }
}
```

`FuncDecl` cast 对位 `As<ASTKind::FUNC_DECL>`，属性判定和三个实参逐字段一致。仓颉不能在一个 `if-let`
条件中追加 C++ 的 `&&` 声明变量条件，故使用嵌套 `if`，没有增加语义分支。

全分支声明：已覆盖该 C++ constructor 调用点的全部 1 个 `if`（cast 失败、cast 成功但非 constructor、
constructor 三态）以及调用的 `inMacro=true` 实参；0 个 `case`、0 个 early-return。外围参数/声明路径
仍在同一汇合点之后检查，与 C++ 顺序一致。

平台扫描原始输出为空：

```text
$ rg -n "_WIN32|__APPLE__|__OHOS__|__linux__|#ifdef|#elif" ParseMacro.cpp
<no matches>
```

## BLOCKER-2：15 个原崩溃样本逐项 post-fix 证据

manifest 由修复前
`/root/cj_build/fix_fullconf_artifacts/self_work2/results.log.json` 中 `compile_log` 包含
`CheckCtorFuncBody` 的条目机械筛出，共 15 项。复跑命令对 official
`/root/.cjv/bin/cjc` 与绝对 selfhost
`/root/cj_build/wt/fix_structctor/target/release/bin/cjcj::cjc` 使用同一输入、
`--output-type=staticlib -o /dev/null`。`diag_sha256` 是各侧 stderr/stdout 合并输出去 ANSI 后的完整字节
SHA-256；不是首行摘要。表中 `diag` 仅供人读，判定使用 RC 与完整 hash。

| sample | off RC | self RC | official/selfhost diag_sha256 | verdict | diag |
|---|---:|---:|---|---|---|
| `a30/test_a30_03.cj` | 1 | 1 | `4342ee4e741c4b7495091e0a2012d3d88f61fb7170f70cd7d07209b383656661` | PASS | body missing |
| `a30/test_a30_04.cj` | 1 | 1 | `e47ce89ded47a391adc92eebfeb6ffccd573ae40534c1700d2d3ffb578c22934` | PASS | body missing |
| `a34/test_a34_079.cj` | 1 | 1 | `aa7d41af6f8020b69731780269963eeabbca792b6c11014a8c93be6cbc16cad5` | PASS | body missing |
| `a36/test_a36_06.cj` | 1 | 1 | `eda1954ce3cec3abce3d479aa6809d5c3021ac3af2a24c7c85a85f9db442ac17` | PASS | body missing |
| `a36/test_a36_07.cj` | 1 | 1 | `b3a3cc883a3c94050bceeca6db99c52e4aa965b73d1e3034c97586ccf263c7af` | PASS | body missing |
| `a36/test_a36_08.cj` | 1 | 1 | `3bcb9df38667409ceb0ca13e45a55e10069da78864cfa06e990f7f914d44dd68` | PASS | body missing |
| `a36/test_a36_09.cj` | 1 | 1 | `bf8922bf8085e888ecf4808783350db661e9297f7a74f8b563cea2cd694464e4` | PASS | body missing |
| `a36/test_a36_10.cj` | 1 | 1 | `98ac975dbdc79aa7f8661f9eddc863922516fd8ce9c37342576d986035d42660` | PASS | return type + body missing |
| `a36/test_a36_11.cj` | 1 | 1 | `d05914da2fd299a631ba1a470a79b29036c7e37d067f690c9b4c2e36087b40ce` | PASS | return type + body missing |
| `a36/test_a36_12.cj` | 1 | 1 | `aac9d41824d739d089d15bacb0121a2409d8015e11317f3fdcb02a89ba061856` | PASS | return type + body missing |
| `a36/test_a36_13.cj` | 1 | 1 | `fe441e5807346213ffa2e61bf5e59d335991a11c44e0ad438084358aaf8ee630` | PASS | return type + body missing |
| `a03/test_a03_030.cj` | 1 | 1 | `c287aac194df5cc6de9556a5e10867f75310a1bcbc3d09a987f6e995e32823ef` | PASS | body missing |
| `a03/test_a03_031.cj` | 1 | 1 | `f435483256f015638f45f04f81e2f9612e516f0491821c7bc6afbb6641977bca` | PASS | body missing |
| `a03/test_a03_032.cj` | 1 | 1 | `ad7d228d138fe2f746fef5d372118696a2f76578714a72439581d0fd0987d256` | PASS | body missing |
| `a03/test_a03_033.cj` | 1 | 1 | `9328a044327106ad638696e3a9d304164430d18c5f06fd464497522372db9736` | PASS | body missing |

完整相对路径前缀分别是原报告列出的三族：

- `src/tests/02_types/01_value_types/10_struct_type/02_constructors/`
- `src/tests/06_class_and_interface/01_class/02_class_members/01_constructors/`
- `src/tests/06_class_and_interface/01_class/02_class_members/02_static_initializers/`

机械汇总原始行：

```text
STRUCTCTOR_ORIGINAL_CRASH_TOTAL=15 PASS=15 MISMATCH=0
```

## quick 自证

构建原始尾行：

```text
cjpm build -m packages/parse -j 8
cjpm build success
cjpm build -m packages/cjc -j 8
cjpm build success
```

quick 原始汇总：

```text
TOTAL=114  PASS=114  MISMATCH=0  FAIL=0
```

按协同基建门策略未运行 `verify.sh` 全门。

## 交付自检

- 新调用 `CheckConstructorBody` 对位 C++ `ParserImpl::CheckConstructorBody`，签名锚
  `ParserImpl.cpp:286-304`；本次调用锚 `ParseMacro.cpp:104-111`，`FuncDecl`/constructor attr/scope/
  `inMacro=true` 均字段级一致。
- 已覆盖本次所移植 C++ 调用点的全部 1 个条件分支（仓颉语法展开为 2 个嵌套 `if`），0 case，
  0 early-return。
- 无任何 grep 不到 C++ 出处的新符号。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 本轮未撞到系统根，未自行替代。
- 本轮没有不确定的新仓颉语言特性；cast/if-let 与 named argument 均复用同包既有写法，未需查询 cj-mcp。

===END===
