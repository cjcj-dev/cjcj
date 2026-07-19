#!/usr/bin/env bash
# Compile the self-host LLVM FFI C-shim into a relocatable object linked into cjc.
# Run once before `cjpm build` (the object is referenced by packages/cjc/cjpm.toml
# link-option). LLVM headers come from the C++ compiler source tree (LLVM 15.0.4,
# the same version cjc links at runtime: libLLVM-15.so).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
CPP="${CANGJIE_CPP_SRC:-/root/cj_build/cangjie_compiler}"
LLVM_SRC_INC="$CPP/third_party/llvm-project/llvm/include"
LLVM_GEN_INC="$CPP/build/build/third_party/llvm/include"
FLATBUFFERS_INC="$CPP/build/build/include"
SCHEMA_GEN_INC="$CPP/build/build/schema"
CXX="${CXX:-clang++}"
if ! command -v "$CXX" >/dev/null 2>&1 && command -v clang++-15 >/dev/null 2>&1; then
    CXX=clang++-15
fi
CC="${CC:-cc}"

# Host -> vendored prebuilt .o dir (shim needs patched-LLVM headers absent on CI; see
# runtime_shim/prebuilt/README.md).
HOST_OS="$(uname -s)"
HOST_ARCH="$(uname -m)"
case "${HOST_OS}/${HOST_ARCH}" in
    Linux/x86_64)           PREBUILT_PLAT="linux_x86_64" ;;
    Linux/aarch64|Linux/arm64) PREBUILT_PLAT="linux_aarch64" ;;
    Darwin/arm64|Darwin/aarch64) PREBUILT_PLAT="darwin_aarch64" ;;
    Darwin/x86_64)          PREBUILT_PLAT="darwin_x86_64" ;;
    *)                      PREBUILT_PLAT="" ;;
esac
PREBUILT_O="$HERE/prebuilt/${PREBUILT_PLAT}/cjselfhost_llvmshim.o"

"$CC" -std=c11 -O2 -fPIC -D_POSIX_C_SOURCE=200809L \
  -c "$HERE/cjc_runtime_config.c" -o "$HERE/cjc_runtime_config.o"

# Resolve the shim .o in priority order. The LLVM-header probe lives inside the
# source-compile branch so a CI machine (no headers, no C++ tree) reaches the prebuilt
# branch instead of failing the probe. -fno-rtti/-fno-exceptions match the LLVM ABI.
if [ -f "$HERE/cjselfhost_llvmshim.o" ]; then
    echo "reusing existing cjselfhost_llvmshim.o"
elif [ -d "$FLATBUFFERS_INC" ] && [ -d "$SCHEMA_GEN_INC/flatbuffers" ]; then
    # source build (dev machine with the patched-LLVM C++ tree)
    if [ -d "$LLVM_SRC_INC" ] && [ -d "$LLVM_GEN_INC" ]; then
        LLVM_INCLUDE_ARGS=(-I"$LLVM_SRC_INC" -I"$LLVM_GEN_INC")
    elif command -v llvm-config-15 >/dev/null 2>&1; then
        LLVM_INCLUDE_ARGS=(-I"$(llvm-config-15 --includedir)")
    else
        echo "ERR: LLVM 15 headers not found (needed only to compile the shim from source)" >&2
        exit 1
    fi
    "$CXX" -std=c++17 -O2 -fPIC -fno-rtti -fno-exceptions \
      -c "$HERE/cjselfhost_llvmshim.cpp" -o "$HERE/cjselfhost_llvmshim.o" \
      "${LLVM_INCLUDE_ARGS[@]}" -I"$FLATBUFFERS_INC" -I"$SCHEMA_GEN_INC"
elif [ -n "$PREBUILT_PLAT" ] && [ -f "$PREBUILT_O" ]; then
    # vendored prebuilt (CI)
    cp "$PREBUILT_O" "$HERE/cjselfhost_llvmshim.o"
    echo "used vendored prebuilt shim: $PREBUILT_O"
else
    echo "ERR: cannot obtain cjselfhost_llvmshim.o — none of: (1) a pre-existing local .o," >&2
    echo "     (2) the patched-LLVM C++ source tree (to compile from source), (3) a vendored" >&2
    echo "     prebuilt for ${HOST_OS}/${HOST_ARCH} (expected at $PREBUILT_O) is available." >&2
    exit 1
fi

echo "built: $HERE/cjselfhost_llvmshim.o"
echo "built: $HERE/cjc_runtime_config.o"
nm -C "$HERE/cjselfhost_llvmshim.o" | grep -cE ' T (LLVMGlobalObjectAddStringAttribute|LLVMSelfhost)' \
  | sed 's/^/exported LLVMSelfhost* symbols: /' || true

# Macro runtime layout. The self-host cjc resolves the Cangjie runtime lib relative to its own
# binary (CompilerInvocation.GetRuntimeLibPath: <cjc>/../runtime/lib/<host>, a faithful 1:1 port of
# C++ which has no CANGJIE_HOME fallback). C++'s cjc is installed under CANGJIE_HOME/bin so the
# sibling ../runtime resolves; the build-dir cjc (target/release/bin) has no sibling runtime/, so
# link it to CANGJIE_HOME's runtime for in-process macro invocation. Deployment note: an installed
# cjc needs no symlink — this is a build-layout shim, not a compiler-code change.
REPO="$(cd "$HERE/.." && pwd)"
if [ -n "${CANGJIE_HOME:-}" ] && [ -d "$CANGJIE_HOME/runtime" ]; then
    mkdir -p "$REPO/target/release"
    ln -sfn "$CANGJIE_HOME/runtime" "$REPO/target/release/runtime"
    echo "linked runtime layout: $REPO/target/release/runtime -> $CANGJIE_HOME/runtime"
fi
