#!/usr/bin/env bash
# CJC runs with the caller's host loader; the probe uses PRODUCT_LD_LIBRARY_PATH.
set -u
repo=$1
header=$2
out=$3
compiler=$4
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$out"
out=$(cd "$out" && pwd)
run_step() {
    local step=$1
    shift
    local start=$SECONDS
    "$@" > "$out/$step.log" 2>&1
    local rc=$?
    printf '%s\n' "$rc" > "$out/$step.rc"
    printf '%s wall=%s rc=%s\n' "$step" "$((SECONDS-start))" "$rc" >> "$out/steps.txt"
    return "$rc"
}
uptime > "$out/uptime-before.txt"
run_step generate python3 "$here/generate.py" --repo "$repo" --runtime-header "$header" --out "$out" || exit $?
run_step cpp-build c++ -std=c++17 "$out/layout.cpp" -o "$out/cpp-layout" || exit $?
run_step cpp-run "$out/cpp-layout" || exit $?
cp "$out/cpp-run.log" "$out/cpp-layout.txt"
run_step cj-build timeout 90 "$compiler" "$out/layout.cj" -o "$out/cj-layout" || exit $?
sha256sum "$compiler" "$out/cj-layout" "$out/cpp-layout" > "$out/elf.sha256"
run_step cj-run env LD_LIBRARY_PATH="$PRODUCT_LD_LIBRARY_PATH" timeout 30 "$out/cj-layout" || exit $?
cp "$out/cj-run.log" "$out/cj-layout.txt"
run_step comparison python3 "$here/compare.py" "$out"
rc=$?
uptime > "$out/uptime-after.txt"
exit "$rc"
