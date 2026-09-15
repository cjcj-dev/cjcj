#!/bin/bash
set -euo pipefail
ulimit -c 0
src=$(cd "$(dirname "$0")" && pwd)
out=${LITERAL_OUT:?}; sdk=${CANGJIE_HOME:?}; host=${LITERAL_HOST:?}; lib=${LITERAL_RUNTIME:?}
headers=${LITERAL_RUNTIME_HEADERS:?}; compiler=${LITERAL_CJC:-$sdk/bin/cjc}
mkdir -p "$out/probe" "$out/control" "$out/temps-probe" "$out/temps-control"
start=$SECONDS
receipt=run.rc
trap 'rc=$?; echo "$rc" > "$out/$receipt"; echo "wall=$((SECONDS-start))" > "$out/wall.txt"; uptime > "$out/uptime-after.txt"' EXIT
uptime > "$out/uptime-before.txt"
sha256sum "$compiler" "$sdk/third_party/llvm/bin/llc" "$lib/"{libcangjie-runtime.so,libboundscheck.so} > "$out/inputs.sha256"
export PATH="$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:$PATH"
export LD_LIBRARY_PATH="$host/runtime/lib/linux_x86_64_cjnative:$host/third_party/llvm/lib:$host/tools/lib"
clang++ -std=c++17 -shared -fPIC -O0 -g -pthread -I"$headers" "$src/observe.cpp" -L"$lib" -lcangjie-runtime -lboundscheck -ldl -o "$out/liblibrary_observe.so"
"$compiler" -p "$src/probe" --output-type=staticlib -O0 --apc-split-num 3 --dump-ir -o "$out/probe/libliteral_probe.a" > "$out/probe-scan.log" 2>&1
python3 "$src/identities.py" "$out/probe/libliteral_probe_IR/0_GenIncremental" "$out/identities.cpp"
clang++ -std=c++17 -fPIC -c "$out/identities.cpp" -o "$out/identities.o"
"$compiler" -p "$src/probe" --output-type=dylib -O0 --apc-split-num 3 --dump-ir --save-temps "$out/temps-probe" --link-options "$out/identities.o" -L "$out" -llibrary_observe -L "$lib" -o "$out/probe/libliteral_probe.so" > "$out/probe-build.log" 2>&1
"$compiler" -p "$src/control" --output-type=dylib -O0 --apc-split-num 2 --dump-ir --save-temps "$out/temps-control" -L "$out" -llibrary_observe -L "$lib" -o "$out/control/libliteral_control.so" > "$out/control-build.log" 2>&1
clang++ -std=c++17 -O0 -g -I"$headers" "$src/driver.cpp" -L"$out" -llibrary_observe -L"$lib" -lcangjie-runtime -lboundscheck -o "$out/library_runner"
sha256sum "$out/library_runner" "$out/liblibrary_observe.so" "$out/probe/libliteral_probe.so" "$out/control/libliteral_control.so" > "$out/elf.sha256"
nm --defined-only "$out/probe/libliteral_probe.so" > "$out/probe-defined.txt"
if [[ "${LITERAL_BUILD_ONLY:-0}" == 1 ]]; then
    receipt=build.rc
    echo 'NOT_RUN(build-only)' > "$out/run.rc"
    echo 'BUILD_ONLY_COMPLETE (no runtime assertions executed)'
    exit 0
fi
export LD_LIBRARY_PATH="$out:$out/probe:$out/control:$lib:$sdk/runtime/lib/linux_x86_64_cjnative"
LITERAL_MAPS="$out/process.maps" cjProcessorNum=1 cjGCInterval=3600s taskset -c "${LITERAL_CORES:?}" timeout 60s "$out/library_runner" "$out/probe/libliteral_probe.so" "$out/control/libliteral_control.so" "${LITERAL_CONCURRENT:-0}" > "$out/run.log" 2>&1
