# cjcj 路线图

> 当前状态与测量口径见 [STATUS.md](STATUS.md)。本文只描述下一阶段目标，避免在多处
> 复制易过时的进度数字。

cjcj 的编译器主线复刻与自举闭环已经完成。后续工作不再以“能否自举”为中心，而是
在保持官方语义和默认产物一致的前提下，提高发布质量、测试深度、平台覆盖与性能。

## 不变量

以下约束适用于所有里程碑：

1. 默认模式忠实复刻 C++ 编译器，不静默省略规则，不以样本特判或 fallback 掩盖缺口。
2. 默认模式持续保持 bcgate 共享函数 **2490/2490** 字节一致；任何下降都视为回归。
3. 超越官方的 codegen 优化只能由 `--cjcj-optimization` 承载；旗标关闭时仍须保持
   默认产物一致。runtime/GC 优化不得放宽语言、finalizer、weak reference、extension
   更新或卸载语义。
4. 每个修复必须有官方 C++ 源码锚和定向复现；测试未覆盖不是偏离官方行为的理由。
5. 发布产物中的编译器名为 `cjc`，模块名与仓库名为 `cjcj`，主分支为 `master`。

## 当前基线

2026-07-25 的权威基线为：

| 维度 | 基线 |
|---|---|
| 编译器主线 | 真实 parse -> sema -> CHIR -> codegen 管线完成，自举闭环达成 |
| 默认产物一致性 | bcgate 2490/2490，共享函数 differing=0 |
| 单文件差分 | difftest 114/114 |
| 结构化差分资产 | 18 例：12 个多包/import、3 个宏包、3 个增量双轮 case |
| 发布 | v0.0.1 已公开为 pre-release，5 个平台、每个平台 SDK 包及 SHA-256，共 10 个发布产物 |
| 性能 | Goal-2 权威比值 4.28x（旗开）/4.29x（旗关），同箱同窗 N=5 中位数 |
| 构建编排 | 仓内 `build/` 与 CI 使用 zx 8 的 `.mjs` 脚本；早期 Python 编排器已删除 |

## R1：v0.0.2 发布准备

v0.0.2 的目标是把已经完成的自举编译器变成可重复验证的多平台 SDK，而不是增加一个
新的编译器前端分支。

- 保持 Linux x64、Linux aarch64、macOS x64、macOS arm64、Windows x64 五平台发布矩阵。
- 每个平台生成可重定位 SDK 包和同名 `.sha256`；包内入口统一为 `bin/cjc` 或
  `bin/cjc.exe`。
- release workflow 必须消费同一轮构建的 LLVM tools、patched cjpm 与 runtime，避免
  跨 run 的陈旧 artifact。
- 对解压后的 SDK 执行编译、链接、运行、宏和包导入 smoke；不以“构建 job 成功”代替
  最终包验证。
- 发布前冻结 SDK、runtime、LLVM 与 cjpm 的来源 SHA，并在 release 元数据中保留。

验收入口以 `.github/workflows/release.yml` 与
`.github/workflows/build-release-package.yml` 为准。v0.0.1 是当前公开预发布，v0.0.2
仍处于准备阶段。

## R2：测试从样本门扩展到结构门

现有 114 例单文件语料负责快速检查编译、运行与字节一致性，但对 import、宏包和增量
重建天然覆盖不足。已经入库的 18 例结构化语料补上了这三类形态，下一步是把它从独立
资产提升为稳定门禁。

- 保持 `scripts/difftest.mjs` 的 114 例快速门与 `scripts/bcgate.py` 的 2490 函数字节门。
- 使用 `scripts/difftestx_corpus/run.sh` 验证多包/import、macro package 与 incremental
  两轮重建；固定外层 `JOBS` 和编译器内层 `CJC_JOBS`。
- 将结构化语料接入 CI 时保留 case manifest 与逐例结果，避免只输出总计。
- 继续维护 macro、generic、test/mock 等专项 golden gate；文档不固化易漂移的 selfhost
  结果，当前结果由同一 HEAD 的实跑输出给出。
- 扩展诊断、平台条件、CJO/增量缓存与 debug info 的行为级回归资产，弥补 bcgate 不覆盖
  的输出面。

## R3：性能从 4.28x 走向超越官方

Goal-2 的权威口径是同箱、同窗、同 workload、同核域，分别构建 fresh target，使用 N>=3
中位数；当前 N=5 结果为 4.28x。更早版本或错误口径得到的历史比值不能作为当前基线。

近期目标是把比值降到 2.0x 以内，长期目标是编译产物性能超过官方，包括 runtime/GC。
合法优化面只有两类：

- `--cjcj-optimization`：旗开时允许生成优于官方的代码，旗关仍保持 bcgate 2490/2490。
- runtime/GC：不改变 compiler 输出字节，但必须保持 GC、并发、finalizer、weak reference、
  TypeInfo 与动态扩展语义。

当前画像显示 GC Trace/Mark、写屏障与 TypeInfo 是主要成本桶。每把性能改动必须同时给出
正确性门、前后二进制/IR 绑定和同口径 N>=3 收益；低于噪声的结果记录为负结果，不以
单轮 wall time 宣称收益。

## R4：忠实度与平台债持续清账

主线完工不等于所有语料和平台行为都已经穷尽。后续清账按用户可观察面排序：

1. 诊断精确性、source range 与平台条件分支；
2. 多包 import、CJO 序列化、增量重建与 macro host/target 分离；
3. debug info、sanitizer、LTO 和链接器/归档确定性；
4. 官方 C++ 新提交带来的同步差异；
5. 非发布平台与生态研究。

缺失的上游设施必须先完整移植，不在 downstream 写简化替代。默认输出不变的并发化也要
验证诊断顺序、dump 顺序、archive 顺序与竞争稳定性，不能只看逐函数 IR。

## 研究方向：WebAssembly

WebAssembly 当前是调研结论，尚未立项。线性内存路线需要重做精确 GC 根发现、异常、
32 位对象 ABI、协程和 WASI/runtime 平台层，不能按普通 target triple 扩展估算。
完整边界、8 类阻塞面与 86-134 人周估算见
[WASM_PORTING.md](WASM_PORTING.md)。最小 4-6 人周演示只证明 backend feasibility，
不构成“支持 wasm”的产品声明。

## 验收入口

本地开发和 CI 的权威入口均在仓内：

```sh
cjpm build
npx --yes zx@8 scripts/difftest.mjs -j 10
python3 scripts/bcgate.py --self target/release/bin/cjcj::cjc -j 10
JOBS=4 CJC_JOBS=1 bash scripts/difftestx_corpus/run.sh
```

发布构建与完整源码构建分别以 `.github/workflows/release.yml`、
`.github/workflows/srcbuild.yml` 为准。命令中的并发度是示例，受共享构建环境约束时应显式
降低外层与编译器内层并发。
