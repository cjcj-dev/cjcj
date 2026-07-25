# cjcj 当前状态

最后核实：2026-07-25。仓库为 `cjcj-dev/cjcj`，模块名 `cjcj`，主分支 `master`；
编译器发布产物名为 `cjc`。

## 摘要

cjcj 是仓颉编写的仓颉编译器，忠实复刻官方 C++ 编译器的 parse、sema、CHIR、codegen
与 driver 管线。编译器主线复刻已经完工，自举闭环已经达成；当前工作重心是发布质量、
平台矩阵、测试深度与性能，而不是继续维护早期 facade 或局部兼容实现。

| 维度 | 当前状态 |
|---|---|
| 自举 | 已能通过真实编译管线编译自身源码，自举闭环达成 |
| 默认输出一致性 | bcgate 共享函数 **2490/2490** 字节一致，differing=0 |
| 单文件差分 | difftest **114/114** |
| 多包/宏/增量差分 | 18 个结构化 case 已入库：12 个多包/import、3 个 macro、3 个 incremental |
| 公开发布 | **v0.0.1 pre-release**，5 平台的 SDK 包及 SHA-256，共 10 个发布产物 |
| 下一发布 | **v0.0.2 正在准备** |
| 性能 | Goal-2 当前权威比值 **4.28x**（旗开）/4.29x（旗关），同箱同窗 N=5 中位数 |
| 构建编排 | `build/` 与 CI 使用 zx 8 `.mjs`；早期 Python 编排器已删除 |

自举完成前的部分一致性计数、stage2 崩溃状态和旧性能口径均已过时，不能用于描述当前
master。

## 发布与平台

v0.0.1 已由 GitHub Releases 公开为预发布。release workflow 当前覆盖：

- Linux x64
- Linux aarch64
- macOS x64
- macOS arm64
- Windows x64

每个平台发布一个可重定位 SDK 压缩包和一个同名 `.sha256`。SDK 中的编译器入口是
`bin/cjc`，Windows 为 `bin/cjc.exe`。工作流定义见 `.github/workflows/release.yml` 与
`.github/workflows/build-release-package.yml`；v0.0.2 的发布准备继续沿用这五个平台。

## 一致性与测试

默认编译路径以官方 C++ 编译器为 oracle，当前固定基线是 2490 个共享函数全部字节一致。
bcgate 主要比较单文件语料的逐函数 bitcode，不能替代所有用户可观察面，因此测试分层为：

| 层 | 入口 | 覆盖 |
|---|---|---|
| 快速行为差分 | `npx --yes zx@8 scripts/difftest.mjs` | 114 个单文件 compile/run case |
| 字节一致性 | `python3 scripts/bcgate.py --self <cjc>` | 114 个样本、2490 个共享函数 |
| 结构化差分 | `scripts/difftestx_corpus/run.sh` | 多包/import、macro package、incremental 双轮重建 |
| 专项 golden gates | `scripts/*_gate.mjs` | generic、macro、test/mock、诊断、序列化等窄面 |
| 发布 smoke | `ci/smoke/run_smoke.mjs` | 解包后的编译、链接、运行与宏/包行为 |

结构化语料由 `685f4fa5`（`test: add structural differential corpus`）加入，
`c2b53c37` 固定外层 `JOBS` 与编译器内层 `CJC_JOBS`。它补充而不替代 114 例快速门。

## 构建体系

源码构建入口是 `cjpm build`。完整 SDK/source build 的编排已从早期 Python 工具迁移到
仓内 zx 脚本：

- `build/cli.mjs`：源码构建 CLI；
- `build/srcbuild/stages/*.mjs`：compiler、runtime、stdlib、stdx、tools、package、verify；
- `build/toolchain/*.mjs`：平台依赖、静态库、sccache、MinGW 与 target Python；
- `.github/workflows/srcbuild.yml`：完整源码构建；
- `.github/workflows/ci.yml`：日常 master/PR 构建与 smoke。

统一调用 zx 8：`npx --yes zx@8 <script>.mjs`。迁移提交为 `dc5d6fef`；旧 Python
目录和它的工作流、测试已在同一提交删除。

## 性能

Goal-2 使用同箱同窗、fresh target、相同 workload 与固定核域比较 selfhost 和官方 C++
`cjc`。2026-07-25 的 N=5 中位数为：

| 构型 | 中位 wall | selfhost/official |
|---|---:|---:|
| 官方 C++ | 10.71 s | 1.00x |
| selfhost + `--cjcj-optimization` | 45.87 s | **4.28x** |
| selfhost 默认模式 | 45.95 s | **4.29x** |

旗开与旗关只差 0.17%，该轮不把差异解释为稳定收益。当前性能优化继续沿两条合法路径：
旗控 codegen 优化，以及保持语义的 runtime/GC 优化。默认模式的 bcgate 2490/2490
不因性能目标放宽。

## 包与官方组件对应

`packages/<name>` 与官方 `cangjie_compiler/src/<Name>` 及其公开头文件按组件对应：

| cjcj package | 官方组件 | 主要职责 |
|---|---|---|
| `basic` | `Basic` | source、position、diagnostic |
| `utils` | `Utils` | file/path、hash、Unicode、platform FFI |
| `option` | `Option` | compiler options 与 target 配置 |
| `lex` | `Lex` | token 与 lexer |
| `parse` | `Parse` | parser |
| `ast` | `AST` | 共享 AST、Ty 与 walker |
| `sema` | `Sema` | 类型检查、推断、继承与诊断 |
| `chir` | `CHIR` | IR、AST2CHIR、analysis、transform、serialize |
| `codegen` | `CodeGen` | LLVM IR 与对象生成 |
| `mangle` | `Mangle` | 符号改名 |
| `macro` | `Macro` | macro 编译与求值 |
| `meta_transformation` | `MetaTransformation` | 元变换 |
| `modules` | `Modules` | import、package graph、CJO |
| `conditional_compilation` | `ConditionalCompilation` | `@When` 条件编译 |
| `incremental_compilation` | `IncrementalCompilation` | 增量依赖与缓存 |
| `driver` | `Driver` | 工具链与任务编排 |
| `frontend` | `Frontend` | `CompilerInstance` 与 pipeline |
| `frontend_tool` | `FrontendTool` | frontend 工具入口 |
| `cjc` | `main.cpp` / driver entry | 编译器可执行目标 |
| `compiler_unittest` | C++ unittests | 仓颉 `std.unittest` 移植 |

LLVM、runtime、FlatBuffers、libffi、boundscheck 与平台 linker 等原生依赖通过 C FFI 或薄
adapter 使用，不在仓颉中重新实现。

## 当前工作面

- 完成 v0.0.2 的多平台构建、打包、解包 smoke 与来源固定。
- 把结构化差分资产稳定接入 CI，并继续补齐 bcgate 的 import、增量、诊断和平台盲区。
- 在默认字节一致的前提下，将 Goal-2 从 4.28x 继续降到 2.0x 以内，长期目标是超过官方。
- 持续跟随官方 C++ 源码，清理新发现的忠实度与平台债。

WebAssembly 目前仅完成技术调研，未立项；结论与工作量见
[WASM_PORTING.md](WASM_PORTING.md)。后续计划见 [ROADMAP.md](ROADMAP.md)。
