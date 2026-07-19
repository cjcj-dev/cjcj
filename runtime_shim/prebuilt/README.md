# runtime_shim/prebuilt — 预编译 shim 目标文件(按平台)

## 为什么要 vendor 预编译 `.o`

`cjselfhost_llvmshim.cpp` 引用了**仓颉补丁版 LLVM** 才有的 GC intrinsic:

- `llvm::Intrinsic::cj_gcread_static_struct`
- `llvm::Intrinsic::cj_gcwrite_static_struct`

这些符号只存在于 C++ 编译器构建树生成的
`build/build/third_party/llvm/include/llvm/IR/IntrinsicEnums.inc` 里。**stock LLVM 15
头文件编不过**(实测 `clang++-15` + `/usr/lib/llvm-15/include` 报 3 处
`no member named 'cj_gc*_static_struct'`),而发布版 SDK 的 `third_party/llvm/` 只带
`bin`+`lib`、**不带任何 LLVM 头**。

结论:干净机器(GitHub Actions runner)**无法从源码重建该 shim**。因此把已在开发机
用补丁版头编好的 `.o` 按平台 vendor 进本目录,`build_shim.sh` 的第三条 fallback 会在
找不到补丁版源码树、也没有本地 `.o` 时,直接拷贝对应平台的预编译件。

该 `.o` 与 SDK 的 `libLLVM-15.so` 的 C++ ABI 绑定;两者都是 LLVM 15.0.x 补丁版,ABI 兼容。

## 目录约定

```
prebuilt/<platform>/cjselfhost_llvmshim.o
```

`<platform>` 由 `build_shim.sh` 依 `uname -s`/`uname -m` 推导:

| 平台            | 目录             | 现状                         |
|-----------------|------------------|------------------------------|
| Linux x86_64    | `linux_x86_64`   | ✅ 已提供(开发机原生编译)  |
| Linux aarch64   | `linux_aarch64`  | ✅ 已提供(x86_64 交叉编译)  |
| macOS aarch64   | `darwin_aarch64` | ⬜ 缺(见 REPORT-relmatrix)  |
| macOS x86_64    | `darwin_x86_64`  | ⬜ 缺(见 REPORT-relmatrix)  |

Linux 两 arch 均有 `.o`,Release matrix 覆盖 linux-x64 + linux-aarch64;macOS/Windows
无 `.o` 且改名 `cjc` 另需 runtime 补丁扩展到 Mach-O/PE section 门,显式列为 BLOCKED
(见 `reports/REPORT-relmatrix.md`),绝不放假绿 job。

## 如何再生某平台的 `.o`(开发机,需补丁版 LLVM 头)

在装有 C++ 参照编译器构建树的机器上:

```bash
cd runtime_shim
rm -f cjselfhost_llvmshim.o
CANGJIE_CPP_SRC=/path/to/cangjie_compiler bash build_shim.sh   # 从补丁版头编译
mkdir -p prebuilt/<platform>
cp cjselfhost_llvmshim.o prebuilt/<platform>/cjselfhost_llvmshim.o
```

## 当前 linux_x86_64 记录

- 来源:开发机 `clang++-15`(Ubuntu 15.0.7) + `cangjie_compiler/build/build/{third_party/llvm/include,include,schema}` 补丁版头,`-std=c++17 -O2 -fPIC -fno-rtti -fno-exceptions`。
- 导出 `LLVMSelfhost*` / `LLVMGlobalObjectAddStringAttribute` 符号数:98
- sha256:`2015741dc63932c618180bf813852e4b0744eb5f4de6b316a21e68d810b03302`

## 当前 linux_aarch64 记录

- 来源:x86_64 开发机**交叉编译**——`aarch64-linux-gnu-g++`(GCC 14.2.0) + 同一套补丁版
  LLVM 头(`IntrinsicEnums.inc` 的 `cj_gc*` intrinsic 与生成的 flatbuffers 头均与目标 arch 无关),
  `-std=c++17 -O2 -fPIC -fno-rtti -fno-exceptions`。仅 `-c` 产 `.o`,未定义 LLVM 符号在目标机
  链接期对 aarch64 `libLLVM-15.so` 解析。
- ELF:`ELF 64-bit LSB relocatable, ARM aarch64`;导出 `LLVMSelfhost*`/`CJOF*` 符号数:100
- sha256:`34194deed72a026f8730945595f448e4fbb11c13600c5d095c8f4a17e1d9000a`
- 验收口径:交叉编译无法在本机链接/运行,linux-aarch64 的真实链接+冒烟由 arm CI runner 门验;
  若 arm 门失败即回落 BLOCKED。
