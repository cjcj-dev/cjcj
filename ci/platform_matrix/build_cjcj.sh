#!/usr/bin/env bash
# Provision the official host nightly SDK, then attempt an O1 workspace build.
# O1 is intentional for this first platform bring-up matrix: only Linux x64 has
# a source-built fixed llc today. Missing platform shim/link support must fail
# visibly rather than being hidden.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ci/platform_matrix/common.sh
source "$HERE/common.sh"
stage_begin cjcj

TOOLCHAIN="${CJCJ_TOOLCHAIN:-nightly-1.2.0-alpha.20260721165458}"
setup_rc=0
case "$(uname -s)" in
    MINGW*|MSYS*)
        pwsh.exe -NoLogo -NoProfile -File "$HERE/setup_sdk.ps1" || setup_rc=$?
        win_home="${USERPROFILE:?USERPROFILE is required}\\.cjv\\toolchains\\$TOOLCHAIN"
        CANGJIE_HOME="$(cygpath -u "$win_home")"
        CANGJIE_STDX_PATH="$(cygpath -u "${USERPROFILE}\\.cjv\\stdx\\$TOOLCHAIN\\static\\stdx")"
        export CANGJIE_HOME CANGJIE_STDX_PATH
        export PATH="$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$CANGJIE_HOME/runtime/lib/windows_x86_64_cjnative:$CANGJIE_HOME/tools/lib:$PATH"
        ;;
    *)
        # O1 does not consume fixed llc. Override GitHub's CI=true only for the
        # installer so Linux x64 keeps the stock llc instead of failing before
        # the requested platform build attempt.
        CI= FIXED_LLC_GZ= bash ci/setup_sdk.sh || setup_rc=$?
        CANGJIE_HOME="$HOME/.cjv/toolchains/$TOOLCHAIN"
        CANGJIE_STDX_PATH="$HOME/.cjv/stdx/$TOOLCHAIN/static/stdx"
        export CANGJIE_HOME CANGJIE_STDX_PATH
        export PATH="$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$HOME/.local/bin:$PATH"
        if [ "$(uname -s)" = Darwin ]; then
            export DYLD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/${SDK_RUNTIME_DIR:?}:$CANGJIE_HOME/tools/lib"
            xattr -dr com.apple.quarantine "$CANGJIE_HOME" 2>/dev/null || true
        else
            export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/${SDK_RUNTIME_DIR:?}:$CANGJIE_HOME/tools/lib"
        fi
        ;;
esac
export cjHeapSize="${CJ_HEAP_SIZE:-12GB}"

print_common_versions
printf 'sdk_toolchain=%s\nsdk_archive=%s\nsdk_home=%s\noptimization=O1\nsetup_rc=%s\n' \
    "$TOOLCHAIN" "${SDK_ARCHIVE:-unknown}" "$CANGJIE_HOME" "$setup_rc"
cjv --version || true
cjc --version || true
cjpm --version || true
if [ -x "$CANGJIE_HOME/third_party/llvm/bin/llc" ]; then
    "$CANGJIE_HOME/third_party/llvm/bin/llc" --version | head -n 5 || true
fi

# Runtime-only checkout mutation: the repository remains O2 by default.
sed 's/compile-option = "-O2"/compile-option = "-O1"/' cjpm.toml > "$PLATFORM_CI_ROOT/cjpm.O1.toml"
cp "$PLATFORM_CI_ROOT/cjpm.O1.toml" cjpm.toml

shim_rc=0
bash runtime_shim/build_shim.sh || shim_rc=$?
echo "shim_rc=$shim_rc; continuing to cjpm build so the platform frontier is recorded"
build_rc=0
cjpm build || build_rc=$?
printf 'setup_rc=%s shim_rc=%s build_rc=%s\n' "$setup_rc" "$shim_rc" "$build_rc"

if [ "$setup_rc" -ne 0 ]; then exit "$setup_rc"; fi
if [ "$shim_rc" -ne 0 ]; then exit "$shim_rc"; fi
exit "$build_rc"
