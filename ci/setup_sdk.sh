#!/usr/bin/env bash
# 在 CI runner 上准备 cjcj 的构建工具链(引导用官方仓颉 SDK)。
#
# 做四件事:
#   1. bootstrap cjv(github.com/Zxilly/cjv,公开发布的单文件 Go 二进制)
#   2. cjv install <pinned-nightly> -c stdx  —— 安装 cjcj 开发所锚定的确切 nightly + stdx
#   3. 把 packages/cjc/cjpm.toml 里硬编码的 libLLVM-15.so 绝对路径,symlink 到本次下载的 SDK
#      (默认方案:不改 cjpm.toml;见 REPORT 的「LLVM 路径」小节)
#   4. 把构建环境五件套 + cjHeapSize 写进 $GITHUB_ENV(无则打印)
#
# 需要的环境变量:
#   GITCODE_API_KEY   （必需)拉取 nightly SDK 用;CI 里来自 secrets.GITCODE_API_KEY
#   CJCJ_TOOLCHAIN    （可选)默认锁定 nightly-1.2.0-alpha.20260712020030
#   CJV_VERSION       （可选)默认 v0.2.20
#   CJ_HEAP_SIZE      （可选)默认 12GB(16GB runner;⚠不设会在解析阶段 OOM)
#   REPO_ROOT         （可选)仓库根,默认脚本上上级目录
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CJCJ_TOOLCHAIN="${CJCJ_TOOLCHAIN:-nightly-1.2.0-alpha.20260712020030}"
CJV_VERSION="${CJV_VERSION:-v0.2.20}"
CJ_HEAP_SIZE="${CJ_HEAP_SIZE:-12GB}"

log() { echo "[setup_sdk] $*"; }

# --- 平台探测(决定 cjv 资产名 与 runtime host 库目录名)-------------------------
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS/$ARCH" in
    Linux/x86_64)          CJV_ASSET="cjv_linux_amd64.tar.gz";  RT_DIR="linux_x86_64_cjnative" ;;
    Linux/aarch64)         CJV_ASSET="cjv_linux_arm64.tar.gz";  RT_DIR="linux_aarch64_cjnative" ;;
    Darwin/arm64)          CJV_ASSET="cjv_darwin_arm64.tar.gz"; RT_DIR="darwin_aarch64_cjnative" ;;
    Darwin/x86_64)         CJV_ASSET="cjv_darwin_amd64.tar.gz"; RT_DIR="darwin_x86_64_cjnative" ;;
    *) log "unsupported host $OS/$ARCH"; exit 2 ;;
esac

# --- 1. bootstrap cjv ------------------------------------------------------------
if ! command -v cjv >/dev/null 2>&1; then
    log "downloading cjv $CJV_VERSION ($CJV_ASSET)"
    TOOLS="$HOME/.local/bin"; mkdir -p "$TOOLS"
    TMP="$(mktemp -d)"
    curl -fsSL -o "$TMP/cjv.tar.gz" \
        "https://github.com/Zxilly/cjv/releases/download/${CJV_VERSION}/${CJV_ASSET}"
    tar -C "$TMP" -xzf "$TMP/cjv.tar.gz"
    install -m0755 "$(find "$TMP" -type f -name cjv | head -1)" "$TOOLS/cjv"
    export PATH="$TOOLS:$PATH"
fi
log "cjv: $(command -v cjv) $(cjv --version 2>/dev/null || true)"

# --- 2. 安装 pinned nightly + stdx ----------------------------------------------
if [ -n "${GITCODE_API_KEY:-}" ]; then
    cjv set gitcode-api-key "$GITCODE_API_KEY" >/dev/null 2>&1 || true
else
    log "WARN: GITCODE_API_KEY 未设置,nightly SDK 拉取很可能失败(请在仓库 Secrets 里配置)"
fi
log "installing toolchain $CJCJ_TOOLCHAIN (+stdx component)"
cjv install "$CJCJ_TOOLCHAIN" -c stdx

# --- 计算路径 --------------------------------------------------------------------
CANGJIE_HOME="$HOME/.cjv/toolchains/$CJCJ_TOOLCHAIN"
[ -d "$CANGJIE_HOME" ] || { log "toolchain dir missing: $CANGJIE_HOME"; exit 3; }
STDX_PATH="$HOME/.cjv/stdx/$CJCJ_TOOLCHAIN/static/stdx"

# --- 3. 同步 cjpm.toml 里硬编码的 libLLVM 绝对路径 ------------------------------
# 从 cjpm.toml 里读出该绝对路径(避免脚本与仓库不同步),symlink 到本次 SDK 的 libLLVM。
LLVM_HARD="$(grep -oE '/[^ ]*/third_party/llvm/lib/libLLVM-15\.so' "$REPO_ROOT/packages/cjc/cjpm.toml" | head -1 || true)"
SDK_LLVM="$CANGJIE_HOME/third_party/llvm/lib/libLLVM-15.so"
if [ -n "$LLVM_HARD" ] && [ ! -e "$LLVM_HARD" ]; then
    LLVM_HARD_DIR="$(dirname "$LLVM_HARD")"
    log "linking hardcoded LLVM path $LLVM_HARD -> $SDK_LLVM"
    if mkdir -p "$LLVM_HARD_DIR" 2>/dev/null; then :; else sudo mkdir -p "$LLVM_HARD_DIR"; fi
    if ln -sfn "$SDK_LLVM" "$LLVM_HARD" 2>/dev/null; then :; else sudo ln -sfn "$SDK_LLVM" "$LLVM_HARD"; fi
fi

# --- 4. 导出环境 -----------------------------------------------------------------
LD_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/$RT_DIR:$CANGJIE_HOME/tools/lib"
if [ -n "${GITHUB_ENV:-}" ]; then
    {
        echo "CANGJIE_HOME=$CANGJIE_HOME"
        echo "CANGJIE_STDX_PATH=$STDX_PATH"
        echo "LD_LIBRARY_PATH=$LD_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        echo "cjHeapSize=$CJ_HEAP_SIZE"
    } >> "$GITHUB_ENV"
    echo "$CANGJIE_HOME/bin" >> "$GITHUB_PATH"
    echo "$HOME/.local/bin" >> "$GITHUB_PATH"
    log "exported env to \$GITHUB_ENV"
else
    cat <<EOF
# eval these:
export CANGJIE_HOME=$CANGJIE_HOME
export PATH=$CANGJIE_HOME/bin:\$PATH
export LD_LIBRARY_PATH=$LD_PATH
export CANGJIE_STDX_PATH=$STDX_PATH
export cjHeapSize=$CJ_HEAP_SIZE
EOF
fi
log "SDK ready: CANGJIE_HOME=$CANGJIE_HOME"
