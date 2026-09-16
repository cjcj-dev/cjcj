#!/bin/bash
# Execute already-built real DLLs with an explicitly selected runtime pair.
set -euo pipefail
ulimit -c 0
out=${LITERAL_OUT:?}
artifacts=${LITERAL_ARTIFACTS:?}
lib=${LITERAL_RUNTIME:?}
sdk=${CANGJIE_HOME:?}
mkdir -p "$out"
start=$SECONDS
trap 'rc=$?; echo "$rc" > "$out/run.rc"; echo "wall=$((SECONDS-start))" > "$out/wall.txt"; uptime > "$out/uptime-after.txt"' EXIT
uptime > "$out/uptime-before.txt"
cp "$artifacts/inputs.sha256" "$out/build-inputs.sha256"
sha256sum "$artifacts/library_runner" "$artifacts/liblibrary_observe.so" \
    "$artifacts/probe/libliteral_probe.so" "$artifacts/control/libliteral_control.so" \
    "$lib/libcangjie-runtime.so" "$lib/libboundscheck.so" > "$out/run-inputs.sha256"
export LD_LIBRARY_PATH="$artifacts:$artifacts/probe:$artifacts/control:$lib:$sdk/runtime/lib/linux_x86_64_cjnative"
LITERAL_MAPS="$out/process.maps" cjProcessorNum=1 cjGCInterval=3600s \
    taskset -c "${LITERAL_CORES:?}" timeout 60s "$artifacts/library_runner" \
    "$artifacts/probe/libliteral_probe.so" "$artifacts/control/libliteral_control.so" \
    "${LITERAL_CONCURRENT:-0}" > "$out/run.log" 2>&1
