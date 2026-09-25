#!/usr/bin/env bash
set -eu
ulimit -c 0
compiler=$(realpath "${1:?compiler ELF}")
work=$(realpath -m "${2:?evidence directory}")
fixtures=$(cd "$(dirname "$0")/override_extend_fixtures" && pwd)
mkdir -p "$work"
sha256sum "$compiler" "$fixtures/"*.cj > "$work/inputs.sha256"
uptime > "$work/load-before"
taskset -pc $$ > "$work/cpus"
run_case() {
    local n=$1
    mkdir -p "$work/$n/import" "$work/$n/main"
    set +e
    "$compiler" "$fixtures/dep$n.cj" --output-type=staticlib -O2 \
        --output-dir "$work/$n/import" -o "dep$n.a" --diagnostic-format=noColor \
        > "$work/$n/dependency.log" 2>&1
    local dep_rc=$?
    echo "$dep_rc" > "$work/$n/dependency.rc"
    if [ "$dep_rc" = 0 ]; then
        (cd "$work/$n/main" && "$compiler" "$fixtures/main$n.cj" -O2 \
            --import-path "$work/$n/import" -L "$work/$n/import" -l"dep$n" \
            --emit-chir=raw --dump-chir --diagnostic-format=noColor -o "$work/$n/main/result") \
            > "$work/$n/compiler.log" 2>&1
        echo "$?" > "$work/$n/compiler.rc"
    fi
}
run_case 02 &
run_case 03 &
wait
mkdir -p "$work/control"
set +e
(cd "$work/control" && "$compiler" "$fixtures/control.cj" --emit-chir=raw --dump-chir -O2 -o result) \
    > "$work/control/compiler.log" 2>&1
echo "$?" > "$work/control/compiler.rc"
uptime > "$work/load-after"
python3 - "$work" <<'PY'
import hashlib
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
checks = {}
for name in ('02', '03'):
    for step in ('dependency', 'compiler'):
        path = root / name / (step + '.rc')
        checks[name + '/' + step] = path.exists() and path.read_text().strip() == '0'
checks['control/compiler'] = (root / 'control/compiler.rc').read_text().strip() == '0'
for case in ('02/main', '03/main', 'control'):
    checks[case + '/chir'] = (root / case / 'result_Emit_Debug.chirtxt').is_file()
outputs = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
           for p in root.rglob('*') if p.is_file() and p.name in ('result', 'result_Emit_Debug.chirtxt')}
(root / 'result.json').write_text(json.dumps({'checks': checks, 'outputs': outputs}, indent=2) + '\n')
for name, passed in checks.items():
    print(('PASS ' if passed else 'FAIL ') + name)
sys.exit(0 if all(checks.values()) else 1)
PY
