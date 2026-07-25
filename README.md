# cjcj

用仓颉语言重写的仓颉编译器。产物名为 `cjc`，命令行与官方编译器保持一致。

## 状态

v0.0.1（预发布）。编译器已能编译自身源码，与官方编译器的字节级一致性比对在 CI 中持续运行。

支持平台：Linux x64、Linux aarch64、macOS x64、macOS arm64、Windows x64。

## 安装

从 [Releases](https://github.com/cjcj-dev/cjcj/releases) 下载对应平台的压缩包，用同名 `.sha256`
校验后解压。压缩包是一套可重定位的完整 SDK，自带运行时与标准库：

```sh
tar xf cjcj-0.0.1-linux-x64.tar.gz
source cjcj-0.0.1-linux-x64/envsetup.sh
cjc hello.cj -o hello
```

Windows 解压后直接使用 `bin\cjc.exe`。

## 从源码构建

需要官方仓颉 SDK 与 Node.js。完整步骤以 CI 为准（`.github/workflows/ci.yml`），最小路径：

```sh
npx --yes zx@8 ci/setup_sdk.mjs   # 安装并配置官方 SDK
cjpm build                        # 构建编译器
```

## 文档

- [docs/ROADMAP.md](docs/ROADMAP.md) — 路线图
- [docs/STATUS.md](docs/STATUS.md) — 各模块状态
