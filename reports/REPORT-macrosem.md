PROGRESS=DONE · verdict=新 pin 的单次 CI package 通过已知，但本棒未执行要求的 N≥8；四刀定位与 macro/app 崩点重算均未开始 · LANE=macrosem
SIDE_EFFECT: 已提交的产品改动只增强 `sema_invalid_node_after_check` 的正文与落点；未改冒烟样本、未降级诊断、未写共享 SDK。
DELIVERY_REF=cjcj|fix/macrosem|cf4773c5ee4ede7b2ee5ce55aad092810d4143b0

# macrosem 停棒报告

## ① 我确定的

以下显式区分 `read`、`measured`、`provided` 与 `inferred`；`provided` 是主控给出的 CI 数据，本棒没有再次联网打开该 run。

### 无正文诊断

- **read** — `packages/basic/src/DiagnosticTables.cj:2703` 原模板是固定字符串 `semantic error`，没有参数槽；已提交版本为 `semantic error: %s`。
- **read** — `packages/ast/src/ASTTypeValidator.cj:135-166` 会生成三类具体原因：invalid target type、invalid sema type、invalid function-body owner type。
- **read** — 原 `packages/ast/src/ASTTypeValidator.cj:94-96,203-209` 调用链只传 Bool/Node，不传上述字符串；因此原因在进入 renderer 前被丢弃，不是 renderer 吞字。
- **read** — 原发射点使用整个 `currentValidRange()`；已提交版本在 `packages/ast/src/ASTTypeValidator.cj:193-207` 改为无效节点 `begin..begin+1`，合成节点则用最近源码范围的起点。这解释旧输出为什么落到多行宏声明末端 `def.cj:12:2`。
- **measured** — 定向测试 `packages/compiler_unittest/src/ASTPort_test.cj:56-78`：`PASSED=1, FAILED=0, SKIPPED=140`；全 workspace 构建末行是 `cjpm build success`。
- **certain limitation** — run `31873940305` 当时具体命中 AST validator 三个 predicate 中哪一个不可从旧日志恢复；被丢掉的字符串是唯一区分信息。

### 样本合法性与旧 pin

- **measured** — 官方 `/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458/bin/cjc` 在正确相邻 runtime 布局下，对原样 12 行 `def.cj` 运行 `--compile-macro`：`1/1` 通过，`rc=0`，墙钟 `0.426 s`；产物为 `lib-macro_mymacros.so` 47432 bytes、`mymacros.cjo` 3208 bytes。
- **read** — 旧 CI cjcj 提交 `29f9262ad5a2559c7aff00d6584ca0b71149be2c` 到修复基线 `767d21e2fb17f484691b4dc7ba59a2ed6d6289c6` 的源码差异只有 `ci/runtime_pin.env:1`：`597b47f106cf58dad5c71e7ededc13563640a2c3` → `9bc72903517fd643d2e1c9cab18aa35aa31d7e75`。
- **measured** — 私有重建的旧 `597b47f...` SO SHA-256 为 `6edc6e9148e423590c90c25911fe9d1a2a99b24a9f9c41d40bff2217567cf93b`；它放在 `<private>/runtime/lib/linux_x86_64_cjnative`，编译器复制为 `<private>/bin/cjcj`，所以确实进入进程内 runtime，不是缺 `../runtime` 的静默跳过。
- **measured** — 旧 SO + 原样宏的多轮表现不稳定：至少观察到 `SIGABRT`（invalid TypeInfo）、`SIGSEGV`（`ForEachBitmapWord`）、FlatBuffer 负索引，以及走到 llc；这不是一个稳定的源码语义错误。
- **read** — 旧 runtime 源码 `/tmp/macrosem-runtime-597.6KPh9A/runtime/src/Heap/Allocator/RegionManager.cpp:1440-1445` 的对照开关是 `MRT_GCV2_DISABLE_MINOR=1`。
- **measured** — 原样宏在旧 SO 上加 `MRT_GCV2_DISABLE_MINOR=1`：`1/1` 在 `3.604 s` 内通过 sema/AST validator 到达 llc，`invalid_object_active_region=0`；随后因本机 SDK 的 llc 不认识 `-cj-generational-post-barrier=true` 而失败。这个 arm 证明“关闭 minor 后旧 semantic 终点消失”，但不等于已经定位到新 pin 四刀中的某一刀。
- **measured** — 最小化：空宏体在旧 SO 上 `1/1` 到达正常 `Unit`→`Tokens` mismatched-types（`15.436 s`）；加入最小 `return quote()` 后 `1/1` 进入 GC/SIGSEGV 路径。`$input` 与第二次展开不是触发该负载所必需。
- **inferred（证据较强，但不是四刀二分结果）** — 旧 run 的 generic semantic error 是 GC 破坏后的 AST 类型完整性报警，而不是 `quote`/`Tokens`/`macro package` 的语言规则错误。依据是官方通过、旧 SO 多形态内存破坏、禁 minor 后越过 AST validator。

