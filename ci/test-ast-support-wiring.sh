#!/usr/bin/env bash
# Device-only fault arms: execute the actual bootstrap-input process each time.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=${1:?empty evidence directory}
mkdir "$work"
work=$(cd "$work" && pwd)
cd "$root"
consumer=ci/release/prepare_bootstrap_inputs.mjs
if test -n "$(git status --porcelain -- "$consumer")"; then
  echo 'consumer must be clean' >&2
  exit 1
fi
cp "$consumer" "$work/consumer.saved"
restore() {
  cp "$work/consumer.saved" "$consumer"
  cmp "$work/consumer.saved" "$consumer"
}
finish() {
  rc=$?
  trap - EXIT
  restore || rc=1
  sha256sum "$consumer" > "$work/exit.sha256"
  git status --porcelain -- "$consumer" > "$work/exit.status"
  test ! -s "$work/exit.status" || rc=1
  exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
run() {
  local arm=$1 rc=0 start=$SECONDS
  timeout -k 5 180 node --test --test-reporter=tap ci/release/prepare_bootstrap_inputs.test.mjs > "$work/$arm.log" 2>&1 || rc=$?
  echo "$rc" > "$work/$arm.rc"
  echo "wall=$((SECONDS-start))" > "$work/$arm.wall"
}
check() {
  python3 - "$work" "$1" <<'TAP'
import json, re, sys
from pathlib import Path
work, arm = Path(sys.argv[1]), sys.argv[2]
text = (work / f'{arm}.log').read_text()
rc = int((work / f'{arm}.rc').read_text())
records = list(re.finditer(r'^(ok|not ok) ([0-9]+) - (.+)$', text, re.M))
plan = re.findall(r'^1\.\.([0-9]+)$', text, re.M)
assert records and len(plan) == 1 and int(plan[0]) == len(records), 'incomplete TAP plan'
names = [m[3] for m in records]
assert len(set(names)) == len(names), 'duplicate TAP names'
assert [int(m[2]) for m in records] == list(range(1, len(records)+1)), 'TAP numbering'
assert not re.search(r'^.*# (?:SKIP|TODO)\b', text, re.M), 'skipped/TODO record'
summary = {}
for key in ('tests', 'pass', 'fail', 'cancelled', 'skipped', 'todo'):
    values = re.findall(rf'^# {key} ([0-9]+)$', text, re.M)
    assert len(values) == 1, f'missing {key} terminator'
    summary[key] = int(values[0])
failed = [m[3] for m in records if m[1] == 'not ok']
assert summary['tests'] == len(records) and summary['fail'] == len(failed)
assert summary['pass'] == len(records)-len(failed)
assert all(summary[k] == 0 for k in ('cancelled', 'skipped', 'todo'))
result = {'rc': rc, 'names': names, 'failed': failed, 'summary': summary}
(work / f'{arm}.json').write_text(json.dumps(result, indent=2)+'\n')
expected = {
 'green': {}, 'restored': {},
 'selection-cut': {'ast artifact wins over an available fallback archive': 93,
                   'missing selected ast artifact cannot fall back': 108},
 'digest-cut': {'ast reviewed pin rejects changed bytes while tuple stays valid': 100},
}[arm]
assert set(failed) == set(expected), f'{arm}: unexpected failure set {failed}'
assert (rc == 0) == (not expected), f'{arm}: unexpected runner rc {rc}'
if arm == 'green':
    # Confirm the dynamic full-package controls in the actual normal TAP.
    required = ['explicit bare ast archive is rejected before bootstrap export']
    required += [f'explicit AST input missing {name} is rejected before export' for name in
      ('include/cangjie', 'include/flatbuffers/StdAstFormat_generated.h', 'schema/StdAstFormat.fbs',
       'third_party/flatbuffers/bin/flatc', 'third_party/flatbuffers/include',
       'third_party/flatbuffers/cangjie', 'third_party/flatbuffers/modules')]
    required += [f'bare {where} archive selects complete downloaded AST inputs consumed by installer'
                 for where in ('build', 'SDK')]
    assert set(required) <= set(names), 'missing full-package controls'
else:
    green = json.loads((work / 'green.json').read_text())
    assert names == green['names'], 'test collection changed'
for i, m in enumerate(records):
    if m[3] in expected:
        diagnostic = text[m.end():records[i+1].start() if i+1 < len(records) else len(text)]
        assert 'ERR_ASSERTION' in diagnostic, 'not an assertion failure'
        assert re.search(rf'prepare_bootstrap_inputs\.test\.mjs:{expected[m[3]]}:[0-9]+', diagnostic), 'target assertion not reached'
if arm in ('green', 'restored'):
    markers = sorted(re.findall(r'^# ASSERT .+$', text, re.M))
    assert markers, 'missing assertion markers'
    if arm == 'green':
        (work / 'green-markers.json').write_text(json.dumps(markers, indent=2)+'\n')
    else:
        assert markers == json.loads((work / 'green-markers.json').read_text()), 'restored markers changed'
print(f'{arm}: rc={rc} tests={len(names)} failures={failed}')
TAP
}
sha256sum "$consumer" ci/release/prepare_bootstrap_inputs.test.mjs ci/release/prepare_bootstrap_fixture.mjs > "$work/inputs.sha256"
sha256sum "$consumer" > "$work/green.sha256"
run green
check green
python3 - <<'PY'
from pathlib import Path
p = Path('ci/release/prepare_bootstrap_inputs.mjs')
s = p.read_text()
line = 'pinnedInput(process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT || process.env.CJCJ_BOOTSTRAP_AST_SUPPORT,'
assert s.count(line) == 1, 'ANCHOR-MISMATCH selection'
p.write_text(s.replace(line, 'pinnedInput(process.env.CJCJ_BOOTSTRAP_AST_SUPPORT,'))
PY
diff -u "$work/consumer.saved" "$consumer" > "$work/selection-cut.diff" || test "$?" -eq 1
sha256sum "$consumer" > "$work/selection-cut.sha256"
run selection-cut
check selection-cut
restore
sha256sum "$consumer" > "$work/selection-restored.sha256"
# Bypass just the AST caller's reviewed pin, retaining tuple and full-package guards.
python3 - <<'PY'
from pathlib import Path
p = Path('ci/release/prepare_bootstrap_inputs.mjs')
s = p.read_text()
line = "astFallbacks, '', process.env.AST_SUPPORT_SHA256, 'ast-support archive SHA256');"
assert s.count(line) == 1, 'ANCHOR-MISMATCH digest'
p.write_text(s.replace(line, "astFallbacks, '', sha256File(process.env.CJCJ_BOOTSTRAP_AST_ARTIFACT || process.env.CJCJ_BOOTSTRAP_AST_SUPPORT || firstExisting(astFallbacks)), 'ast-support archive SHA256');"))
PY
diff -u "$work/consumer.saved" "$consumer" > "$work/digest-cut.diff" || test "$?" -eq 1
sha256sum "$consumer" > "$work/digest-cut.sha256"
run digest-cut
check digest-cut
restore
run restored
check restored
sha256sum "$consumer" > "$work/restored.sha256"
cmp "$work/green.sha256" "$work/restored.sha256"
printf 'AST-WIRING green=0 selection-cut=%s digest-cut=%s restored=0\n' "$(cat "$work/selection-cut.rc")" "$(cat "$work/digest-cut.rc")"
