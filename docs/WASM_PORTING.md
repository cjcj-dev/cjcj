# WebAssembly 线性内存移植设计

> 状态：调研结论，尚未立项；置信度为 low，因为 Cangjie GC pass 尚未在
> WebAssembly target 上做原型，shadow root stack 与 wasm EH 也尚未验证。

本文描述把 cjcj、Cangjie runtime 与标准库移植到 `wasm32` 线性内存的技术边界。
路线以 core WebAssembly + WASI 为产品基线，不讨论 WasmGC。当前结论是：路线可行，
但不是更换 LLVM triple 就能完成的后端适配。

## 结论与边界

- 官方 compiler/runtime 产品源码中没有 wasm、WASI 或 Emscripten 平台实现。
- 当前 vendor LLVM 15.0.4 的 `llc` 只注册 ARM、AArch64 与 X86，未编入
  WebAssembly target；`lld -flavor wasm` 可用，但不能代替缺失的 codegen target。
- Cangjie GC 使用精确 native stackmap，不是保守扫描。wasm 无法遍历引擎内部的
  value stack 或 locals，因此根发现必须重做。推荐 shadow root stack；B2 是关键路径，
  M1 无法绕过。
- 当前协程通过手写汇编保存和切换 SP/PC。M0/M1 可以禁用并发而推迟该工作，M3 主线
  应采用 CPS/显式状态机；只有目标 host 的 stack-switching 稳定后才重新评估提案方案。
- 规范或提案达到某个阶段不等于 cjcj 可用。EH、threads、stack-switching 与 WASI
  的落地均受 vendor LLVM、runtime 和目标 host 共同约束。
- 产品化总量预计为 **100-138 刀、86-134 人周**。最小 backend feasibility demo
  需要 **4-6 人周**，且不应对外称“支持 wasm”。

## 现状证据

### 官方源码与工具链

对 `cangjie_compiler` 与 `cangjie_runtime` 的产品源码、头文件、CMake 和仓颉源码进行
单词边界检索时，产品代码命中为 0。唯一 wasm 文本来自
`cangjie_compiler/third_party/llvmPatch.diff` 中的上游 LLVM 类型、注释和 MIME 字符串，
不能视为平台支持。

当前 target 入口如下：

- `cangjie_compiler/include/cangjie/Option/Option.h:98-132`：`Backend` 只有
  `CJNATIVE/UNKNOWN`，`Arch` 无 `WASM32`，`OS` 无 `WASI`。
- `cangjie_compiler/src/Option/Option.cpp:69-85,106-116,145-199`：枚举字符串、
  backend 名、triple 序列化与 effective triple。
- `cangjie_compiler/src/Option/OptionAction.cpp:78-103,206-274,346-367`：命令行
  target 解析以及 `@When` 的 `os/backend/arch` 键。
- `cangjie_compiler/src/Driver/Backend/CJNATIVEBackend.cpp:28-70`：现有 OS 到
  `Ohos/Android/Linux/MinGW/Darwin/IOS` ToolChain 的分派点。
- `cangjie_compiler/src/Driver/Job.cpp:74-95`：backend 只有 CJNATIVE。wasm 应是
  CJNATIVE 的新目标平台，不应另造 frontend backend。

建议 canonical triple 为 `wasm32-unknown-wasi`，新增 `Arch::WASM32` 与 `OS::WASI`。
WASI 不能伪装成 Linux，否则 `os != Windows` 等 fallback 会错误引入 pthread、dlopen、
`mmap` 等假设。

装机 vendor `llc` 的实测版本为 LLVM 15.0.4，只注册 `x86` 与 `x86-64`；构建锚
`cangjie_compiler/third_party/CMakeLists.txt:177-204` 只启用
`ARM|AArch64|X86`。必须加入 `WebAssembly` 并重建 vendor LLVM。不能直接换系统 LLVM，
因为 vendor patch 包含 `CangjieGC` calling convention、`CJRewriteStatepoint`、
`CJStackPointerInserter` 与自定义 stackmap，例如
`third_party/llvmPatch.diff:33687-33773,35132,38219-38259,44945`。

### 编译器触点

以下 32 个触点是 runtime 重写前已由源码确认的最小审计面，不是最终文件总数：