### 新 pin 与新失败

- **provided, not independently re-read** — 主控给出的 CI run `31882945821`：runtime pin `9bc72903`；03_closures、04_iface_enum、06_macro/package 均通过，06_macro/app 以 SIGSEGV 失败，总计 `pass=5 fail=1`。
- **provided raw numbers** — 新 app 失败：`rc=1`、`signal=SIGSEGV`、`ms=40978`、`pc=0x558c7989fc4c`、`fa=0x7f9be27ffdb0`、`si_addr=0x7f9cb95d4fe8`、`si_code=SEGV_MAPERR`。
- **certain semantics of fields** — `fa` 在该 GCLOG 格式中是 frame address/RBP，不是 fault address；真正需和指令寻址式核对的是 `si_addr`。
- **not established** — 本棒尚无新 pin 的本地 N≥8 数据，不能把新 CI 的单次 package 通过改写为“已修复”或“概率为零”。

## ② 我做到哪一步了

### 已提交产品改动

- 分支：`fix/macrosem`
- 产品提交：`cf4773c5ee4ede7b2ee5ce55aad092810d4143b0`
- 作者/提交者：`Zxilly <zxilly@outlook.com>`
- 改动：`packages/basic/src/DiagnosticTables.cj:2703`、`packages/ast/src/ASTTypeValidator.cj:94-207`、`packages/compiler_unittest/src/ASTPort_test.cj:56-78`。
- 状态：诊断修复与回归测试完整，不是半成品；它不声称修复 runtime GC 或新的 macro/app SIGSEGV。

### 已有装置与产物

- 修补后 cjcj：`target/release/bin/cjcj::cjc`；曾复制到 `/tmp/macrosem-layout.oMlTtA/bin/cjcj`，该副本 SHA-256 为 `259cbcb7deb5f857b94ff6676b7a8115951551c3499ff8b90736c2c3d129481d`。
- 旧 pin runtime：`/tmp/macrosem-runtime-597.6KPh9A/runtime/output/temp/lib/x86_64_Release/libcangjie-runtime.so`，SHA-256 `6edc6e9148e423590c90c25911fe9d1a2a99b24a9f9c41d40bff2217567cf93b`。
- 旧 pin boundscheck：同目录 `libboundscheck.so`，SHA-256 `5e589a81b328ef0253d92fd453b0ce76ac00e35184aa28b7aa8813918185cc14`。
- 当前 `/tmp/macrosem-layout.oMlTtA` 已被钉回旧 `597b47f...` SO；不要把它误当新 pin 装置。
- 一个此前已构建但尚未接入 N≥8 装置的新 pin 候选存在于 `/tmp/macrosem-runtime.vQrtxe/product/libcangjie-runtime.so`，最后一次只读检查显示 21570144 bytes；本棒没有计算/记录其 SHA，也没有重新核对 SOURCE_SHA。

### 已跑的臂与数量

| arm | 次数 | 结果 |
|---|---:|---|
| 官方 cjc + 原样 package | 1 | `1/1 rc=0` |
| 旧 `597b47f...` + 空宏体 | 1 | 正常 mismatched-types |
| 旧 `597b47f...` + `quote()` | 1 | SIGSEGV/GC 路径 |
| 旧 `597b47f...` + 原样 package、正常日志 | 2 | 1 次 SIGABRT，1 次 SIGSEGV |
| 旧 `597b47f...` + 原样 package、`MRT_LOG_LEVEL=f` | 至少 3 | FlatBuffer 负索引或走到 llc；未再次命中 semantic 文本 |
| 旧 `597b47f...` + `MRT_GCV2_DISABLE_MINOR=1` | 1 | 通过 sema/AST 到 llc，`3.604 s` |
| 新 `9bc72903` + 原样 package、本地概率测量 | **0/8 已跑** | **尚未开始** |
| 四刀父/子 runtime 边界 | 0 | 尚未构建 |
| 新 pin macro/app 本地复现 | 0 | 尚无 core、寄存器或崩点指令 |

## ③ 下一步该做什么

必须保持顺序；不要先跳到 app。

### A. 先完成新 pin package 的 N≥8

