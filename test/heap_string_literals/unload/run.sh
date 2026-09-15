#!/bin/bash
set -euo pipefail
ulimit -c 0
src=$(cd "$(dirname "$0")" && pwd)
out=${LITERAL_OUT:?}; sdk=${CANGJIE_HOME:?}; host=${LITERAL_HOST:?}; lib=${LITERAL_RUNTIME:?}
compiler=${LITERAL_CJC:-$sdk/bin/cjc}; headers=${LITERAL_RUNTIME_HEADERS:?}
mkdir -p "$out/holder" "$out/producer"
start=$SECONDS
trap 'rc=$?; echo "$rc" > "$out/run.rc"; echo "wall=$((SECONDS-start))" > "$out/wall.txt"; uptime > "$out/uptime-after.txt"' EXIT
uptime > "$out/uptime-before.txt"
sha256sum "$compiler" "$sdk/third_party/llvm/bin/llc" "$lib/"{libcangjie-runtime.so,libboundscheck.so} > "$out/inputs.sha256"
export LD_LIBRARY_PATH="$host/runtime/lib/linux_x86_64_cjnative:$host/third_party/llvm/lib:$host/tools/lib"
export PATH="$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:$PATH"
"$compiler" -p "$src/holder" --output-type=dylib -O0 --apc-split-num 2 --dump-ir -L "$lib" -o "$out/holder/libliteral_retainer.so" > "$out/holder-build.log" 2>&1
"$compiler" -p "$src/producer" --output-type=dylib -O0 --apc-split-num 3 --dump-ir --import-path "$out/holder" -L "$out/holder" -lliteral_retainer -L "$lib" -o "$out/producer/libliteral_unload_source.so" > "$out/producer-build.log" 2>&1
clang++ -std=c++17 -O0 -g -rdynamic -I"$headers" "$src/driver.cpp" -L"$lib" -lcangjie-runtime -lboundscheck -o "$out/unload_runner"
sha256sum "$out/unload_runner" "$out/holder/libliteral_retainer.so" "$out/producer/libliteral_unload_source.so" > "$out/elf.sha256"
export LD_LIBRARY_PATH="$out/producer:$out/holder:$lib:$sdk/runtime/lib/linux_x86_64_cjnative"
taskset -c "${LITERAL_CORES:?}" timeout 60s "$out/unload_runner" "$out/holder/libliteral_retainer.so" "$out/producer/libliteral_unload_source.so" "$out" > "$out/run.log" 2>&1
