# Mangler 规则面 1:1 静态对照审计

## 结论

本审计以 selfhost `master` 基线 `74d4fe37507022550934ab515bd0b50c5e99bdf4` 为准，只做文本对照，没有运行 `cjpm build`、编译器、自编译或 bcgate，也没有修改 `packages/`。

规则级结果见 [`MANGLE_RULE_AUDIT.tsv`](MANGLE_RULE_AUDIT.tsv)：共 101 行，`MATCH=91`、`MISSING=0`、`DIVERGENT=8`、`INVENTED=2`。这里的 `DIVERGENT` 判定从严：即使当前可构造输入上的最终字节可能相同，只要分支条件或求值顺序不是 1:1，也不记为 `MATCH`。

最值得优先核实的输出差异候选是：

1. 默认参数 helper 缺 `ownerFunc` 时，C++ 在必需指针检查处停止，selfhost 跳过 `_CPI...H` 主体并继续拼参数，可能产出残缺名。
2. local var 的包 context 查找，C++ 使用原始 `fullPackageName`，selfhost 先去掉 `$test`；同一单测包会决定是否追加 `K<index>`。
3. local var 已进入 context 但索引缺失时，C++ 停止，selfhost 会保留裸 `K` 并返回 `...KE`。
4. CHIR AutoEnv qualified-name 的拒绝条件与 generic-base 判定不是同一 API，可能在 closure type-info 名称上直接分叉。

## 审计边界和枚举方法

C++ 正向规则覆盖：

- `src/Mangle/BaseMangler.cpp` 与 `include/cangjie/Mangle/BaseMangler.h`、`MangleUtils.h`、`StdPkg.inc`
- `src/Mangle/ASTMangler.cpp` 与 `include/cangjie/Mangle/ASTMangler.h`
- `src/Mangle/CHIRMangler.cpp`
- `src/Mangle/CHIRManglingUtils.cpp`
- `src/Mangle/CHIRTypeManglingUtils.cpp` 与对应头文件常量
- `src/Mangle/Compression.cpp/.h`

selfhost 正向规则覆盖：

- `packages/mangle/src/{MangleUtils,StdPkg,BaseMangler,ASTMangler,CHIRMangler,Compression}.cj`
- descriptor/AST 桥接字段只在判断某分支输入是否等价时查阅 `ASTAdapter.cj` 与 `MangleModels.cj`
- CHIR 所有权迁移后的对应实现 `packages/chir/src/CHIRMangling.cj`

demangle 侧另行覆盖 C++ `demangler/{Utils,DeCompression,Demangler,CangjieDemangle}.{h,cpp}` 与 selfhost `packages/mangle/src/{DemangleUtils,DeCompression,Demangler,CangjieDemangle}.cj`。C++ demangler 不在 `src/Mangle/` 目录内，但 selfhost 存在对应物，因此按任务要求纳入。

TSV 的粒度是“一个可独立判断的编码/分支族一行”。大型状态机按 dispatcher、各类型分支、tree spanning、递归替换分别列行；没有把数百个纯容器/字符串适配语句伪装成独立规则。正反向逐函数入口均已落入至少一行，声明种类、修饰符、泛型、extend、操作符、特殊字符、压缩/替换和 demangle 均有独立规则行。

审计只比较规则语义；C++ assert/null-check 与仓颉 throw 的异常载体差异，在二者都停止且不产出名字时不单列 `DIVERGENT`。如果 selfhost 的缺值分支会继续并产出名字，则必列为 `DIVERGENT`。

## 8 个 DIVERGENT

### D1 默认参数 helper 缺 owner 会继续产名

C++ `BaseMangler::MangleFunctionDecl` 在 `BaseMangler.cpp:543-561` 对 `HAS_INITIAL` 无条件要求 `ownerFunc`，随后构造 `_CPI`、owner signature 与 `H`。selfhost `BaseMangler.cj:711-728` 把整个主体放进 `if (let Some(owner) <- funcDecl.ownerFunc)`；`None` 时落到 `BaseMangler.cj:733-735` 继续追加参数。

