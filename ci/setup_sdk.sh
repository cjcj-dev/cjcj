#!/usr/bin/env bash
# Install the Cangjie bootstrap SDK and export the build env.
#   1. bootstrap cjv (github.com/Zxilly/cjv)
#   2. cjv install <pinned-nightly> -c stdx
#   2.5 swap the SDK's llc with the CI-built -O2-fixed llc artifact
#   3. repoint the libLLVM path hardcoded in packages/cjc/cjpm.toml at the SDK (CI checkout only)
#   4. write CANGJIE_HOME / CANGJIE_STDX_PATH / lib path / cjHeapSize / PATH to $GITHUB_ENV
#
# Env:
#   GITCODE_API_KEY  optional; nightly+stdx download publicly without it (accelerator only)
#   CJCJ_TOOLCHAIN   default nightly-1.2.0-alpha.20260721165458
#   CJV_VERSION      default v0.2.20
#   CJ_HEAP_SIZE     default 12GB (unset -> parse-phase OOM)
#   REPO_ROOT        default the script's parent dir
#   FIXED_LLC_GZ     source-built llc.gz artifact (required by Linux x86_64 CI)
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CJCJ_TOOLCHAIN="${CJCJ_TOOLCHAIN:-nightly-1.2.0-alpha.20260721165458}"
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

# 2.5 Swap the SDK's llc with the source-built -O2-fixed static llc.
#     The stock nightly llc miscompiles -O2 (SelectionDAG relocate-of-undef memory corruption;
#     cjcj-llvm fix/scheddag-memcorrupt). The backend lowered relocate-of-undef to a
#     materialized 0xFEFEFEFE sentinel in a callee-saved register; the compressed GC stackmap
#     records that register as a live root, so runtime GC dereferenced 0xFEFEFEFE and crashed
#     non-deterministically on 26.04/few-core heaps (task#11). Fix: lower relocate-of-undef to
#     getUNDEF (no register materialization, no phantom root) + filterGCPointer tolerates a
#     ConstantOp GC pointer. The fix is in llc (backend) only; opt/libLLVM are untouched. This
#     static llc is self-contained (no libLLVM dependency). Idempotent: skips if already fixed;
#     keeps the original as llc.orig once. CI downloads this file from the source-build artifact.
case "$OS/$ARCH" in
    Linux/x86_64) LLC_PLATFORM="linux_x86_64" ;;
    *)            LLC_PLATFORM="" ;;
esac
FIXED_LLC_GZ="${FIXED_LLC_GZ:-}"
SDK_LLC="$CANGJIE_HOME/third_party/llvm/bin/llc"
if [ -n "$LLC_PLATFORM" ] && [ -n "$FIXED_LLC_GZ" ]; then
    [ -f "$FIXED_LLC_GZ" ] || { log "FATAL: fixed llc artifact missing: $FIXED_LLC_GZ"; exit 4; }
    [ -f "$SDK_LLC" ] || { log "FATAL: SDK llc missing: $SDK_LLC"; exit 4; }
    FIXED_LLC_SHA="$(gunzip -c "$FIXED_LLC_GZ" | sha256sum | awk '{print $1}')"
    cur_sha="$(sha256sum "$SDK_LLC" | awk '{print $1}')"
    if [ "$cur_sha" != "$FIXED_LLC_SHA" ]; then
        [ -f "$SDK_LLC.orig" ] || cp -f "$SDK_LLC" "$SDK_LLC.orig"   # capture the true original once
        rm -f "$SDK_LLC"                                            # break any hardlink; don't overwrite in place
        gunzip -c "$FIXED_LLC_GZ" > "$SDK_LLC"
        chmod 0755 "$SDK_LLC"
        got_sha="$(sha256sum "$SDK_LLC" | awk '{print $1}')"
        [ "$got_sha" = "$FIXED_LLC_SHA" ] || { log "FATAL: fixed llc artifact sha mismatch ($got_sha)"; exit 4; }
        log "swapped SDK llc -> source-built -O2-fixed ($FIXED_LLC_SHA)"
    else
        log "SDK llc already -O2-fixed; skip"
    fi
elif [ -n "$LLC_PLATFORM" ] && [ -n "${CI:-}" ]; then
    log "FATAL: FIXED_LLC_GZ is required for Linux x86_64 CI"
    exit 4
else
    log "no source-built fixed llc artifact for $OS/$ARCH; keeping stock llc"
fi

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