| # | 源码锚 | 工作 |
|---:|---|---|
| 1 | `cangjie_compiler/third_party/CMakeLists.txt:177-204` | 构建 WebAssembly LLVM target |
| 2 | `cangjie_compiler/include/cangjie/Option/Option.h:98-132` | `WASM32/WASI` 枚举 |
| 3 | `cangjie_compiler/src/Option/Option.cpp:69-199` | enum/string/triple |
| 4 | `cangjie_compiler/src/Option/OptionAction.cpp:78-274` | triple parser |
| 5 | `cangjie_compiler/src/Driver/Backend/CJNATIVEBackend.cpp:28-70` | ToolChain 分派 |
| 6 | `cangjie_compiler/src/Driver/CMakeLists.txt:7-20` | 注册新源码 |
| 7 | `include/cangjie/Driver/Toolchains/CJNATIVE/Wasm_CJNATIVE.h`（新增） | ToolChain 声明 |
| 8 | `src/Driver/Toolchains/CJNATIVE/Wasm_CJNATIVE.cpp`（新增） | 静态链接流程 |
| 9 | `cangjie_compiler/include/cangjie/Driver/Tools.inc` | linker 工具 ID |
| 10 | `cangjie_compiler/src/Driver/TempFileManager.cpp:225-245` | `.wasm` 输出与 dylib 拒绝 |
| 11 | `cangjie_compiler/src/Driver/DriverOptions.cpp:247-330` | target CPU、静态链接、非法组合 |
| 12 | `cangjie_compiler/src/Driver/ToolOptions.cpp:140-250` | wasm llc/lld 参数 |
| 13 | `cangjie_compiler/src/CodeGen/CGModule.cpp:32-61` | data layout/triple |
| 14 | `cangjie_compiler/src/CodeGen/CJNative/CJNativeCGCFFI.h:109-271` | wasm C ABI 类 |
| 15 | `cangjie_compiler/src/CodeGen/CJNative/CJNativeCGCFFI.cpp:144-768` | wasm C ABI 实现 |
| 16 | `cangjie_compiler/src/CodeGen/CJNative/CJNativeIRBuilder.cpp:421-453` | 指针宽度与布局 |
| 17 | `packages/option/src/OptionEnums.cj:72-76` | selfhost 枚举同步 |
| 18 | `packages/option/src/Triple.cj:3-48` | selfhost triple 同步 |
| 19 | `packages/driver/src/DriverModel.cj:30` | wasm linker ToolID |
| 20 | `packages/driver/src/CJNATIVEBackend.cj:14-49` | selfhost 分派 |
| 21 | `packages/driver/src/Wasm_CJNATIVE.cj`（新增） | selfhost ToolChain |
| 22 | `packages/driver/src/Tools.cj:11-51` | 工具名 |
| 23 | `packages/option/src/TempFileManager.cj:84-95,207-220` | `.wasm` 输出 |
| 24 | `packages/driver/src/DriverOptions.cj:205-277` | target 合法性 |
| 25 | `packages/driver/src/ToolOptions.cj:154-192,202-238` | wasm llc/lld 参数 |
| 26 | `packages/codegen/src/CGModule.cj:1235-1293` | layout/triple/CFFI 分派 |
| 27 | `packages/codegen/src/CGCFFI.cj:1-271` | wasm C ABI |
| 28 | `packages/codegen/src/IRBuilder.cj` | pointer width/header offset 审计 |
| 29 | `cangjie_tools/cjpm/src/config/cross_compile.cj:16-52` | 产物命名与 dylib 拒绝 |
| 30 | `cangjie_tools/cjpm/src/config/target.cj:327-425` | triple normalization |
| 31 | `cangjie_tools/cjpm/src/implement/run.cj` | 选择 host 执行 `.wasm` |
| 32 | `cangjie_tools/cjpm/src/implement/isolate.cj:13-28` | 替换 native isolate |

ToolChain 基类接口见
`cangjie_compiler/include/cangjie/Driver/Toolchains/ToolChain.h:26-63`；现实职责可参考
`include/cangjie/Driver/Toolchains/Gnu.h:22-73`。wasm 不应继承 `Gnu`，而应新增
`Wasm_CJNATIVE`，负责 wasm-capable `llc`、`lld -flavor wasm`/`wasm-ld`、
`llvm-ar`、WASI sysroot、静态链接、入口与 import/export、线性内存参数，并在 M0-M2
明确拒绝 target-side shared library。宏依赖继续由 host target 构建；现有 host/target
分离见 `cangjie_tools/cjpm/src/implement/build_parallel.cj:1228-1237,1322-1327`。