推测最小触发源码形态：

```cangjie
func f(x!: Int64 = 0): Unit {}
```

需要同时出现编译器内部异常形态：desugar 生成的 `HAS_INITIAL` helper 未回填 `ownerFunc`。这不是说普通源码必然形成该坏 AST，而是该条件差异的最小上游构造。

### D2 未知 OPERATOR 的分支条件不同

C++ `BaseMangler.cpp:599-601` 只有 `OPERATOR && map.contains(identifier)` 才进入 operator 分支；selfhost `BaseMangler.cj:755-761` 只检查 `OPERATOR`，再在分支内部对未知名字回退 `MangleName`。未知 operator 上当前输出恰好与 C++ ordinary-name 路径相同，但控制条件不是 1:1，故标红。

推测最小触发源码形态：宏或导入 AST 产生一个带 `OPERATOR` 属性、名字不在 `[] ! - ** * / % + << >> < > <= >= == != & ^ | ()` 集合内的函数，例如伪形态 `operator func ??()`；当前语法是否接纳该拼写不在本静态任务中验证。

### D3 extend 内默认参数 helper 缺 owner 的路径不同

C++ `BaseMangler.cpp:698-708` 在 `HAS_INITIAL` 分支直接读取 `ownerFunc->PRIVATE`；selfhost `BaseMangler.cj:832-850` 把缺 owner 映射为 `false`，继而选择短 `X+type`，而不是停止或生成完整 `X+type+Ufile+Kindex` extend entity。

推测最小触发源码形态：

```cangjie
extend Box {
    func f(x!: Int64 = 0): Unit {}
}
```

同样要求 desugar helper 的内部 `ownerFunc` 丢失。

### D4 generic FuncDecl 缺 funcBody 时 selfhost 静默返回无泛型后缀

C++ `BaseMangler.cpp:298-322` 的 FuncDecl generic 路径读取 `fd.funcBody->generic`；selfhost `BaseMangler.cj:1139-1151` 在 `funcBody=None` 时跳过收集，随后由 `args.isEmpty()` 返回空串。

推测最小触发源码形态：导入或宏生成的泛型函数签名（近似 `foreign func f<T>(): Unit`），其 descriptor 保留 function sema type 与 `GENERIC` 信息但缺 `funcBody`。

### D5 `$test` local-var context key 不同

C++ `BaseMangler.cpp:337-339` 用原始 `decl.fullPackageName` 查询 context；context 建立处 `BaseMangler.cpp:863-869` 却会去掉 `$test`。selfhost `BaseMangler.cj:1289-1291` 查询时也去掉 `$test`。因此对 `p$test`，C++ 可能不进入计数分支，selfhost 会进入并追加 `K<index>`。

推测最小触发源码形态：

```cangjie
// 位于测试编译生成的 p$test package
func f(): Unit {
    let x = 0
}
```

### D6 local-var 索引缺失时 selfhost 返回裸 K

C++ `BaseMangler.cpp:367-372` 要求 `GetIndexOfVar` 有值后才拼 `K<number>`；selfhost 在 `BaseMangler.cj:1290` 已先拼 `K`，但 `BaseMangler.cj:1296-1301` 的 `None` 分支为空，最终仍在 `:1305-1306` 拼 `E` 并返回。

推测最小触发源码形态：

```cangjie
func f(): Unit {
    let x = 0
}
```

需要 context collection 漏登记 `x`，或 mangling 使用的 descriptor identity 与 collection identity 不一致；结果候选为尾部 `...KE`。

### D7 AST static constructor 的替换时序不同

C++ `ASTMangler.cpp:336-345` 先追加参数，再从整个字符串尾部做固定 8 字符替换；selfhost `ASTMangler.cj:342-363` 在 `MangleOthers` 追加参数前，精确匹配 identifier+kind 后缀并改成 `<clinit>`。零参数合法静态构造器通常同结果；带编码参数的异常 AST 会不同。

