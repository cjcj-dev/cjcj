#!/usr/bin/env bash
# Install the Cangjie bootstrap SDK and export the build env.
#   1. bootstrap cjv (github.com/Zxilly/cjv)
#   2. cjv install <pinned-nightly> -c stdx
#   3. repoint the libLLVM path hardcoded in packages/cjc/cjpm.toml at the SDK (CI checkout only)
#   4. write CANGJIE_HOME / CANGJIE_STDX_PATH / lib path / cjHeapSize / PATH to $GITHUB_ENV
#
# Env:
#   GITCODE_API_KEY  optional; nightly+stdx download publicly without it (accelerator only)
#   CJCJ_TOOLCHAIN   default nightly-1.2.0-alpha.20260712020030
#   CJV_VERSION      default v0.2.20
#   CJ_HEAP_SIZE     default 12GB (unset -> parse-phase OOM)
#   REPO_ROOT        default the script's parent dir
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CJCJ_TOOLCHAIN="${CJCJ_TOOLCHAIN:-nightly-1.2.0-alpha.20260712020030}"
CJV_VERSION="${CJV_VERSION:-v0.2.20}"
CJ_HEAP_SIZE="${CJ_HEAP_SIZE:-12GB}"

log() { echo "[setup_sdk] $*"; }

# Host -> cjv asset name and runtime lib dir.
OS="$(uname -s)"; ARCH="$(uname -m)"
case "$OS/$ARCH" in
    Linux/x86_64)          CJV_ASSET="cjv_linux_amd64.tar.gz";  RT_DIR="linux_x86_64_cjnative" ;;
    Linux/aarch64)         CJV_ASSET="cjv_linux_arm64.tar.gz";  RT_DIR="linux_aarch64_cjnative" ;;
    Darwin/arm64)          CJV_ASSET="cjv_darwin_arm64.tar.gz"; RT_DIR="darwin_aarch64_cjnative" ;;
    Darwin/x86_64)         CJV_ASSET="cjv_darwin_amd64.tar.gz"; RT_DIR="darwin_x86_64_cjnative" ;;
    *) log "unsupported host $OS/$ARCH"; exit 2 ;;
esac

# 1. bootstrap cjv
if ! command -v cjv >/dev/null 2>&1; then
    log "install cjv $CJV_VERSION"
    TOOLS="$HOME/.local/bin"; mkdir -p "$TOOLS"
    TMP="$(mktemp -d)"
    curl -fsSL -o "$TMP/cjv.tar.gz" \
        "https://github.com/Zxilly/cjv/releases/download/${CJV_VERSION}/${CJV_ASSET}"
    tar -C "$TMP" -xzf "$TMP/cjv.tar.gz"
    install -m0755 "$(find "$TMP" -type f -name cjv | head -1)" "$TOOLS/cjv"
    export PATH="$TOOLS:$PATH"
fi
log "cjv $(cjv --version 2>/dev/null || true)"

# 2. install toolchain + stdx (GITCODE_API_KEY optional)
if [ -n "${GITCODE_API_KEY:-}" ]; then
    cjv set gitcode-api-key "$GITCODE_API_KEY" >/dev/null 2>&1 || true
    log "gitcode-api-key set"
fi
log "cjv install $CJCJ_TOOLCHAIN -c stdx"
cjv install "$CJCJ_TOOLCHAIN" -c stdx

CANGJIE_HOME="$HOME/.cjv/toolchains/$CJCJ_TOOLCHAIN"
[ -d "$CANGJIE_HOME" ] || { log "toolchain dir missing: $CANGJIE_HOME"; exit 3; }
STDX_PATH="$HOME/.cjv/stdx/$CJCJ_TOOLCHAIN/static/stdx"

# 3. Repoint the libLLVM dir hardcoded in cjpm.toml (a /root/.cjv/... path unreadable to the
#    runner user, mode 0700) at this SDK. CI checkout only; repo file untouched, local dev unaffected.
if [ -n "${GITHUB_ENV:-}${CI:-}" ]; then
    CJPM_TOML="$REPO_ROOT/packages/cjc/cjpm.toml"
    SDK_LLVM_DIR="$CANGJIE_HOME/third_party/llvm/lib"
    HARD_DIR="$(grep -oE "/[^ '\"]*/third_party/llvm/lib" "$CJPM_TOML" 2>/dev/null | head -1 || true)"
    if [ -n "$HARD_DIR" ] && [ "$HARD_DIR" != "$SDK_LLVM_DIR" ]; then
        # portable in-place edit (BSD/GNU sed); replaces both the .so path and the -rpath
        sed "s#${HARD_DIR}#${SDK_LLVM_DIR}#g" "$CJPM_TOML" > "$CJPM_TOML.tmp" && mv "$CJPM_TOML.tmp" "$CJPM_TOML"
        log "repoint cjpm.toml LLVM dir -> $SDK_LLVM_DIR"
    fi
fi

# 4. export env (DYLD_LIBRARY_PATH on macOS, LD_LIBRARY_PATH on Linux)
if [ "$OS" = "Darwin" ]; then LD_VAR="DYLD_LIBRARY_PATH"; else LD_VAR="LD_LIBRARY_PATH"; fi
LD_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/$RT_DIR:$CANGJIE_HOME/tools/lib"
if [ -n "${GITHUB_ENV:-}" ]; then
    {
        echo "CANGJIE_HOME=$CANGJIE_HOME"
        echo "CANGJIE_STDX_PATH=$STDX_PATH"
        echo "${LD_VAR}=$LD_PATH"
        echo "cjHeapSize=$CJ_HEAP_SIZE"
    } >> "$GITHUB_ENV"
    # cjpm lives in tools/bin (bin/ has only cjc/cjc-frontend); both must be on PATH.
    echo "$CANGJIE_HOME/bin" >> "$GITHUB_PATH"
    echo "$CANGJIE_HOME/tools/bin" >> "$GITHUB_PATH"
    echo "$HOME/.local/bin" >> "$GITHUB_PATH"
    log "env -> \$GITHUB_ENV ($LD_VAR)"
else
    cat <<EOF
export CANGJIE_HOME=$CANGJIE_HOME
export PATH=$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:\$PATH
export ${LD_VAR}=$LD_PATH
export CANGJIE_STDX_PATH=$STDX_PATH
export cjHeapSize=$CJ_HEAP_SIZE
EOF
fi
log "CANGJIE_HOME=$CANGJIE_HOME"
