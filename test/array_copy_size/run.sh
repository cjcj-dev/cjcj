#!/bin/bash
# Compile the real std.core implementation, then link the fixture against it.
# SDK inputs must be private copies. COPY_RUN_LD selects the coloured runtime.
set -uo pipefail
ulimit -c 0
src=$(cd "$(dirname "$0")" && pwd)
compiler=${1:?compiler ELF}
core=${2:?stdlib/libs/std/core source directory}
out=${3:?absolute output directory}
mkdir -p "$out/temps" "$out/lib" "$out/objects"
uptime > "$out/uptime-before"
sha256sum "$compiler" "$src/main.cj" "$core/array.cj" > "$out/inputs.sha256"
/usr/bin/time -f 'wall=%e' "$compiler" --no-prelude --output-type=staticlib "$core/"*.cj \
    --output "$out/std.core.a" -j "$(nproc)" -O2 --dump-ir --dump-to-screen \
    --save-temps="$out/temps" > "$out/core-compile.log" 2>&1
rc=$?; echo "$rc" > "$out/core-compile.rc"
[ "$rc" = 0 ] || exit "$rc"
# Retain std.core's unchanged native support, replace its Cangjie object.
cp "$CANGJIE_HOME/lib/linux_x86_64_cjnative/libcangjie-std-core.a" "$out/lib/"
(cd "$out/objects" && ar x "$out/std.core.a" && test "$(find . -name '*.o' | wc -l)" = 1 && mv ./*.o core.o && ar r "$out/lib/libcangjie-std-core.a" core.o)
rc=$?; echo "$rc" > "$out/archive.rc"
[ "$rc" = 0 ] || exit "$rc"
sha256sum "$out/std.core.a" "$out/lib/libcangjie-std-core.a" > "$out/core.sha256"
/usr/bin/time -f 'wall=%e' "$compiler" "$src/main.cj" -O0 --static-std -L "$out/lib" \
    -o "$out/fixture" > "$out/compile.log" 2>&1
rc=$?; echo "$rc" > "$out/compile.rc"
[ "$rc" = 0 ] || exit "$rc"
sha256sum "$out/fixture" > "$out/fixture.sha256"
objdump -d --disassemble=_CNat5ArrayIG_E5cloneHv "$out/fixture" > "$out/clone.disasm"
python3 "$src/check.py" "$out" > "$out/check.log" 2>&1
check_rc=$?; echo "$check_rc" > "$out/check.rc"
for mode in tuple control; do
 cjHeapSize=96G LD_LIBRARY_PATH="${COPY_RUN_LD:?coloured runtime path}" timeout 60 "$out/fixture" "$mode" > "$out/$mode-run.log" 2>&1
 echo "$?" > "$out/$mode-run.rc"
done
uptime > "$out/uptime-after"
cat "$out/check.log"
[ "$check_rc" = 0 ] && [ "$(cat "$out/tuple-run.rc")" = 0 ] && [ "$(cat "$out/control-run.rc")" = 0 ]