平台条件也是独立审计面。调研时 runtime/stdlib 有 627 条、cjcj packages 有 493 条
涉及 `os/arch/env/backend` 的 `@When`，合计 1120 条、129 个文件。不是每条都要修改，
但每条都要审计，尤其不能让 `os != "Windows"` 自动把 WASI 当 POSIX Linux。

### CodeGen 平台假设

| 类别 | 结论 | 源码锚与动作 |
|---|---|---|
| 指针宽度/DataLayout | 必须修改 | `CGModule.cpp:32-46` 与 `CGModule.cj:1263-1274` 只把 ARM32 当 32 位；`CJNativeIRBuilder.cpp:421-453` 同样需要按 pointer width 查询。 |
| 对象头/TypeInfo | 系统性重做 | `runtime/src/Base/Types.h:37-55`、`Common/StateWord.h:80-179`、`ObjectModel/RefField.h:117-180` 都将 ARM 与非 ARM 分开，wasm32 必须冻结独立 ABI 并重建 metadata/std/runtime。 |
| 内联汇编 | compiler 无需新增；runtime 重做 | compiler codegen 未发现发射 inline asm；runtime 有 80 个 `.S`，涵盖协程、异常恢复和 safepoint。 |
| 仓颉 ABI/GC CC | 必须新增 target lowering | `CodeGen/Utils/CGUtils.h:82-85` 给托管函数设置 `gc "cangjie"`，vendor patch 只有 X86/AArch64 对应路径。 |
| C ABI/varargs | 必须新实现 | `CGModule.cpp:90-108` 会把未知目标误退到 Linux AMD64；`CJNativeCGCFFI.cpp:144-169,739-768` 是 AMD64/AArch64 分类。 |
| 异常 | 现机制不可移植 | `EmitBasicBlockIR.cpp:117-136`、`CJNativeIRBuilder.cpp:360-397` 生成 landingpad/invoke；runtime `Exception.cpp:94-199`、`EhStackInfo.cpp:15-44` 与 `RestoreContextForEH.S:14-55` 操作 native frame/LSDA/寄存器。 |
| TLS | M1 替换，M3 重做 | `Mutator/ThreadLocal.cpp:17-18,58-110` 使用 C++ TLS 与固定 offset ABI；CJThread 另用 `__thread`。 |

## Runtime 八类阻塞面

### B1：CJThread 协程与原生栈切换

默认原生线程栈、协程栈与 guard 参数见
`runtime/src/CJThread/.../schedule_impl.h:32-40`。`cjthread.cpp:191-211,308-399,675-690`
分配独立栈并初始化 SP/PC；`gas/x86/x86_64/cjthread_context.S:23-114` 直接保存/恢复
`rsp/rip`。wasm 无法读取或替换引擎 value stack。

M0/M1 应明确禁用 `spawn`/Future 调度。Asyncify 只用于 demo 或原型；stack-switching
不能仅凭提案阶段进入发布基线。M3 推荐从 compiler lowering 到 scheduler 使用显式状态机/CPS，
并把挂起点、异常、GC roots 和 debug info 作为一个设计处理。

### B2：精确 GC 根发现

现有 GC 是精确 native stackmap，不是保守扫描：

- `runtime/src/Heap/Collector/TracingCollector.cpp:173-180,202-215` 从 frame 的
  start PC、frame PC 与 frame address 构造 `RootMap`，访问 slot、register 与 callee-saved roots。
- `runtime/src/UnwindStack/GcStackInfo.cpp:117-170,253-272` 分类并遍历 native frame。
- `runtime/src/StackMap/StackMap.h:45-129,220-251` 保存 slot roots、register roots、
  derived pointers，并按 PC/frame address 查询压缩 stackmap。

wasm guest 无法遍历引擎内部 value stack 或 locals；保守扫描线性内存既看不到这些引用，
也会误认整数并阻碍移动 GC。推荐由 vendor LLVM pass 在 safepoint 前把活 managed refs
写入线性内存 shadow root frame，记录 base/derived 关系，在正常返回和异常路径弹出。

M0 可限定无 heap allocation、无 GC safepoint；M1 不能绕过 B2。第一个 B2 原型必须覆盖
循环分配、移动 GC、深调用、异常穿越和 derived pointer，之后才能扩大 std 移植。

### B3：堆与地址空间

