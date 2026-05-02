# cangjie-build

[仓颉（Cangjie）](https://gitcode.com/Cangjie) SDK 的工程化构建流水线，使用
Python + [uv](https://docs.astral.sh/uv/) 实现，并配套 GitHub Actions 工作流。

## 支持的目标

| Target        | 模式                                              |
| ------------- | ------------------------------------------------- |
| `linux-x64`   | 原生构建（Ubuntu 22.04 + clang-15）               |
| `windows-x64` | 通过 llvm-mingw + openssl（mstorsjo）交叉编译     |

> macOS / aarch64 / OHOS 等目标暂未实现，但 `targets.py` 中的策略类已经
> 预留了扩展点。

## 本地快速上手（Ubuntu 22.04）

```bash
uv sync
uv run cangjie-build --target linux-x64 install-system-deps
uv run cangjie-build --target linux-x64 install-static-libs
uv run cangjie-build --target linux-x64 fetch
uv run cangjie-build --target linux-x64 build compiler
uv run cangjie-build --target linux-x64 build runtime
uv run cangjie-build --target linux-x64 build stdlib
uv run cangjie-build --target linux-x64 build stdx
uv run cangjie-build --target linux-x64 build tools
uv run cangjie-build --target linux-x64 package
uv run cangjie-build --target linux-x64 verify
```

`run-all` 子命令把以上步骤串成一条线（主要用于本地调试）。`windows-x64`
目标把 `install-static-libs` 换成 `install-mingw`。

## 交叉编译涉及的上游补丁

`fetch` 阶段克隆 cangjie 源码后，对 `cangjie_compiler` 应用两处 cmake
补丁，把 lldb 的 `ExternalProject_Add` 真正卡在 `cangjie-frontend` /
`cangjie-lsp-share` 之后（上游只挂在 ExternalProject 顶层 target 上，
CMP0114 OLD 行为下卡不住 build step，会出现 `libcangjie-frontend.dll.a
missing` 的竞态）：

- `third_party/cmake/BuildCJDB.cmake`：加 `cmake_policy(SET CMP0114 NEW)`
  + `STEP_TARGETS build configure`
- `src/CMakeLists.txt`：在 `CANGJIE_BUILD_CJDB` 块里追加
  `add_dependencies(lldb-build cangjie-frontend cangjie-lsp-share)`

`tools` 阶段对 `cjpm/build/build.py` 应用一处补丁：把 cross-windows
链接行硬编码的 `/opt/buildtools/llvm-mingw-w64/x86_64-w64-mingw32/lib`
改为 `$MINGW_PATH/x86_64-w64-mingw32/lib`，这样不依赖上游
`linux_cross_windows_zh.md` 假设的 `/opt/buildtools` 路径。

补丁逻辑统一走 `_common.apply_text_patch()`，匹配不到旧字串会抛
`BuildError("...patch shape drift...")`，让上游重命名时大声失败而不是
静默 no-op。

windows 交叉编译的 build_type 在 `cfg.cross_build_type` 里硬编码为
`release`：上游 `relwithdebinfo` 路径在 MinGW 上有多处问题
（`src/CMakeLists.txt:272` 把 cangjie-frontend 切到静态 `.a`，
`-fdebug-types-section` 被注入 pcre2 但 clang 在 `x86_64-w64-windows-gnu`
上拒绝），与 linux-host 的 `--build-type` 选择无关。

链接器统一走 lld：`base_env` 设 `LDFLAGS=-fuse-ld=lld`，cmake 在首次
configure 时把它拷进 `CMAKE_*_LINKER_FLAGS_INIT`；llvm-mingw 自带
lld，cangjie 自带的 clang 在 cjc emit 时也用 lld。

## 持续集成

仓库提供两条工作流：

- `.github/workflows/build-cangjie.yml` — GitHub Actions 托管 runner 上
  的矩阵构建（`linux-x64` + `windows-x64`），多级 sccache（disk L0 +
  GHA L1）。`workflow_dispatch` 触发器参数与上游 `tozi-team/cangjie_build`
  对齐：全局 `tag`、按仓库覆盖的 URL/tag、`build_type`、`run_tests`。
- `.github/workflows/build-cangjie-azure.yml` — Azure ephemeral VM 跑
  `windows-x64` cross-compile（默认 `Standard_F16als_v7` spot，区域
  fallback `eastus2 → eastus`）。GHA cache API 在重活下会 429
  限流，改成把 sccache 写入 Azure Blob 容器（`SCCACHE_AZURE_BLOB_CONTAINER=sccache`）。

只要 `which sccache` 成功，CLI 就会通过 cmake 的
`CMAKE_C_COMPILER_LAUNCHER=sccache` /
`CMAKE_CXX_COMPILER_LAUNCHER=sccache` 启用它。注意 sccache 只覆盖
C/C++ 编译；cjc 编译 .cj 源、链接 step、cmake configure、install 拷贝
都不缓存，warm-cache 整体仍要约 12–17 分钟（compiler + tools 占大头）。

## 代码质量

```bash
uv run ruff check .
uv run ruff format --check .
uv run ty check
uv run pyright           # strict 模式
uv run pytest
```

`build-cangjie.yml` 的 lint job 跑同样的检查。Python 锁在
`>=3.11,<3.13`：cangjie 的 lldb 15 还在用 `PyEval_ThreadsInitialized`，
3.13 里被移除会编译失败。

## License

Apache-2.0（详见 `LICENSE`）。
