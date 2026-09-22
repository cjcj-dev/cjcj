#!/bin/bash
# Real frontend emission. Host runtime and private candidate LLVM must be supplied.
set -uo pipefail
ulimit -c 0
src=$(cd "$(dirname "$0")" && pwd)
out=${STRENGTH_OUT:?}
compiler=${STRENGTH_CJC:?}
weak=${STRENGTH_WEAK_SOURCE:?}
mkdir -p "$out/main-temps" "$out/ref-temps"
uptime > "$out/uptime-before.txt"
sha256sum "$compiler" "$weak" "$CANGJIE_HOME/third_party/llvm/bin/opt" "$CANGJIE_HOME/third_party/llvm/bin/llc" > "$out/inputs.sha256"
start=$SECONDS
"$compiler" "$src/main.cj" --output-type=staticlib -O0 --dump-ir --save-temps "$out/main-temps" -o "$out/libstrength.a" > "$out/main-build.log" 2>&1 &
main_pid=$!
"$compiler" "$weak" --output-type=staticlib -O0 --dump-ir --save-temps "$out/ref-temps" -o "$out/libstd.ref.a" > "$out/ref-build.log" 2>&1 &
ref_pid=$!
wait "$main_pid"; main_rc=$?
wait "$ref_pid"; ref_rc=$?
printf '%s\n' "$main_rc" > "$out/main-build.rc"
printf '%s\n' "$ref_rc" > "$out/ref-build.rc"
echo "wall=$((SECONDS-start)) parallel_arms=2" > "$out/wall.txt"
uptime > "$out/uptime-after.txt"
echo "main_rc=$main_rc ref_rc=$ref_rc"
# Input failures are recorded separately; do not suppress target assertions.
python3 "$src/check_ir.py" "$out/libstrength_IR/0_GenIncremental" \
 --expect 'ordinaryField=1' --expect 'arrayElement=1' \
 --expect 'enumPayload=1' --expect 'boxedPayload=1' > "$out/main-check.log" 2>&1
main_check=$?
python3 "$src/check_ir.py" "$out/libstd.ref_IR/0_GenIncremental" \
 --expect 'clear=2' --expect 'WeakRefBase.*init=1' > "$out/ref-check.log" 2>&1
ref_check=$?
printf '%s\n' "$main_check" > "$out/main-check.rc"
printf '%s\n' "$ref_check" > "$out/ref-check.rc"
echo "main_check=$main_check ref_check=$ref_check"
[ "$main_rc" = 0 ] && [ "$ref_rc" = 0 ] && [ "$main_check" = 0 ] && [ "$ref_check" = 0 ]
