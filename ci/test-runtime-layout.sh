#!/usr/bin/env bash
# Exercise the real pinned generator and the pairing entry with isolated copies.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
work=${1:?work directory}
runtime=${2:?runtime repository}
llvm=${3:?LLVM repository}
# shellcheck disable=SC1091
source "$repo/ci/runtime_pin.env"
# shellcheck disable=SC1091
source "$repo/ci/llvm_pin.env"
mkdir -p "$work/runtime" "$work/llvm/llvm/include/llvm/CodeGen"
git -C "$runtime" archive "$RUNTIME_REF" runtime | tar -x -C "$work/runtime"
header=llvm/include/llvm/CodeGen/CangjieRuntimeLayout.h
git -C "$llvm" show "$LLVM_SHA:$header" > "$work/llvm/$header"
for side in runtime llvm; do
    git -C "$work/$side" init -q
    git -C "$work/$side" add .
    git -C "$work/$side" -c user.name=Zxilly -c user.email=zxilly@outlook.com commit -qm 'test: pinned layout snapshot'
done
check() {
    bash "$repo/ci/check-llvm-runtime-abi.sh" \
        --runtime-repo "$work/runtime" --runtime-ref HEAD \
        --llvm-repo "$work/llvm" --llvm-ref HEAD
}
check > "$work/candidate.log" 2>&1
echo 'ASSERT layout candidate rc=0'
cp "$work/llvm/$header" "$work/original.h"
sha256sum "$work/llvm/$header" > "$work/candidate.sha256"
# Consumer fault: a valid header with one wrong offset, not a missing input.
python3 - "$work/llvm/$header" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
s, n = re.subn(r'(ObjectStateWordOffset = )(\d+)', lambda m: m[1] + str(int(m[2]) + 8), p.read_text())
assert n == 1
p.write_text(s)
PY
git -C "$work/llvm" add .
git -C "$work/llvm" -c user.name=Zxilly -c user.email=zxilly@outlook.com commit -qm 'test: wrong consumer offset'
git -C "$work/llvm" diff HEAD~ HEAD > "$work/consumer-cut.diff"
sha256sum "$work/llvm/$header" > "$work/consumer-cut.sha256"
rc=0
check > "$work/consumer-cut.log" 2>&1 || rc=$?
test "$rc" -eq 1
grep -F 'differs from runtime assertions' "$work/consumer-cut.log"
echo 'ASSERT layout consumer mismatch rc=1'
cp "$work/original.h" "$work/llvm/$header"
git -C "$work/llvm" add .
git -C "$work/llvm" -c user.name=Zxilly -c user.email=zxilly@outlook.com commit -qm 'test: restore consumer offset'
check > "$work/restored.log" 2>&1
sha256sum "$work/llvm/$header" > "$work/restored.sha256"
cmp "$work/candidate.sha256" "$work/restored.sha256"
echo 'ASSERT layout restored rc=0'
# Producer fault: change the runtime assertion value consumed by its generator.
python3 - "$work/runtime/runtime/src/Common/BaseObject.h" <<'PY'
from pathlib import Path
import re
import sys
p = Path(sys.argv[1])
s, n = re.subn(r'(sizeof\(BaseObject\) == )(\d+)(, "compiler layout ObjectHeaderSize")',
               lambda m: m[1] + str(int(m[2]) + 8) + m[3], p.read_text())
assert n == 1
p.write_text(s)
PY
git -C "$work/runtime" add .
git -C "$work/runtime" -c user.name=Zxilly -c user.email=zxilly@outlook.com commit -qm 'test: wrong producer layout'
git -C "$work/runtime" diff HEAD~ HEAD > "$work/producer-cut.diff"
rc=0
check > "$work/producer-cut.log" 2>&1 || rc=$?
test "$rc" -eq 1
grep -F 'differs from runtime assertions' "$work/producer-cut.log"
echo 'ASSERT layout producer mismatch rc=1'
# Source/header synchronization only: no runtime or generated-code behavior claim.