`RegionSpace.cpp:90-119` 预留连续 metadata+heap；`MemMap.cpp:48-97,115-127` 使用
`mmap`/`VirtualAlloc`、`mprotect` 与 unmap；`RegionInfo.h:553-586` 依赖
`MAP_FIXED` 与 `madvise`；`CjScheduler.cpp:637-660` 默认 heap 为 256 MiB。

wasm memory 只能通过 `memory.grow` 增长，释放只能回到 runtime 内部 free list。需要线性内存
arena，分区容纳静态数据、metadata、heap、shadow roots 与后续协程状态；同时冻结 wasm32
4 GiB 地址预算和 OOM 行为。

### B4：信号与 safepoint

`SignalStack.cpp:100-197`、`SignalUtils.cpp:49-80` 使用 signal/ucontext；CJThread guard
与 `Mutator.cpp:308-347` 使用 `mprotect`。现有 STW 也有显式 flag 与协作挂起路径，见
`Mutator.h:276-285`、`MutatorManager.cpp:409-414`、`Mutator.cpp:180-240`。

M1 单线程应改为显式 safepoint poll 与显式 stack bounds check；M3 再扩展为 atomics/host wake
的多线程 handshake。signal handler 与 guard-page 行为必须明确标为 unsupported，不能静默吞掉。

### B5：线程、原子与 TLS

`Mutator/ThreadLocal.cpp:17-18,58-110` 使用 C++ TLS，CJThread 使用 `__thread`；
`Heap/GcThreadPool.cpp:20-125` 与 `CollectorResources.cpp:215-241` 创建 pthread worker。
调研统计为 36 个 pthread 文件、52 个 atomic 文件，去重后 73 个文件。

M1 将 TLS 收敛为 runtime instance state，GC/finalizer 同步执行；M3 才引入 shared linear
memory、wasm atomics、worker lifecycle、真正 TLS 和多 mutator STW。浏览器构建还需要
`SharedArrayBuffer` 与 COOP/COEP，因此 threaded/non-threaded 应是两套 artifact。

### B6：系统调用与 WASI

系统接口集中在 `CJThread/src/base/syscall_common.cpp:27-83`、
`syscall_linux.cpp:74-120`、`aio/sock.cpp:1721-1768`；`StackManager.cpp:254,348,635`
读取 `/proc`，`CjScheduler.cpp:88-119` 读取环境变量。

WASI Preview 1 可覆盖 args/env、clock、random、preopened-dir fd/path I/O、poll/yield、
`proc_exit` 与有限 socket 操作，但不能提供 mmap/mprotect、signal/ucontext、pthread、
fork/exec、任意绝对路径、`/proc`、dlopen 或原生 epoll/kqueue/IOCP。M0-M2 以 P1 core
module 为基线，host adapter 独立封装；浏览器 DOM/HTTP/WebSocket 另行设计。

### B7：动态加载

`runtime/src/os/Loader.h:16-31`、`os/Linux/Loader.cpp:13-53` 定义并实现 native loader；
`LoaderManager.cpp:111-203` 同时支持预注册 metadata 与动态装载；
`CangjieRuntimeApi.cpp:713-782` 暴露动态库 API。

M0-M2 使用单 module 静态链接与启动期 metadata 注册。编译期宏仍在 host 构建，不是 target
runtime blocker。目标侧 `LoadCJLibrary`、hot unload 与运行时扩展装载明确不支持。

### B8：C FFI 与原生依赖闭包

stdlib/libs 中有 51 个 C/C++/头文件，分布在 16 个包；45 个仓颉文件声明 240 个
`foreign`。闭包入口见 `stdlib/libs/CMakeLists.txt:51-69`、
`stdlib/third_party/CMakeLists.txt:27-38`、`stdlib/third_party/Pcre2.cmake:7-94` 与
`runtime/CMakeLists.txt:360-425`。

| 依赖面 | 当前 wasm 产物 | 处置 |
|---|---|---|
| libc/libm/compiler-rt/libc++ | Cangjie SDK 无 | 引入钉版本 WASI sysroot |
| pthread/dl/native unwind | 无直接基线 | M1 删除依赖；M3 以 wasm threads/host adapter 重做 |
| boundscheck | 有 vendored C，无 wasm artifact | 静态 cross-build 并做 ABI/行为测试 |
| PCRE2 | 未验证当前配置 | wasm static；先做 2-3 天可编译性探针 |
| FlatBuffers | host `flatc` + generated C++ | `flatc` 留 host，runtime 静态 cross-build，审计 32 位格式 |
| 51 个 std native 文件 | 无 | 分类为 WASI import、portable C、unsupported |
| 用户 CFunc/unsafe | host `.a/.so` 不兼容 | 只收 wasm32 object/archive；M0-M2 禁动态 FFI |

