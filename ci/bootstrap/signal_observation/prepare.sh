#!/usr/bin/env bash
# Reuse the frozen stage0 build/assembly. Omit only its unobserved --version
# check from a private script copy: the single LLDB launch observes that entry.
set -euo pipefail
out="$RUNNER_TEMP/signal-observation"
mkdir -p "$out/preparation"
cp -R "$GITHUB_WORKSPACE/ci" "$out/preparation/ci"
python3 - "$out/preparation/ci/bootstrap/bootstrap.sh" "$out/preparation/ci/bootstrap/gha_run.sh" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); s = p.read_text()
line = '  assert_version cjcj-stage1 "$out" "$WORK/sdk-stage0-run" "$HRT"'
assert s.count(line) == 1
s = s.replace(line, '  echo "OBSERVATION: stage0 version launch reserved for LLDB"')
p.write_text(s)
p = Path(sys.argv[2]); s = p.read_text()
line = 'exec bash "$root/ci/bootstrap/bootstrap.sh"'
assert s.count(line) == 1
s = s.replace(line, 'exec bash "$(dirname "${BASH_SOURCE[0]}")/bootstrap.sh"')
p.write_text(s)
PY
# No runtime/LLVM/std producer is called: stage0 builds only the shim/compiler.
bash "$out/preparation/ci/bootstrap/gha_run.sh" stage0 > "$out/candidate-build.log" 2>&1
