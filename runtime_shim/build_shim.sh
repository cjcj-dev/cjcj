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

[ -d "$LLVM_SRC_INC" ] || { echo "ERR: LLVM source headers not found: $LLVM_SRC_INC" >&2; exit 1; }
[ -d "$LLVM_GEN_INC" ] || { echo "ERR: LLVM generated headers not found: $LLVM_GEN_INC" >&2; exit 1; }

# -fno-rtti / -fno-exceptions to match the LLVM build ABI.
clang++ -std=c++17 -O2 -fPIC -fno-rtti -fno-exceptions \
  -c "$HERE/cjselfhost_llvmshim.cpp" -o "$HERE/cjselfhost_llvmshim.o" \
  -I"$LLVM_SRC_INC" -I"$LLVM_GEN_INC"

echo "built: $HERE/cjselfhost_llvmshim.o"
nm -C "$HERE/cjselfhost_llvmshim.o" | grep -E ' T ' | grep -i shim || true
