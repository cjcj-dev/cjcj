#!/bin/bash
set -euo pipefail
ulimit -c 0
src=$(cd "$(dirname "$0")" && pwd)
out=${LITERAL_OUT:?}; sdk=${CANGJIE_HOME:?}; host=${LITERAL_HOST:?}; lib=${LITERAL_RUNTIME:?}
compiler=${LITERAL_CJC:-$sdk/bin/cjc}
mkdir -p "$out"
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
export LD_LIBRARY_PATH="$host/runtime/lib/linux_x86_64_cjnative:$host/third_party/llvm/lib:$host/tools/lib"
export PATH="$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:$PATH"
clang -shared -fPIC -O0 -g "$src/observe.c" -L"$lib" -lcangjie-runtime -lboundscheck -o "$out/libexception_observe.so"
for name in arithmetic oom; do
    "$compiler" "$src/$name.cj" -O0 --static-std --dump-ir -L "$out" -lexception_observe -L "$lib" -o "$out/$name" > "$out/$name-build.log" 2>&1
done
sha256sum "$out/arithmetic" "$out/oom" "$out/libexception_observe.so" > "$out/elf.sha256"
export LD_LIBRARY_PATH="$out:$lib:$sdk/runtime/lib/linux_x86_64_cjnative"
set +e
taskset -c "${LITERAL_CORES:?}" timeout 60s "$out/arithmetic" > "$out/arithmetic.log" 2>&1
arithmetic_rc=$?
taskset -c "$LITERAL_CORES" timeout 60s "$out/oom" > "$out/oom.log" 2>&1
oom_rc=$?
set -e
echo "$arithmetic_rc" > "$out/arithmetic.rc"
echo "$oom_rc" > "$out/oom.rc"
python3 - "$out" <<'PY'
from pathlib import Path
import sys
out=Path(sys.argv[1]); log=(out/'oom.log').read_text()
checks=[('arithmetic', (out/'arithmetic.rc').read_text().strip()=='0'),
        ('oom.exit', (out/'oom.rc').read_text().strip()=='1'),
        ('oom.heading','An exception has occurred:' in log),('oom.message','    Out of memory' in log)]
for name,ok in checks: print('ASSERT '+name+' '+('PASS' if ok else 'FAIL'))
raise SystemExit(any(not ok for _,ok in checks))
PY
