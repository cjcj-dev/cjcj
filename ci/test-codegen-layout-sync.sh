#!/usr/bin/env bash
# Exercise the actual ABI entry with a stale generated frontend source.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=${1:?evidence directory}
runtime=${2:?runtime repository}
llvm=${3:?LLVM repository}
source "$repo/ci/runtime_pin.env"
source "$repo/ci/llvm_pin.env"
mkdir -p "$work/product/ci" "$work/product/packages/codegen/src"
for file in check-llvm-runtime-abi.sh generate-codegen-runtime-layout.py runtime_pin.env llvm_pin.env; do
    cp "$repo/ci/$file" "$work/product/ci/$file"
done
output="$work/product/packages/codegen/src/RuntimeLayout.cj"
cp "$repo/packages/codegen/src/RuntimeLayout.cj" "$output"
cp "$output" "$work/original.cj"
check() {
    bash "$work/product/ci/check-llvm-runtime-abi.sh" \
        --runtime-repo "$runtime" --runtime-ref "$RUNTIME_REF" \
        --llvm-repo "$llvm" --llvm-ref "$LLVM_SHA"
}
check > "$work/candidate.log" 2>&1
sha256sum "$output" > "$work/candidate.sha256"
python3 - "$output" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'instanceSizeIndex: Int64 = 4'
assert s.count(old) == 1
p.write_text(s.replace(old, 'instanceSizeIndex: Int64 = 6'))
PY
# The copy remains valid Cangjie; only the active field index has changed.
diff -u "$work/original.cj" "$output" > "$work/cut.diff" || test "$?" = 1
sha256sum "$output" > "$work/cut.sha256"
rc=0
check > "$work/cut.log" 2>&1 || rc=$?
printf 'ASSERT generated_source_stale actual_rc=%s expected_rc=1\n' "$rc"
test "$rc" = 1
grep -F 'CODEGEN_LAYOUT=STALE generated source differs:' "$work/cut.log"
cp "$work/original.cj" "$output"
check > "$work/restored.log" 2>&1
sha256sum "$output" > "$work/restored.sha256"
cmp "$work/candidate.sha256" "$work/restored.sha256"
printf 'ASSERT generated_source_sync candidate_rc=0 cut_rc=1 restored_rc=0\n'
