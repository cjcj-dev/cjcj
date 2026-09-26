#!/usr/bin/env bash
set -eu
ulimit -c 0
compiler=$(realpath "${1:?compiler ELF}")
work=$(realpath -m "${2:?evidence directory}")
fixtures=$(cd "$(dirname "$0")/override_top_fixtures" && pwd)
mkdir -p "$work"
sha256sum "$compiler" "$fixtures/"*.cj > "$work/inputs.sha256"
uptime > "$work/load-before"
nproc > "$work/jobs"
taskset -pc $$ > "$work/cpus"
run_case() {
    local n=$1
    mkdir -p "$work/$n"
    set +e
    "$compiler" "$fixtures/$n.cj" --output-type=staticlib -O2 \
        --output-dir "$work/$n" -o "$n.a" --diagnostic-format=noColor \
        > "$work/$n/compiler.log" 2>&1
    echo "$?" > "$work/$n/compiler.rc"
}
run_case norelation &
run_case multisuper &
wait
uptime > "$work/load-after"
python3 - "$work" <<'PY'
import json
from pathlib import Path
import sys
root = Path(sys.argv[1])
checks = {}
for name in ('norelation', 'multisuper'):
    path = root / name / 'compiler.rc'
    checks[name] = path.exists() and path.read_text().strip() == '0'
(root / 'result.json').write_text(json.dumps({'checks': checks}, indent=2) + '\n')
for name, passed in checks.items():
    print(('PASS ' if passed else 'FAIL ') + name)
sys.exit(0 if all(checks.values()) else 1)
PY
