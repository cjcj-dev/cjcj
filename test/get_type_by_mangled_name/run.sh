#!/bin/bash
set -uo pipefail
ulimit -c 0
src=$(cd "$(dirname "$0")" && pwd)
compiler=${1:?compiler path}
out=${2:?absolute evidence directory}
mkdir -p "$out"
uptime > "$out/uptime-before"
sha256sum "$compiler" "$src/main.cj" "$src/check.py" > "$out/inputs.sha256"
/usr/bin/time -f 'wall=%e' "$compiler" "$src/main.cj" -O0 --dump-ir --dump-to-screen \
    -o "$out/fixture" > "$out/compile.log" 2>&1
compile_rc=$?
echo "$compile_rc" > "$out/compile.rc"
python3 "$src/check.py" --ir "$out/compile.log" > "$out/check.log" 2>&1
check_rc=$?
echo "$check_rc" > "$out/check.rc"
run_rc=125
if [ "$compile_rc" = 0 ] && [ -x "$out/fixture" ]; then
    sha256sum "$out/fixture" > "$out/fixture.sha256"
    LD_LIBRARY_PATH="${PAYLOAD_RUN_LD:?product runtime path}" timeout 60 "$out/fixture" > "$out/run.log" 2>&1
    run_rc=$?
    if [ "$run_rc" = 0 ]; then
        /usr/bin/grep -q '^GET_TYPE_BY_MANGLED_NAME_OK$' "$out/run.log" || run_rc=1
    fi
fi
echo "$run_rc" > "$out/run.rc"
uptime > "$out/uptime-after"
cat "$out/check.log"
echo "compile_rc=$compile_rc check_rc=$check_rc run_rc=$run_rc"
[ "$compile_rc" = 0 ] && [ "$check_rc" = 0 ] && [ "$run_rc" = 0 ]
