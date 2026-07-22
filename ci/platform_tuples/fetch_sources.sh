#!/usr/bin/env bash
# Fetch only the exact pinned commits needed for a tuple. In particular, LLVM is
# never cloned at a moving branch tip.
set -euo pipefail

root="${TUPLE_ROOT:?TUPLE_ROOT is required}"
mkdir -p "$root/logs"
exec > >(tee "$root/logs/source-fetch.log") 2>&1

fetch_exact() {
    local url="$1" sha="$2" dest="$3" sparse_path="${4:-}"
    if [ ! -d "$dest/.git" ]; then
        git init "$dest"
        git -C "$dest" remote add origin "$url"
    fi
    if [ -n "$sparse_path" ]; then
        git -C "$dest" sparse-checkout set "$sparse_path"
    fi
    git -C "$dest" fetch --depth=1 origin "$sha"
    git -C "$dest" checkout --detach FETCH_HEAD
    test "$(git -C "$dest" rev-parse HEAD)" = "$sha"
}

fetch_exact "${LLVM_URL:?}" "${LLVM_SHA:?}" "$root/llvm-project"
grep -q ERT_CTOR_ANNOTATIONS \
    "$root/llvm-project/llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h"
# Seven reflection operands plus ERT_MAX. The previous LLVM pin has only six.
test "$(sed -n '/enum EnumReflectionType/,/};/p' \
    "$root/llvm-project/llvm/include/llvm/Transforms/Scalar/ReflectionInfo.h" \
    | grep -c '^  ERT_')" -eq 8

fetch_exact "${CANGJIE_COMPILER_URL:?}" "${CANGJIE_COMPILER_SHA:?}" "$root/cangjie-compiler" schema
test -f "$root/cangjie-compiler/schema/ModuleFormat.fbs"

fetch_exact "${FLATBUFFERS_URL:?}" "${FLATBUFFERS_SHA:?}" "$root/flatbuffers"
test -f "$root/flatbuffers/CMakeLists.txt"