推测最小触发源码形态：宏/恢复 AST 形成近似 `static init(x: Int64)` 的带参数静态构造器。当前语法是否允许该源码不在本任务中编译验证。

### D8 CHIR AutoEnv qualified-name 判定不同

C++ `CHIRTypeManglingUtils.cpp:275-300` 先拒绝 `type.IsAutoEnvInstBase()`，再以 `type.IsAutoEnvGenericBase()` 决定是否输出 `Closure<(args)->ret>`。selfhost `CHIRMangling.cj:335-359` 没有 instantiated-base 拒绝，并以 `def.GetAnnotation("IsAutoEnvGenericBase")` 判断 generic base；selfhost 自己已有对应类型 API `packages/chir/src/Type.cj:350-356`，但此处没有调用。

推测最小触发源码形态：

```cangjie
func make<T>(): (T) -> T {
    return { x: T => x }
}
```

closure conversion 生成的 abstract AutoEnv class 若以 `IsAutoEnvClass`+type args 表示、但 def 上没有名为 `IsAutoEnvGenericBase` 的 annotation，C++ 输出 closure textual form，selfhost 输出普通 `package:name<args>`；无 type args 的 instantiated base 则 C++ 拒绝而 selfhost继续普通格式化。

## MISSING 与 INVENTED

`MISSING=0`：本轮没有发现“C++ 有一个规则分支而 selfhost 完全没有对应输出路径”的项目。上面 D1/D3/D4/D8 都不是 MISSING，因为 selfhost 有相邻路径，但条件或缺值行为不同。

`INVENTED=2`：

- `packages/mangle/src/CHIRMangler.cj:28-34` 有 descriptor overload：`retTy=None` 时发出 `v`。C++ `CHIRMangler.cpp:36-42` 只有 AST `FuncTy` 路径，没有这个缺返回类型的规则输入。推测构造是手工 `MangleType` CFunc descriptor，不对应正常源码。
- `packages/mangle/src/ASTMangler.cj:264-269` 对 ExtendDecl 先调用一次写入随后丢弃的 `StringRef`，再完整重算字符串；C++ `ASTMangler.cpp:257-264` 只调用一次。这不改变最终字节，但属于 C++ 无的额外规则求值。

AST/descriptor 转换、显式 enum equality、`StringRef`/`IntRef` 等仓颉语言适配不算 INVENTED mangling 规则，因为它们自身不决定输出字节。

## `_CN14cjcj` 与模块名嵌入路径

精确文本搜索 `_CN14cjcj|CN14cjcj` 在双方实现中均无命中；这个前缀是 `_C` + `N` + 动态十进制长度 + 以 `cjcj` 开头的 package payload，不是硬编码常量。

各路径对账如下：

| 路径 | C++ | selfhost | 结论 |
|---|---|---|---|
| ABI decl package | `BaseMangler.cpp:176-198, 579-590` | `BaseMangler.cj:1010-1028, 734-744` | MATCH：首个 `::` 压成单个 `:`，再按实际长度编码；`_CN14cjcj...` 的 `14` 只由 payload 长度决定。 |
| semantic user type | `BaseMangler.cpp:238-252` | `BaseMangler.cj:1099-1119` | MATCH：复用同一 package/generic-definition 选择规则。 |
| imported generic definition | `BaseMangler.cpp:1160-1184` | `BaseMangler.cj:1601-1618` | MATCH：沿 `genericDecl`/outer chain 取定义包，不会回退写死旧模块名。 |
| AST raw signature | `ASTMangler.cpp:272-276` | `ASTMangler.cj:311-317` | MATCH：两边都直接 length-encode 构造器传入的 raw fullPackageName；这是 raw AST hash 规则，不走 BaseMangler 的 `::`→`:` 规范化。 |
| CHIR virtual extend wrapper | `CHIRManglingUtils.cpp:53-68` | `CHIRMangling.cj:377-400` | MATCH：直接嵌入 `GetPackageName().size()+GetPackageName()`；双方都动态读取重命名后的包。 |
| TypeInfo qualified name | `CHIRTypeManglingUtils.cpp:288-298` | `CHIRMangling.cj:326-358` | package `::`→`/` 规则 MATCH；AutoEnv 分支另按 D8 标红。 |
| compression/decompression | `Compression.cpp:623-681`; `demangler/DeCompression.cpp` | `Compression.cj:645-690`; `DeCompression.cj` | MATCH：只解析长度、package code 与 `_C` 前缀，不匹配具体组织名。 |
| demangle package restore | `demangler/Demangler.cpp:707-743` | `Demangler.cj:640-676` | MATCH：读动态长度并把 payload 中单个 `:` 恢复为 `::`；`cjcj` 不特殊化。 |
| CHIR prefix replacement | `CHIRManglingUtils.cpp:29-38` | `CHIRMangling.cj:60-65` | MATCH：只验证/剥离 `_C` 两字节，不假定 `_CN` 后的包内容。 |

