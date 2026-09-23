#!/usr/bin/env bash
# Use the upstream std-support branch; never patch the compiler's CMake files.
set -euo pipefail
src=${1:?compiler source}
build=${2:?build directory}
out=${3:?artifact directory}
mkdir -p "$out"
start=$SECONDS
cmake -S "$src" -B "$build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCANGJIE_BUILD_CJC=OFF -DCANGJIE_BUILD_TESTS=OFF \
  -DCANGJIE_BUILD_STD_SUPPORT=ON -DCANGJIE_SKIP_BUILD_CLANG_RT=ON \
  2>&1 | tee "$out/configure.log"
# The dependency listing is evidence of the actual build surface, not a second
# hand-maintained list of upstream objects.
ninja -C "$build" -t commands cangjie-ast-support > "$out/target-commands.txt"
jobs=$(getconf _NPROCESSORS_ONLN)
cmake --build "$build" --target cangjie-ast-support -j "$jobs" \
  2>&1 | tee "$out/build.log"
cp "$build/lib/libcangjie-ast-support.a" "$out/"
(cd "$out" && shasum -a 256 libcangjie-ast-support.a > SHA256SUMS)
nm --defined-only "$out/libcangjie-ast-support.a" > "$out/nm-defined.txt"
printf 'target=cangjie-ast-support jobs=%s wall=%ss\n' "$jobs" "$((SECONDS-start))" | tee "$out/build-summary.txt"
