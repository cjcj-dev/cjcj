#!/usr/bin/env bash
# Device-only fault arms: execute the actual bootstrap-input process each time.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=${1:?empty evidence directory}
mkdir "$work"
work=$(cd "$work" && pwd)
cd "$root"
consumer=ci/release/prepare_bootstrap_inputs.mjs
cp "$consumer" "$work/consumer.saved"
restore() { cp "$work/consumer.saved" "$consumer"; }
trap restore EXIT
run() { node --test --test-reporter=tap ci/release/prepare_bootstrap_inputs.test.mjs; }
sha256sum "$consumer" > "$work/green.sha256"
run > "$work/green.log" 2>&1
python3 - <<'PY'
from pathlib import Path
p = Path('ci/release/prepare_bootstrap_inputs.mjs')
s = p.read_text()
line = 'pinnedInput(process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT, ['
assert s.count(line) == 1
p.write_text(s.replace(line, 'pinnedInput(undefined, ['))
PY
diff -u "$work/consumer.saved" "$consumer" > "$work/selection-cut.diff" || test "$?" -eq 1
sha256sum "$consumer" > "$work/selection-cut.sha256"
set +e
run > "$work/selection-cut.log" 2>&1
selection_rc=$?
set -e
test "$selection_rc" -ne 0
grep -F 'not ok 5 - ast artifact wins' "$work/selection-cut.log"
grep -F 'not ok 7 - missing selected ast artifact' "$work/selection-cut.log"
grep -Fx '# pass 6' "$work/selection-cut.log"
grep -Fx '# fail 2' "$work/selection-cut.log"
restore
# Bypass just the AST caller's reviewed pin, leaving the tuple guard intact.
python3 - <<'PY'
from pathlib import Path
p = Path('ci/release/prepare_bootstrap_inputs.mjs')
s = p.read_text()
line = "], '', process.env.AST_SUPPORT_SHA256, 'ast-support archive SHA256');"
assert s.count(line) == 1
p.write_text(s.replace(line, "], '', sha256File(process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT || firstExisting([process.env.CJCJ_BOOTSTRAP_AST_SUPPORT, path.join(buildRoot, 'lib', 'libcangjie-ast-support.a')])), 'ast-support archive SHA256');"))
PY
diff -u "$work/consumer.saved" "$consumer" > "$work/digest-cut.diff" || test "$?" -eq 1
sha256sum "$consumer" > "$work/digest-cut.sha256"
set +e
run > "$work/digest-cut.log" 2>&1
digest_rc=$?
set -e
test "$digest_rc" -ne 0
grep -F 'not ok 6 - ast reviewed pin rejects changed bytes' "$work/digest-cut.log"
grep -Fx '# pass 7' "$work/digest-cut.log"
grep -Fx '# fail 1' "$work/digest-cut.log"
restore
run > "$work/restored.log" 2>&1
sha256sum "$consumer" > "$work/restored.sha256"
cmp "$work/green.sha256" "$work/restored.sha256"
printf 'AST-WIRING green=0 selection-cut=%s digest-cut=%s restored=0\n' "$selection_rc" "$digest_rc"
