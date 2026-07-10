# cjcj 编译器平台条件全量对照审计

基线：`3921990d`（selfhost `master` / `fix/platparity` 起点）  
C++：`7a1666e7`（`/root/cj_build/cangjie_compiler/src`）  
selfhost：`/root/cj_build/wt/fix_platparity/packages`  
明细：[PLATFORM_PARITY_AUDIT.tsv](PLATFORM_PARITY_AUDIT.tsv)

## 结论

本次把同一 `#if/#elif/#else/#endif` 条件链归并为一个审计块，共得到 **147 个平台条件块**、覆盖 **167 个平台条件 directive**。逐块结论为：

- **COVERED 74**：存在对应 `@When`，或无注解但逐平台结果等价。
- **MISSING 9**：官方 named 实体/平台路径在 selfhost 完全不存在。
- **DIVERGENT 64**：存在对应功能，但平台分支缺失、被单一路径替代，或分支行为与官方不同。

任务给出的四个主锚全部复核一致：`_WIN32=108`、`__APPLE__=31`、`__linux__=24`、`__aarch64__ + __x86_64__=16` 次宏出现。为保证“全量”，明细还纳入了同一 `src/` 内未列在主锚中的平台宏：`__arm__`、`_WIN64`、`__unix__`、`__MINGW64__`、`__ohos__`/`__ohos`、`__android__`；它们不能被误当成功能门。

状态定义：

- `COVERED`：官方条件链的各结果均可在 selfhost 找到，允许把纯编译期选择改写成结果等价的目标/host 查询。
- `MISSING`：对应 named 实体或条件路径不存在；修复时应直接移植官方实体。
- `DIVERGENT`：有同名/近似功能，但至少一个平台结果不同；“只有 Linux 路径”、恒真/恒 64 位、用通用实现替换官方平台 API 均归此类。

## 按包 × 状态

| C++ 包 | 块数 | COVERED | MISSING | DIVERGENT |
|---|---:|---:|---:|---:|
| Basic | 9 | 4 | 0 | 5 |
| CHIR | 11 | 2 | 0 | 9 |
| CodeGen | 13 | 9 | 2 | 2 |
| Driver | 24 | 10 | 2 | 12 |
| Entrypoints | 11 | 3 | 1 | 7 |
| Frontend | 3 | 2 | 1 | 0 |
| FrontendTool | 1 | 0 | 1 | 0 |
| Lex | 1 | 1 | 0 | 0 |
| Macro | 26 | 6 | 0 | 20 |
| Option | 4 | 3 | 0 | 1 |
| Parse | 1 | 1 | 0 | 0 |
| Utils | 43 | 33 | 2 | 8 |
| **TOTAL** | **147** | **74** | **9** | **64** |

## 按包 × 平台分布

一个条件块可同时计入多个平台列，因此行内平台计数之和不等于块数。

| C++ 包 | Windows | Apple | Linux | x86_64 | aarch64 | ARM32 | Unix | MinGW | OHOS | Android |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Basic | 8 | 0 | 0 | 0 | 0 | 1 | 0 | 0 | 0 | 0 |
| CHIR | 2 | 1 | 1 | 8 | 8 | 0 | 0 | 0 | 0 | 0 |
| CodeGen | 7 | 6 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Driver | 24 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Entrypoints | 8 | 2 | 2 | 0 | 0 | 0 | 2 | 0 | 1 | 0 |
| Frontend | 3 | 2 | 1 | 0 | 0 | 0 | 1 | 0 | 0 | 0 |
| FrontendTool | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Lex | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Macro | 14 | 8 | 13 | 0 | 0 | 0 | 0 | 0 | 3 | 0 |
| Option | 4 | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Parse | 1 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| Utils | 36 | 10 | 7 | 0 | 0 | 1 | 0 | 6 | 5 | 2 |

## 按平台 × 状态

| 平台 | COVERED | MISSING | DIVERGENT |
|---|---:|---:|---:|
| Windows | 65 | 9 | 35 |
| Apple | 20 | 0 | 11 |
| Linux | 10 | 0 | 14 |
| x86_64 | 0 | 0 | 8 |
| aarch64 | 0 | 0 | 8 |
| ARM32 | 1 | 0 | 1 |
| Unix | 1 | 2 | 0 |
| MinGW | 4 | 0 | 2 |
| OHOS | 5 | 0 | 4 |
| Android | 2 | 0 | 0 |

## MISSING TOP：可直接派发的修复波

以下按 named 官方实体合并；括号内是 TSV ID，可直接作为任务范围。

1. **Windows crash backtrace**（`PB119`, `PB120`）：移植 `Utils/SignalUtil.cpp:91` 的 `AsyncSigSafePutHex`/模块 RVA 栈输出及 `:174` 的同步信号调用。当前 `packages/utils/src/Signal.cj` 完全没有对应物。
2. **Windows Tool 长命令与系统错误**（`PB047`, `PB048`）：移植 `Driver/Tool.cpp:36` `WriteArgsToResponseFile` 与 `:65` `GetSystemErrorMessage(DWORD)`；这是后续忠实移植 Windows `Tool::Run` 的直接前置。
3. **IncrementalGen Windows 路径**（`PB030`, `PB031`）：移植 `CodeGen/IncrementalGen/IncrementalGen.cpp:98` `IncrementalGen::Init` 的完整实体及 Windows UTF-8 路径分支。
4. **Frontend cached split reader**（`PB061`）：移植 `FrontendTool/IncrementalCompilerInstance.cpp:100` `GetCachedSplitNum`，含 Windows `NormalizeStringToUTF8`。
5. **worker 线程信号注册**（`PB058`）：在对应的并行解析 worker 中忠实移植 `Frontend/CompileStrategy.cpp:238-249` 的 release/Unix/Windows 条件链。
6. **chir-dis 入口信号注册**（`PB137`）：selfhost 当前没有 `main-chir-dis.cpp:49` `RegisterSignalHandler` 对应入口；应作为独立工具入口任务派发。

