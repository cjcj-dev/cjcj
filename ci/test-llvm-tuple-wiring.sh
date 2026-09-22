#!/usr/bin/env bash
# Fault arms for the scripts themselves; no LLVM execution claim.
set -euo pipefail
export LC_ALL=C
root=$(cd "$(dirname "$0")/.." && pwd)
work=${1:?usage: test-llvm-tuple-wiring.sh EMPTY_WORK_DIRECTORY}
mkdir "$work"
cd "$root"
producer=ci/llvm-tuple-layout.sh
consumer=ci/release/prepare_bootstrap_inputs.mjs
cp "$producer" "$work/producer.saved"
cp "$consumer" "$work/consumer.saved"
restore() {
    cp "$work/producer.saved" "$producer"
    cp "$work/consumer.saved" "$consumer"
}
trap restore EXIT
sha256sum "$producer" "$consumer" > "$work/green.sha256"
bash ci/test-llvm-tuple-layout.sh "$work/producer-green" > "$work/producer-green.log" 2>&1
node --test --test-reporter=tap ci/release/prepare_bootstrap_inputs.test.mjs > "$work/consumer-green.log" 2>&1
python3 - <<'PY'
from pathlib import Path
p = Path('ci/llvm-tuple-layout.sh')
s = p.read_text()
line = '    cp -- "$depot/MANIFEST" "$depot/lib/STATIC_LLVM.txt" || return 1'
assert s.count(line) == 1
p.write_text(s.replace(line, '    # fault arm: omit static tuple payload'))
PY
diff -u "$work/producer.saved" "$producer" > "$work/producer-cut.diff" || test "$?" -eq 1
sha256sum "$producer" > "$work/producer-cut.sha256"
set +e
bash ci/test-llvm-tuple-layout.sh "$work/producer-cut" > "$work/producer-cut.log" 2>&1
producer_rc=$?
set -e
test "$producer_rc" -ne 0
grep -F 'lib/STATIC_LLVM.txt' "$work/producer-cut.log"
restore
python3 - <<'PY'
from pathlib import Path
p = Path('ci/release/prepare_bootstrap_inputs.mjs')
s = p.read_text()
line = '  process.env.CJCJ_BOOTSTRAP_TUPLE_ARTIFACT,\n'
assert s.count(line) == 1
p.write_text(s.replace(line, ''))
PY
diff -u "$work/consumer.saved" "$consumer" > "$work/consumer-cut.diff" || test "$?" -eq 1
sha256sum "$consumer" > "$work/consumer-cut.sha256"
set +e
node --test --test-reporter=tap ci/release/prepare_bootstrap_inputs.test.mjs > "$work/consumer-cut.log" 2>&1
consumer_rc=$?
set -e
test "$consumer_rc" -ne 0
grep -F 'ERR_ASSERTION' "$work/consumer-cut.log"
grep -Fx '# pass 2' "$work/consumer-cut.log"
grep -Fx '# fail 1' "$work/consumer-cut.log"
restore
python3 - <<'CUT'
from pathlib import Path
p = Path('ci/release/prepare_bootstrap_inputs.mjs')
s = p.read_text()
a = s.index("if (!/^[0-9a-f]{64}$/.test(process.env.LLVM_TUPLE_SUMS_SHA")
b = s.index("\n\nconst colourRt", a)
p.write_text(s[:a] + s[b:])
CUT
diff -u "$work/consumer.saved" "$consumer" > "$work/pin-cut.diff" || test "$?" -eq 1
sha256sum "$consumer" > "$work/pin-cut.sha256"
set +e
node --test --test-reporter=tap ci/release/prepare_bootstrap_inputs.test.mjs > "$work/pin-cut.log" 2>&1
pin_rc=$?
set -e
test "$pin_rc" -ne 0
grep -F 'ERR_ASSERTION' "$work/pin-cut.log"
grep -Fx '# pass 2' "$work/pin-cut.log"
grep -Fx '# fail 1' "$work/pin-cut.log"
restore
bash ci/test-llvm-tuple-layout.sh "$work/producer-restored" > "$work/producer-restored.log" 2>&1
node --test --test-reporter=tap ci/release/prepare_bootstrap_inputs.test.mjs > "$work/consumer-restored.log" 2>&1
sha256sum "$producer" "$consumer" > "$work/restored.sha256"
cmp "$work/green.sha256" "$work/restored.sha256"
printf 'WIRING producer green=0 cut=%s restored=0; consumer green=0 cut=%s restored=0\n' "$producer_rc" "$consumer_rc"
printf 'WIRING reviewed-pin green=0 cut=%s restored=0\n' "$pin_rc"
