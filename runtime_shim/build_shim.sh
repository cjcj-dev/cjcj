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

[ -d "$LLVM_SRC_INC" ] || { echo "ERR: LLVM source headers not found: $LLVM_SRC_INC" >&2; exit 1; }
[ -d "$LLVM_GEN_INC" ] || { echo "ERR: LLVM generated headers not found: $LLVM_GEN_INC" >&2; exit 1; }
[ -d "$FLATBUFFERS_INC" ] || { echo "ERR: flatbuffers headers not found: $FLATBUFFERS_INC" >&2; exit 1; }
[ -d "$SCHEMA_GEN_INC/flatbuffers" ] || { echo "ERR: schema headers not found: $SCHEMA_GEN_INC/flatbuffers" >&2; exit 1; }

# -fno-rtti / -fno-exceptions to match the LLVM build ABI.
clang++ -std=c++17 -O2 -fPIC -fno-rtti -fno-exceptions \
  -c "$HERE/cjselfhost_llvmshim.cpp" -o "$HERE/cjselfhost_llvmshim.o" \
  -I"$LLVM_SRC_INC" -I"$LLVM_GEN_INC" -I"$FLATBUFFERS_INC" -I"$SCHEMA_GEN_INC"

echo "built: $HERE/cjselfhost_llvmshim.o"
nm -C "$HERE/cjselfhost_llvmshim.o" | grep -E ' T (LLVMGlobalObjectAddStringAttribute|LLVMSelfhost)' || true

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