因此，重命名后的 `cjcj` 在所有 package-bearing 路径中均来自模型字段/函数参数；没有残留 `cangjie_compiler` 或固定 `_CN14cjcj` 规则。不同 mangler 家族的 `::` 表示不同（Base ABI 为 `:`、raw AST 保留 `::`、qualified name 为 `/`），但这些差别在 C++ 与 selfhost 内部分别 1:1，不是本轮差异。

## demangle 与压缩状态机结论

- primitive、operator、std package 反向表逐项一致。特别地，编码表含 `std.ad -> aa`，而双方 demangle reverse map 都从 `ab` 开始；这是双方共同现状，记 MATCH，不是 selfhost 独有缺口。
- `Y` dictionary replacement、`U` file id、`K` counter、`L` lambda、`X` extend、`I` generic、`H` parameter/type grammar的 forward/recursive spanning/decompression 分支均有对应行。
- global init (`_CGV/_CGP/_CGF`)、default-param (`_CPI`)、inner lambda、C wrapper `$real`、virtual wrapper `_CV` 的 demangle dispatch 对应。
- 无具体 package 名白名单参与普通 length-name 解码，所以 `_CN14cjcj...` 不需要新增 demangle 特例。

## 平台/条件分支检查

对正向 C++ 源执行：

```text
/root/cj_build/cangjie_compiler/src/Mangle/BaseMangler.cpp:48:#ifdef CANGJIE_CODEGEN_CJNATIVE_BACKEND
```

这是唯一命中的正向条件编译规则，selfhost 在 `BaseMangler.cj:1709-1757` 用 `@When[backend == "cjnative"]` 与反分支完整覆盖。`demangler` 中的 `BUILD_LIB_CANGJIE_DEMANGLE` 选择字符串载体/导出实例，不改变 grammar；`Cjfilt.cpp` 的 Windows/Linux/macOS CLI I/O 不属于 selfhost mangler/demangler 规则实现。

没有 `_WIN32`、`__APPLE__`、`__OHOS__` 或 `__linux__` 正向 mangling 输出分支需要映射。

## 静态交付自检

- 机械产物：101 行规则 TSV，状态计数 `MATCH=91 MISSING=0 DIVERGENT=8 INVENTED=2`。
- 已覆盖本次枚举的 C++ mangler/demangler 全部具名输出函数及其 grammar branch；分支数来源是 TSV 中按 dispatcher/case/early-return 展开的 101 个规则族，而不是只抽主路径。
- 本提交只新增本 Markdown 与 TSV；未修改 `packages/` 或其他编译器源码。
- 无任何 grep 不到 C++ 出处的新编译器符号；文档中的 `INVENTED` 是审计结论，不是新增实现。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 未撞到需实现的系统根；本任务不做移植，也未自行替代任何缺失设施。
- 按任务硬约束没有运行任何 build/gate；因此没有伪造 `TOTAL/PASS/MISMATCH`、bcgate 或 self-compile 输出。
