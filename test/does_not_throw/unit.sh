#!/usr/bin/env bash
# Run in a disposable build copy with the same real shim used by packages/cjc.
set -euo pipefail
ulimit -c 0
root=$(realpath "${1:?pass an isolated cjcj build tree}")
out=$(realpath -m "${2:?pass an evidence directory}")
: "${CANGJIE_HOME:?set the private host SDK}"
mkdir -p "$out"
cd "$root"
cp packages/chir/cjpm.toml "$out/chir-cjpm.original"
trap 'cp "$out/chir-cjpm.original" "$root/packages/chir/cjpm.toml"' EXIT
python3 - <<'PY'
from pathlib import Path
p = Path('packages/chir/cjpm.toml')
s = p.read_text()
old = '  link-option = ""'
assert old in s
p.write_text(s.replace(old, '  link-option = "runtime_shim/cjselfhost_llvmshim.o ${CANGJIE_HOME}/third_party/llvm/lib/libLLVM-15.so -lstdc++"'))
PY
sha256sum runtime_shim/cjselfhost_llvmshim.o > "$out/shim.sha256"
set +e
/usr/bin/time -f 'wall=%e' cjpm test -j "$(nproc)" -m packages/chir --filter '*DoesNotThrow*' --show-all-output > "$out/test.log" 2>&1
rc=$?
set -e
echo "$rc" > "$out/test.rc"
if [ -f target/release/unittest_bin/chir@cjcj ]; then
  cp target/release/unittest_bin/chir@cjcj "$out/chir-test"
  sha256sum "$out/chir-test" > "$out/test.sha256"
fi
exit "$rc"