## DIVERGENT 修复波建议

这些不是 `MISSING`，但不能因“已有函数”视为平台一致：

1. **宏服务进程模型（27 块）**：`MacroEvaluationClient.cpp`、`MacroEvaluationSrv.cpp` 与 `main-macrosrv.cpp` 的 Win named pipe / POSIX pipe+fork+wait / Linux `prctl` 被 `MacroProcMsger` 进程内队列替代；另有 OHOS `CloseRuntime` 差异。应作为一个系统根处理，不能逐点补注解。
2. **Driver Windows 执行链（12+ 块）**：`Tool::Run`、`WindowsProcessFuture`、Job UTF-16 诊断和 TempFileManager 的宽字符/reparse/_wmkdir 分支被同步 `std.process` 或 `std.fs` 通用路径替代。
3. **CHIR host 宽度与 SIMD（9 块）**：IntNative/UIntNative 恒按 64 位，且 `CJ_CORE_CanUseSIMD` 恒 `true`；官方在 x86_64 上检查 AVX/AVX2、aarch64 返回真、其他平台返回假。
4. **UserMemoryUsage（4 块）**：selfhost 所有平台固定读取 `/proc/self/statm`，缺 Windows `GetProcessMemoryInfo` 与 Apple `task_info`。
5. **Basic Windows 支持（5 块）**：Windows console virtual-terminal 初始化/恢复缺失；GBK/UTF-8 非 ASCII 转码仅返回 `None`。
6. **零散单根**：ARM32 文件上限仍为 4 GB（官方 2 GB）；`--trimpath` 固定追加 `/`；DIBuilder 非 Apple member full-debug 路径仍显式 `BLOCKED`。

## selfhost `@When` 反向发明候选

下列 selfhost 条件在 C++ `src/` 对应职责中没有平台条件块。它们是审查候选，不等于自动判错；修复前必须先决定是仓颉 FFI 的必要适配，还是无官方出处的平行实现。

| 候选 | selfhost | C++ 对照 | 风险判断 |
|---|---|---|---|
| 平台专用 `GetHash` 算法 | `packages/basic/src/Utils.cj:8-92` | `Basic/Utils.cpp:25-29` 仅调用 `std::hash<std::string>` | 高：selfhost 固化了 libstdc++ Murmur 风格与 MSVC FNV 风格，实现面明显大于 C++ named 实体。 |
| `GetHardwareConcurrency` 平台 FFI | `packages/option/src/OptionSupport.cj:19-64` | `Option.cpp:703` / `Option.h:1199` 使用 `std::thread::hardware_concurrency()` | 中：行为目标相同，但新增了 Linux/macOS/Windows FFI 分支及 fallback。 |
| Semaphore core-count 平台 FFI | `packages/utils/src/Semaphore.cj:5-25` | `Utils/Semaphore.cpp:16-20` 使用 `std::thread::hardware_concurrency()` | 中：与上一候选重复实现同一平台探测，应避免两套漂移。 |
| `StdUtils` errno 定位 | `packages/utils/src/StdUtils.cj:15-50` | `Utils/StdUtils/StdUtils.cpp:10-77` 使用 `std::stoi/stoul/...` 异常模型 | 高：selfhost 改成 libc `strto*` + 平台 errno，已经不是 C++ named 实体的结构。 |
| LLVM optional symbol lookup | `packages/codegen/src/LLVM.cj:21-24,92-110` | C++ CodeGen `src/` 无 `LookupLLVMOptionalSymbol` named 实体 | 高：非 Windows `dlsym` 与 Windows 恒空指针是 selfhost 新平台面，需逐调用方确认来源。 |

反向扫描中已排除的“看似发明”：`Option/Triple.cj` 与 `DriverModel.cj` 的 host triple 分支对应 `include/cangjie/Option/Option.h:323-349`；`MacroCommon.cj` 的库后缀对应 `include/cangjie/Macro/MacroCall.h:26-32`；`Signal.cj` 对应 `SignalUnix.cpp`/`SignalWin.cpp` 的平台拆文件；`SourceManager.cj` 的斜杠 helper 对应本次已审计的 `Utils/FileUtil.cpp` 平台语义。

## 机械完备性证据

主锚原始输出：

```text
_WIN32 108
__APPLE__ 31
__linux__ 24
__aarch64__|__x86_64__ 16
```

扩展平台 directive 与 TSV 覆盖数：

```text
C++ platform directive lines 167
TSV represented platform directives 167
TSV audit blocks 147
COVERED 74
MISSING 9
DIVERGENT 64
```

本任务按用户要求为 **零构建审计**，未运行编译、bcgate 或 self-compile，也未修改任何 `packages/`、`runtime_shim/`、`scripts/`（最终交付）或测试业务源码。

逐块完整性声明：已覆盖上述平台宏命中的全部 **147 个 `#if` 条件块 / 167 个 directive**，包括每条链的 `#elif/#else`；数量来源为 C++ `src/` 的预处理 directive 扫描并与 TSV 条件链逐条反查。

- 无任何 grep 不到 C++ 出处的新编译器符号（本提交仅含审计数据与报告）。
- 未改业务源码绕过、未加 band-aid 吞 bug。
- 撞到的平台系统差异均以 `MISSING`/`DIVERGENT` 上报，未自行替代。
