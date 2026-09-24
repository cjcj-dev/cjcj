#!/bin/bash
# Inspect a real frontend aggregate write after the product splitting pass.
set -uo pipefail
ulimit -c 0
src=$(cd "$(dirname "$0")" && pwd)
out=${STRENGTH_OUT:?}
compiler=${STRENGTH_CJC:?}
opt=${STRENGTH_OPT:?}
mkdir -p "$out/temps" "$out/split"
uptime > "$out/uptime-before.txt"
sha256sum "$compiler" "$opt" "$src/aggregate.cj" > "$out/inputs.sha256"
start=$SECONDS
"$compiler" "$src/aggregate.cj" -O0 --dump-ir --save-temps "$out/temps" \
    -o "$out/aggregate" > "$out/build.log" 2>&1
build_rc=$?
printf '%s\n' "$build_rc" > "$out/build.rc"
split_rc=0
count=0
for input in "$out/aggregate_IR/0_GenIncremental/"*.ll; do
    [ -f "$input" ] || continue
    count=$((count + 1))
    "$opt" -passes=cj-barrier-split,verify -S "$input" \
        -o "$out/split/$(basename "$input")" >> "$out/split.log" 2>&1 || split_rc=1
done
[ "$count" -gt 0 ] || split_rc=1
printf '%s\n' "$split_rc" > "$out/split.rc"
# Run each target assertion independently so missing input does not obscure it.
check_rc=0
for function in aggregateStringStore aggregateReferenceStore ordinaryReferenceStore; do
    python3 "$src/check_ir.py" "$out/split" --expect "$function=1" \
        --filter "strength.$function" > "$out/$function.log" 2>&1
    rc=$?
    printf '%s\n' "$rc" > "$out/$function.rc"
    [ "$rc" = 0 ] || check_rc=1
done
if [ "$build_rc" = 0 ]; then
    sha256sum "$out/aggregate" > "$out/elf.sha256"
fi
printf 'wall=%s modules=%s build_rc=%s split_rc=%s check_rc=%s\n' \
    "$((SECONDS-start))" "$count" "$build_rc" "$split_rc" "$check_rc" > "$out/result.txt"
uptime > "$out/uptime-after.txt"
cat "$out/result.txt" "$out/"*Store.log
[ "$build_rc" = 0 ] && [ "$split_rc" = 0 ] && [ "$check_rc" = 0 ]
