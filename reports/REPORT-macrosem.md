PROGRESS=DONE · verdict=DIAGNOSTIC_FIXED; SAMPLE_VALID; CI_SEMANTIC_IS_GC-CORRUPTED-AST · LANE=macrosem
SIDE_EFFECT: `sema_invalid_node_after_check` 现在携带校验器的具体原因，并把主标记放在无效节点（或最近源码范围）的起点；冒烟样本与共享 SDK 均未改动。

# macrosem 调查与修复报告

## 1. 先答第③问：官方/我方对照

### 官方 cjc

- 工具链：`nightly-1.2.0-alpha.20260721165458`
- 二进制：`/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458/bin/cjc`
- cwd：一份全新复制的 `ci/smoke/macro_demo/mymacros`
- 布局：使用该 cjc 相邻的官方 `runtime/lib/linux_x86_64_cjnative`，不是裸二进制。
- 命令：`cjc --compile-macro def.cj`
- 结果：`rc=0`，墙钟 `0.426 s`；产出 `lib-macro_mymacros.so`（47432 bytes）与 `mymacros.cjo`（3208 bytes）。

结论：这 12 行样本及 `macro package`、`Tokens`、`quote($input; $input)` 的写法对官方编译器是合法的；不能通过改样本来“修”本问题。

### 我方失败身份

- 用户给出的 run `31873940305` 在 ubuntu-24.04 检出的 cjcj 是 `29f9262ad5a2559c7aff00d6584ca0b71149be2c`，runtime pin 是 `597b47f106cf58dad5c71e7ededc13563640a2c3`。
- 原始结果：`rc=1`、无 signal、约 `22.108 s`，只打印 `error: semantic error`，范围终点落在 `def.cj:12:2`。
- 当前修复基线 `767d21e2fb17f484691b4dc7ba59a2ed6d6289c6` 与该 CI cjcj 提交之间，`git diff --name-status` 只有 `ci/runtime_pin.env`；编译器源码相同。pin 从 `597b47f...` 移到了 `9bc7290...`。
- 我用 runtime 源码 `597b47f...` 按 `ci/build_patched_runtime.mjs` 的 native/release 配方重建，私有副本 SHA-256 为 `6edc6e9148e423590c90c25911fe9d1a2a99b24a9f9c41d40bff2217567cf93b`；编译器以 CI 要求的 `bin/cjcj` 名称运行，且有相邻 `../runtime`。因此复测确实加载了目标 runtime，没有落入“裸二进制静默跳过宏展开”。共享 `/root/sdks/**`、`/root/.cjv/**` 没有被写入。

所以这是我方回归，不是样本错误。

## 2. 第①问：正文去哪了（独立缺陷）

这不是格式化器吞掉 message，而是诊断定义和发射点共同把 message 丢了。

### 发射链

1. 诊断表原定义位于 `packages/basic/src/DiagnosticTables.cj:2703`：

   ```cangjie
   ErrorData(message: "semantic error", mainHint: "", otherHints: [])
   ```

   模板没有 `%s`，本身就没有正文槽位。

2. 唯一发射点原位于 `packages/ast/src/ASTTypeValidator.cj:194` 附近。`validateNode` 已经生成并保存了三类具体字符串：

   - `invalid target type from ... to ...`
   - `invalid sema type on ... at ...`
   - `invalid owner type for function body at ...`

   但 `PostVisitor` 只接收 `Bool`，`emitInvalidNodeDiagnostic(node)` 也不接收/传递这些字符串。也就是说，原因在进入诊断引擎之前就被调用方丢掉了。

3. CI 输出仍正确打印了该诊断随后添加的 `please report ...` note，其他诊断也能格式化参数；这进一步排除了 renderer 吞正文。

### 为什么指向第 12 行 `}`

原发射点传入 `currentValidRange()`。它往往是整个宏声明/函数体的多行范围；主标记显示该范围的末端，于是落到收尾 `}`，不是第 12 行源码本身有错。

### 修复

- `packages/basic/src/DiagnosticTables.cj:2703` 改为 `semantic error: %s`。
- `packages/ast/src/ASTTypeValidator.cj:94-96,135-166,203-209` 让校验函数返回具体原因并传给诊断。
- `packages/ast/src/ASTTypeValidator.cj:193-200` 对有源码位置的无效节点标记其 `begin..begin+1`；合成节点没有位置时，标记最近用户源码范围的起点，不再指向范围末尾的 `}`。
- `packages/compiler_unittest/src/ASTPort_test.cj:56-78` 新增回归测试，断言正文以 `semantic error: invalid ` 开头，且范围始于第一个无效节点。

这项修复独立于本次底层 GC 故障：今后无论什么原因触发该 AST 完整性检查，都不会再只得到四个字。

## 3. 第②问：底层是什么错

### 诊断实际代表什么

`sema_invalid_node_after_check` 不是一条 Cangjie 语言规则诊断，而是 `ASTTypeValidator` 在语义分析之后做的内部完整性检查。它表示 AST 中至少有一个节点满足下列之一：

- 节点指向的 target 没有正确类型；
- 节点自身的 sema type 缺失、错误，或仍含 ideal/question type variable；
- 函数体 owner 的类型不正确。

历史 CI 那一轮究竟命中这三个 predicate 中的哪一个，已经无法从旧日志反推：旧调用点正是把唯一能区分它们的字符串丢掉了。这也是“无正文”必须单独修的原因。修补后的精确旧-runtime 复跑具有随机性，分别提前落到 SIGABRT、SIGSEGV、FlatBuffer 负索引等内存破坏表现，没有再次恰好落到 AST validator；报告不伪造一个无法恢复的具体节点名。

