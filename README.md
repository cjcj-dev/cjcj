# cangjie-build

[仓颉（Cangjie）](https://gitcode.com/Cangjie) SDK 的工程化构建流水线，使用
Python + [uv](https://docs.astral.sh/uv/) 实现，并配套 GitHub Actions 工作流。

## 支持的目标

| Target        | Runner          | 模式                                                 |
| ------------- | --------------- | ---------------------------------------------------- |
| `linux-x64`   | `ubuntu-22.04`  | 原生构建（Ubuntu 22.04，clang-15）                   |
| `windows-x64` | `ubuntu-22.04`  | 通过 llvm-mingw + openssl（mstorsjo）交叉编译        |

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

`run-all` 子命令会按顺序串联以上所有步骤（主要用于本地调试）。

## 持续集成

`.github/workflows/build-cangjie.yml` 提供 `workflow_dispatch` 触发器，参数
与上游 `tozi-team/cangjie_build` 工作流保持一致：全局 `tag`、按仓库覆盖的
URL/tag、`build_type`、`run_tests`。`linux-x64` 与 `windows-x64` 在矩阵中
并行构建，两个 job 都会上传主 SDK 归档 + STDX 归档作为 artifact。

`sccache` 由 [`mozilla-actions/sccache-action`](https://github.com/mozilla-actions/sccache-action)
提供，并启用了
[多级缓存](https://github.com/mozilla/sccache/blob/main/docs/MultiLevel.md)：
本地磁盘作为 L0（同 job 内重复编译命中），GitHub Actions Cache 作为 L1
（跨 job、跨 run 持久化）。写策略 `l0` 表示 L0 写入成功即视为成功，
GHA 写入失败仅记录日志，不影响构建。

```yaml
SCCACHE_GHA_ENABLED: "true"
SCCACHE_MULTILEVEL_CHAIN: "disk,gha"
SCCACHE_MULTILEVEL_WRITE_ERROR_POLICY: "l0"
SCCACHE_DIR: ${{ github.workspace }}/.sccache
SCCACHE_CACHE_SIZE: "5G"
```

只要 `which sccache` 成功，CLI 会自动通过 CMake 的
`CMAKE_C_COMPILER_LAUNCHER=sccache` /
`CMAKE_CXX_COMPILER_LAUNCHER=sccache` 启用它。

## 代码质量

```bash
uv run ruff check .
uv run ruff format --check .
uv run ty check
uv run pyright           # strict 模式
uv run pytest
```

CI 中的 lint job 会运行同样的检查。

## License

Apache-2.0（详见 `LICENSE`）。
