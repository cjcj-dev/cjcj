# Codex 工作流手册

本文说明 cjcj 当前使用的隔离 worktree + Codex lane 工作流。它面向维护者，不绑定某个
Codex 模型版本、插件缓存路径或已经结束的移植 wave。

## 适用范围

编译器主线和自举闭环已经完成。Codex lane 现在用于：

- 对照官方 C++ 源码修复忠实度或诊断差异；
- 补平台、CJO、增量、debug info 等窄面；
- 增加行为/字节测试；
- 在默认输出不变的条件下做性能工作；
- 进行只读调研并沉淀设计文档。

仓库、模块和主分支分别是 `cjcj-dev/cjcj`、`cjcj`、`master`。发布编译器名为 `cjc`。
旧仓名 `cangjie_compiler_selfhost`、旧 `main` 分支、June-era deepen workflow 和
`codex-companion.mjs` 插件路径都不是现役入口。

## 一条 lane 的输入

每条 lane 必须有：

1. 单一根因或边界清楚的文档/测试目标；
2. 从最新 `origin/master` 创建的独立 worktree 与分支；
3. worktree 根的 `AGENTS.md`，包含当轮环境、验证与交付约束；
4. 官方 C++ 参考树，通常是 `/root/cj_build/cangjie_compiler`；
5. 可复现的样本、基线命令与预期输出；
6. 报告名和明确的允许修改范围。

不要按“一个 package 一条 lane”切任务。优先按一个 C++ named facility、一个诊断根或一个
行为差异切分；同一根跨 package 时仍是一条 lane，彼此独立的根才并行。

## 开工检查

开始编辑前完成以下只读检查：

```sh
git status --short --branch
git remote -v
git log -8 --oneline --decorate
```

在当前维护环境中，还要读取协同台账、已移植设施、文件占用与断点状态。实际路径由 lane
的 `AGENTS.md` 给出；目前使用 `BUS.md`、`PORTED_FACILITIES.tsv`、`CLAIMS.tsv` 和
worktree 根 `STATE.md`。

移植任务必须先做依赖闭包预扫：列出目标 C++ 函数体调用的 named facility，逐一确认
selfhost 已有实体。已有设施直接复用；缺失依赖按 `AGENTS.md` 的比例规则处理，超过授权
范围就精确 BLOCKED，不写“差不多”的平行实现。

## 忠实移植纪律

每个新增或修改的函数、分支、字段和 helper 调用都要能定位到官方 C++ 的具体实体与
`file:line`。实现审查至少检查：

- 函数名与 C++ 名逐字符一致；
- 所有 branch、case 和 early return 都已覆盖；
- 调用参数、字段来源、诊断 overload 与执行顺序一致；
- 平台条件覆盖 C++ 的全部平台分支；
- 没有 fallback、样本特判、吞异常、skip 或未授权的简化 helper；
- 默认模式没有借修业务源码绕过编译器缺陷。

语义看似等价或测试通过都不能替代源码对位。任务前提若被 C++ 原文证伪，应停止改代码并
报告证据；发现任务书错误本身是有效结论。

## 编辑与提交节奏

当前验证脚本可能清理或重建 worktree，未提交改动可能丢失。因此节奏固定为：

```text
编辑一个独立改动 -> 检查 staged 文件 -> commit -> 才运行 build/gate
```

不要把多个可独立 review 的设施或文档压成巨型提交，也不要在验证前积累未提交改动。
每次提交前至少执行：

```sh
git add <明确文件>
git diff --cached --name-only
git commit -m '<semantic prefix>: <summary>'
```

生产提交不得包含调试探针、临时日志、`STATE.md`、`REPORT*.md`、`REJECT*` 或测量 TSV。
这些报告类文件由本地 exclude 管理，只写盘，不使用 `git add -f`。提交作者由任务书指定；
当前项目使用 `Zxilly <zxilly@outlook.com>`，不添加 AI 或 Co-Authored-By 署名。

## 验证

### 环境

标准 Linux 构建环境需要官方 SDK 和足够的 managed heap：

```sh
export PATH=/root/.cjv/bin:$PATH
export CANGJIE_HOME=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$LD_LIBRARY_PATH"
export cjHeapSize=24GB
```

共享维护环境当前要求本机只运行 agent 与秒级只读命令。编译、链接、gate、sweep、profiling
和性能测量必须在任务指定的远程 builder 与核域执行；连接方式、核域和并发上限以当轮
`AGENTS.md` 为准。进入远程 builder 后先登记资源 marker，所有计算进程用 `taskset`
绑定核域，结束时只删除自己的 marker 行。

### 分层验证

验证强度随改动风险增加：

| 层 | 入口 | 适用场景 |
|---|---|---|
| 构建 | `cjpm build` | 所有生产源码改动；文档-only 作为最终卫生检查 |
| 定向复现 | lane 自带最小样本或专项 `*_gate.mjs` | 证明根因和行为变化 |
| 单文件差分 | `npx --yes zx@8 scripts/difftest.mjs` | frontend/sema/CHIR/codegen 行为 |
| 字节门 | `python3 scripts/bcgate.py --self <cjc>` | 默认产物，基线 2490/2490 |
| 结构化差分 | `scripts/difftestx_corpus/run.sh` | import、macro package、incremental |
| 自编译 | 用新 `cjc` 编译核心 package staticlib | sema/chir/codegen 与跨包改动 |
| 发布 smoke | `ci/smoke/run_smoke.mjs` | SDK、runtime、linker 与平台打包 |

默认模式的 bcgate 下降为硬回归。`--cjcj-optimization` 性能刀必须同时证明旗关仍为
2490/2490，并给出旗开同口径 N>=3 中位数；runtime/GC 性能刀不进入 compiler 字节面，
但仍需行为门和并发/生命周期压力测试。

批量验证前后检查磁盘；每个样本完成后删除 object、binary 和 save-temps。最终报告引用的
逐例原始输入、诊断或 JSON 是证据，不得删除，体积大时压缩归档。

## 报告与断点恢复

lane 进行中持续维护 `STATE.md`，至少三行：

```text
目标：<当前目标>
已落 commit：<sha + 摘要>
下一步：<唯一下一动作或 blocker>
```

最终 `REPORT-<lane>.md` 至少包含：

- 结论与范围；
- 基线 SHA、最终 HEAD 和提交列表；
- 每个改动对应的 C++ `file:line`；
- 最小复现的前后行为；
- 每个 gate 的完整原始汇总行与退出码；
- 未完成项、缺失依赖与限制，不隐藏部分交付；
- `git log --name-only <base>..HEAD` 的提交卫生检查。

若任务被中断，下一位执行者先读 `STATE.md` 和已落 commit，从“下一步”继续，不重复已经
完成的调查或验证。遇到关键语义裁决、任务前提冲突或连续假设被证伪，使用当轮 runbook
指定的 lead/advisor 通道，不在两个都说得通的实现间盲选。

## 审查与合并

lane 自己不合并 `master`。交付后由维护者完成：

1. 检查提交只含授权文件，无报告或调试历史；
2. 按 C++ anchor 逐符号审查忠实度；
3. 在独立环境复跑要求的 gate；
4. 以 ff-only 或明确选择的 semantic commits 合并；
5. push `origin/master` 并观察 CI；
6. 更新全局设施/状态台账。

验证通过不自动授权合并，数字未改善也不自动否定忠实的部分移植。判断顺序始终是：
C++ 对位、无回归、证据完整，最后才是目标数字。