### 根因不是 quote/Tokens/macro package 的语义

证据链指向 CI 所绑定的旧 runtime 的 minor-GC 路径破坏了编译器进程内对象，而后 AST validator 只是较幸运地把破坏后的类型元数据截住：

- 官方 cjc 对原样源码 `rc=0`。
- 同一 cjcj 编译器源码在不发生这条 GC 破坏时能通过 sema，随后才可能遇到当前树中另一个、独立的 CHIR/codegen 问题。
- run `31873940305` 的同一 job 中已有 GC 异常计数；目标宏进程最终没有 signal，只以 AST 完整性诊断退出。
- 私有重建的精确 `597b47f...` runtime 在正确布局下，对同一源码的重复运行分别出现：

  - `CheckAndPush: TypeInfo ... has invalid type kind` + SIGABRT；
  - `ForEachBitmapWord` 的 SIGSEGV；
  - FlatBuffer 读到负索引的 `IndexOutOfBoundsException`；
  - `invalid_object_active_region` 非零。

- 该 runtime 源码提供的对照开关是 `MRT_GCV2_DISABLE_MINOR=1`（`runtime/src/Heap/Allocator/RegionManager.cpp:1440-1445`）。启用它后，原样宏在 `3.604 s` 内稳定通过 sema/AST 校验并到达后端，`invalid_object_active_region=0`；随后因本机未替换 CI 的 fixed llc 而报未知 `-cj-generational-post-barrier=true`。这个后端报错不属于本棒，但“关闭 minor 后 semantic error 消失并能走到 llc”把目标错误收窄到了 runtime minor-GC 路径。
- `597b47f...` 到当前 pin `9bc7290...` 的祖先路径包含多项 GC 修复（reclaimed-region SATB、young-region coverage、compact route table publish/reclaim 等）；当前基线提交也明确是移动该 runtime pin。

因此底层结论是：合法宏编译负载触发了旧 runtime 的 GC 内存破坏，破坏后的 sema AST 类型元数据被 `ASTTypeValidator` 报成 generic semantic error；它不是 `$input`、`Tokens` 或 `macro package` 的合法性错误。

## 4. 最小触发形

按“空体 → `quote()` → 加插值 → 复制两次”逐步缩减：

| 宏体 | 官方 cjc | 我方观察 | 结论 |
|---|---|---|---|
| `{}` | 正常的 `Unit` 与 `Tokens` mismatched-types，`rc=1` | 精确旧 runtime 也到达同一具体类型诊断 | 没有进入目标路径 |
| `{ return quote() }` | `rc=0` | 已进入旧 runtime 的 GC 腐坏/崩溃路径 | 最小负载触发形 |
| `{ return quote($input) }` | `rc=0` | 与 `quote()` 同类 | `$input` 不是必要条件 |
| `{ return quote($input; $input) }` | `rc=0` | CI 命中无正文 AST 诊断；本地旧 runtime 多种随机腐坏 | 分号与第二次 `$input` 不是必要条件 |

最小源码为：

```cangjie
macro package mymacros
import std.ast.*
public macro Twice(input: Tokens): Tokens {
    return quote()
}
```

这里的“最小触发”是触发同一高内存/GC 故障路径，不保证每轮都呈现相同的 `rc=1 semantic error`；旧 runtime 的表现本来就是随机的。`macro package`、`Tokens` 和 `import std.ast.*` 是构造一个返回 `Tokens` 的宏所需脚手架，首次新增且必要的负载是 `quote()`；插值不是必要条件。

## 5. 验证

- 定向单测：`ASTTypeValidatorDiagnosticTest`，`PASS=1, FAIL=0, SKIP=140`。
- 全 workspace：`cjpm build --incremental` 成功，末行 `cjpm build success`。
- `git diff --check` 通过。
- 官方 exact sample：`rc=0`。
- 精确 CI runtime 私有布局：确认进入 runtime；默认 minor 下重现多种 GC/内存破坏，`MRT_GCV2_DISABLE_MINOR=1` 下通过 sema/AST validator 到达 llc。
- 冒烟样本内容未改；共享 SDK 未改。

## 6. 没覆盖到什么

- 本提交修复诊断信息与定位，不修改 cangjie runtime；旧 `597b47f...` 的 GC 修复不在本仓改动范围内。
- 没有声称恢复了历史 CI 那一轮被丢弃的具体 predicate/节点名；信息在旧二进制中不可逆丢失，且精确旧 runtime 复跑未再次随机落到同一 AST-validator 终点。
- 当前 cjcj 在较新/禁 minor 环境下还可能遇到独立的 CHIR dominance 或 fixed-llc 装置问题；它们不是 run `31873940305` 的 `rc=1, signal=none, semantic error` 签名，本提交没有顺带修。
- 没跑完整 smoke matrix，也没有覆盖 macOS、Windows、AArch64；精确旧 runtime 本身会随机崩溃，不能作为可靠的全套回归环境。
- `REPORT-blamebisect2.md` 的 sticky-minor abort 位于另一段 runtime 历史，且其目标签名是 SIGABRT；本报告只借鉴装置思路，没有把它与本次无正文诊断当成同一个失败。精确 `597b47f...` 使用的控制开关是 `MRT_GCV2_DISABLE_MINOR=1`。
