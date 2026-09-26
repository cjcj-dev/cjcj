#!/bin/bash
set -uo pipefail
ulimit -c 0
src=$(cd "$(dirname "$0")" && pwd)
out=${FAST_MATH_OUT:?}
compiler=${FAST_MATH_CJC:?}
sdk=${CANGJIE_HOME:?}
llvm_dis=${FAST_MATH_LLVM_DIS:-$sdk/third_party/llvm/bin/llvm-dis}
mkdir -p "$out/on" "$out/off"
uptime > "$out/uptime-before.txt"
sha256sum "$compiler" "$llvm_dis" > "$out/inputs.sha256"
export LD_LIBRARY_PATH="$sdk/runtime/lib/linux_x86_64_cjnative:$sdk/lib/linux_x86_64_cjnative:$sdk/third_party/llvm/lib:${LD_LIBRARY_PATH:-}"

compile_one() {
    local mode=$1 dest=$2
    shift 2
    mkdir -p "$dest"
    "$compiler" "$src/ops.cj" --output-type=staticlib -O0 --save-temps="$dest" "$@" -o "$dest/ops.a" > "$dest/compile.log" 2>&1
    local rc=$?
    printf '%s\n' "$rc" > "$dest/compile.rc"
    if [ "$rc" != 0 ]; then
        return "$rc"
    fi
    local bc ll dis_rc=0
    shopt -s nullglob
    for bc in "$dest"/*.bc; do
        ll="${bc%.bc}.ll"
        "$llvm_dis" "$bc" -o "$ll" > "$dest/llvm-dis.log" 2>&1
        dis_rc=$?
        printf 'dis %s rc=%s\n' "$bc" "$dis_rc" >> "$dest/llvm-dis.log"
        if [ "$dis_rc" != 0 ]; then
            return "$dis_rc"
        fi
    done
    shopt -u nullglob
    python3 "$src/check.py" "$dest" "$mode" > "$dest/check.log" 2>&1
    rc=$?
    printf '%s\n' "$rc" > "$dest/check.rc"
    return "$rc"
}

start=$SECONDS
compile_one on "$out/on" --fast-math &
on_pid=$!
compile_one off "$out/off" &
off_pid=$!
wait "$on_pid"; on_rc=$?
wait "$off_pid"; off_rc=$?
echo "wall=$((SECONDS - start)) parallel_arms=2" > "$out/wall.txt"
uptime > "$out/uptime-after.txt"
echo "on_rc=$on_rc off_rc=$off_rc"
cat "$out/on/check.log" 2>/dev/null || true
echo '--- off ---'
cat "$out/off/check.log" 2>/dev/null || true
[ "$on_rc" = 0 ] && [ "$off_rc" = 0 ]