## 设计决策

| 决策 | 推荐 | 理由与约束 |
|---|---|---|
| 目标风味 | `wasm32-unknown-wasi` | WASI 提供最小系统面；Emscripten 只用于浏览器 adapter/Asyncify 实验。 |
| 首个运行环境 | 固定版本 Wasmtime | 独立 runtime 可直接暴露 WASI；浏览器额外涉及事件循环、网络、DOM 与部署 header。 |
| GC 根发现 | shadow root stack | 最接近现有精确 GC，host 无关，能显式保存 base/derived roots。 |
| 协程 | M0/M1 无并发；M3 CPS/状态机 | 当前实现依赖 SP/PC；提案阶段不能替代 host 与 toolchain 实证。 |
| 异常 | M0 禁 throw/只 trap；M1 wasm EH | 不移植 native unwinder；先验证 vendor LLVM EH 和 typed exception/finally。 |
| 线程 | M1 单线程；M3 双构建 | runtime 73 个文件触及 pthread/atomic，浏览器部署另有 shared-memory 条件。 |

## 里程碑与工作量

“刀”是可独立 review、构建并有定向语义探针的改动单元。人周包含实现、测试和 review
修正，不含排队时间。

| 里程碑 | 能力 | 关键工作 | 刀数 | 人周 | 置信度 |
|---|---|---|---:|---:|---|
| M0 | 受限 hello world | vendor wasm target、triple/driver/linker、wasm32 layout、无分配 lowering、最小启动/output import | 12-16 | 8-12 | low |
| M1 | 单线程完整语言、GC、EH | shadow roots、wasm heap、32 位对象 ABI、显式 safepoint、wasm EH、TLS singleton | 28-38 | 24-38 | low |
| M2 | CLI 型 std 子集 | WASI P1 adapter、51 个 native 文件、PCRE2/boundscheck/FlatBuffers、平台条件审计 | 22-30 | 18-28 | medium-low |
| M3 | `spawn`/Future/并发 GC | CPS/状态机、TLS/atomics/worker、多 mutator STW、异步 I/O、双构建 | 24-34 | 24-38 | low |
| M4 | cjpm、CI、SDK、发布 | build/run/test、host macro/target dep、打包、矩阵、调试/体积/性能基线 | 14-20 | 12-18 | medium |
| **总计** | 产品化 wasm32 | | **100-138** | **86-134** | **low** |

4 名熟悉 compiler/runtime 的工程师并行时，考虑关键路径与集成损耗，日历期约 7-11 个月。
最小演示切片可进一步限制为：单一 output import、仅标量/局部变量/分支/循环/直接调用，
静态 bytes 字符串，禁对象、异常、反射、FFI、协程和线程，并固定 Wasmtime。该切片约
7-9 刀、4-6 人周，只证明 backend feasibility，不应对外称“支持 wasm”；第一个 managed
allocation 会立即进入 B2/M1。

## 未证实假设与核实成本

| 假设 | 当前状态 | 核实成本与产物 |
|---|---|---|
| vendor LLVM 15 的 generic Cangjie statepoint pass 能在 WebAssembly target 上运行到 ISel 前 | 未证实 | 3-5 天；最小 IR 到 wasm object 的 pass-by-pass matrix |
| 当前 PCRE2 版本和选项可无补丁静态 cross-build 到选定 WASI sysroot | 未证实 | 2-3 天；静态库与 regex 行为探针 |
| Cangjie wasm EH 可在 LLVM 15 的实现上稳定映射到目标引擎 | 未证实 | 1-2 周；typed exception/finally conformance，必要时给出升级或回移范围 |
| core language 的最小 runtime 初始化能避免第一次 allocation | 未证实 | 2-3 天；启动路径 allocation trace |

立项后的前两把风险刀应先于 driver UI：

1. 用含/不含 `gc "cangjie"` 的最小 Cangjie-flavored LLVM IR 通过新 WebAssembly
   target，定位第一个不支持的 calling convention、pass 或 ISel 点。
2. 让一个函数跨 safepoint 保存 slot root、register-like local 与 derived pointer，验证
   shadow-root ABI、异常清理和 verifier，再冻结 M1 设计。
