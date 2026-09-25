#!/bin/bash
# Run against a privately installed compiler/std closure and a matching runtime pair.
set -euo pipefail
ulimit -c 0
src=$(cd "$(dirname "$0")" && pwd)
out=${LITERAL_OUT:?}
sdk=${CANGJIE_HOME:?}
host=${LITERAL_HOST:?}
lib=${LITERAL_RUNTIME:?}
compiler=${LITERAL_CJC:-$sdk/bin/cjc}
cores=${LITERAL_CORES:?}
mkdir -p "$out/imported" "$out/temps-import" "$out/temps-main"
start=$SECONDS
record_exit() {
  local rc=$?
  echo "$rc" > "$out/run.rc"
  echo "wall=$((SECONDS-start))" > "$out/wall.txt"
  uptime > "$out/uptime-after.txt"
}
trap record_exit EXIT
uptime > "$out/uptime-before.txt"
sha256sum "$compiler" "$sdk/third_party/llvm/bin/llc" "$lib/"{libcangjie-runtime.so,libboundscheck.so} > "$out/inputs.sha256"
export PATH="$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:$PATH"
export LD_LIBRARY_PATH="$host/runtime/lib/linux_x86_64_cjnative:$host/third_party/llvm/lib:$host/tools/lib"
clang -shared -fPIC -O0 -g "$src/observe.c" -L"$lib" -lcangjie-runtime -lboundscheck -o "$out/libliteral_observe.so"
"$compiler" -p "$src/imported" --output-type=staticlib -O0 --apc-split-num 2 --dump-ir --save-temps "$out/temps-import" -o "$out/imported/libliteral_import.a" > "$out/import-build.log" 2>&1
"$compiler" "$src/main.cj" -O0 --static-std --apc-split-num 4 --dump-ir --save-temps "$out/temps-main" --import-path "$out/imported" -L "$out/imported" -lliteral_import -L "$out" -lliteral_observe -L "$lib" -o "$out/literal_runner" > "$out/main-build.log" 2>&1
python3 "$src/check_ir.py" "$out/imported/libliteral_import_IR/0_GenIncremental" "$out/temps-import" > "$out/ir-import.log"
python3 "$src/check_ir.py" "$out/literal_runner_IR/0_GenIncremental" "$out/temps-main" > "$out/ir-main.log"
sha256sum "$out/literal_runner" "$out/libliteral_observe.so" > "$out/elf.sha256"
nm --defined-only "$out/literal_runner" > "$out/defined.txt"
readelf -SW "$out/literal_runner" > "$out/sections.txt"
export LD_LIBRARY_PATH="$out:$lib:$sdk/runtime/lib/linux_x86_64_cjnative"
LITERAL_MAPS="$out/process.maps" cjGCInterval=3600s taskset -c "$cores" timeout 60s "$out/literal_runner" > "$out/run.log" 2>&1