1. 只读核验 `/tmp/macrosem-runtime.vQrtxe/product/` 的 `SOURCE_SHA`（若有）并对 `libcangjie-runtime.so` 执行 `sha256sum`；必须得到完整 `9bc72903517fd643d2e1c9cab18aa35aa31d7e75` 身份，否则按 `ci/build_patched_runtime.mjs:main` 的 native/release 配方重建。
2. 新建另一个私有目录，不复用当前已钉旧 SO 的 `/tmp/macrosem-layout.oMlTtA`。布局必须是 `<layout>/bin/cjcj` 与 `<layout>/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so`；复制 SDK runtime 其余库，禁止写 `/root/.cjv/**`。
3. 按 `.github/workflows/ci.yml:172-178` 使用进程名 `cjcj`，并给私有工具链装入 CI 的 fixed `llc/opt`；否则 package 走到后端会被本机 stock llc 的未知 `-cj-generational-post-barrier=true` 干扰。
4. 每轮复制全新的 `ci/smoke/macro_demo/mymacros/def.cj` 到独立目录，cwd 为该目录，执行：

   ```sh
   env CANGJIE_HOME=<private-sdk> \
     LD_LIBRARY_PATH=<layout>/runtime/lib/linux_x86_64_cjnative:<private-sdk>/third_party/llvm/lib:<private-sdk>/tools/lib \
     <layout>/bin/cjcj --compile-macro def.cj
   ```

5. 连跑至少 8 次，逐轮记录 `run, rc, signal, ms, stderr_signature, runtime_sha, cjcj_sha`。判据只能是 `8/8 rc=0`；任何一轮出现 semantic/error/signal 都判“仍复现”。

### B. 仅在 A 为 8/8 后定位四刀

1. 先用以下只读命令固定四个 merge 的父链与顺序，避免凭主题猜父提交：

   ```sh
   git -C /root/cj_build/cangjie_runtime show -s --format='%H %P %s' \
     5897434f 7d106625 0b904b5e 9bc72903
   ```

2. 对 whopush、regcover、freeregion/SATB、routetbl2 的每个“父 → 子”边界，分别按 `ci/build_patched_runtime.mjs` 构建私有 SO，记录完整 commit 与 SO SHA-256；不要改共享 SDK。
3. 使用 A 的同一 cjcj、fixed LLVM、8 轮脚本测边界。第一个从“至少一轮失败”变成 `8/8 package rc=0` 的提交才是候选刀；候选的父/子再各复跑一组确认概率窗口没有漂移。

### C. 最后处理 06_macro/app

1. 先用 A 确认过的 package 产物，再按 `ci/smoke/run_smoke.mjs:259` 后续调用编 app：cwd=`ci/smoke/macro_demo/app` 的新复制目录，参数为 `main.cj --import-path <macroBuild> -o <app>`。
2. 用同一私有 `9bc72903` runtime、进程名和 fixed LLVM 跑到 SIGSEGV；保存完整 stderr 与 core。若 core 不可靠，直接批处理 gdb：

   ```sh
   gdb -q -batch \
     -ex 'set pagination off' \
     -ex run \
     -ex 'printf "PC=%p\n", $pc' \
     -ex 'info registers' \
     -ex 'x/12i $pc-24' \
     -ex 'p/x $_siginfo._sifields._sigfault.si_addr' \
     --args <layout>/bin/cjcj main.cj --import-path <macroBuild> -o <app>
   ```

3. 对实际崩点指令逐项重算有效地址。例如 `disp(base,index,scale)` 必须写出 `base + index*scale + disp = ...`，再与 gdb 的 `si_addr` 比较；不能拿 `fa` 当基址，也不能仅凭 `si_addr` 外形分族。
4. 用 `info symbol $pc`、`info proc mappings`/模块基址和 `addr2line -Cfipe <binary-or-so> <module-relative-pc>` 固定函数与 `file:line`，然后才判断是编译器、宏动态库还是 runtime 访问。

## ④ 没覆盖到什么 + 我怀疑但没验的

- **未覆盖** — 新 pin 本地 N≥8：当前是 `0/8`，所以“旧 semantic 已消失”尚未达到用户给定判据。
- **未覆盖** — 四刀二分：四个父/子 SO 均未在本棒构建或测量，不能回答是哪一刀。
- **未覆盖** — 新 CI run `31882945821` 没有由本棒再次打开；表格和崩溃数字来自主控输入。
- **未覆盖** — `06_macro/app` 没有本地复现，没有崩点机器指令、通用寄存器、模块映射或 core；因此没有做寻址表达式重算。
- **未覆盖** — 私有 fixed LLVM 装置尚未组好；stock llc 已知会产生无关的 `-cj-generational-post-barrier=true` 参数错误。
- **未覆盖** — 当前新 pin 候选 SO 只有路径和 21570144-byte 大小，尚缺 SHA/SOURCE_SHA 复核。
- **怀疑但未验** — 四刀中的至少一刀把旧 semantic 的发生概率压到零；现有证据只能说明 GC 是强根因候选，不能指名 whopush/regcover/freeregion/routetbl2。
- **怀疑但未验** — 新 macro/app SIGSEGV 可能仍是 GC，也可能是宏加载/展开后的独立缺陷。`si_addr` 是规范用户态地址这一外观不足以归族，必须以实际指令和寄存器重算为准。
- **明确不混同** — `/root/cj_build/reports/REPORT-blamebisect2.md` 的 sticky-minor SIGABRT 位于另一段 runtime 历史；它不能代替本次四刀二分。
