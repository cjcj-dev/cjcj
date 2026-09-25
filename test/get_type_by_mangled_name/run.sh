#!/bin/bash
set -uo pipefail
ulimit -c 0
src=$(cd "$(dirname "$0")" && pwd)
compiler=${1:?compiler path}
out=${2:?absolute evidence directory}
mkdir -p "$out"
uptime > "$out/uptime-before"
sha256sum "$compiler" "$src/main.cj" "$src/check.py" > "$out/inputs.sha256"
/usr/bin/time -f 'wall=%e' "$compiler" "$src/main.cj" --experimental -O0 --dump-ir --dump-to-screen \
    --output-type=obj -o "$out/fixture.o" > "$out/compile.log" 2>&1
compile_rc=$?
echo "$compile_rc" > "$out/compile.rc"
python3 "$src/check.py" --ir "$out/compile.log" > "$out/check.log" 2>&1
check_rc=$?
echo "$check_rc" > "$out/check.rc"
if [ -f "$out/fixture.o" ]; then
    sha256sum "$out/fixture.o" > "$out/fixture.sha256"
fi
uptime > "$out/uptime-after"
cat "$out/check.log"
echo "compile_rc=$compile_rc check_rc=$check_rc"
[ "$compile_rc" = 0 ] && [ "$check_rc" = 0 ]
