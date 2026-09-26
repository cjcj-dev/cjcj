#!/usr/bin/env bash
# Exercise host routing through the real GHA entry, before SDK inputs are read.
# This is a routing assertion, not a successful compiler/SDK bootstrap.
set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)
expected=${1:?expected native runtime tuple}
evidence=${2:?absolute evidence directory}
case "$evidence" in /*) ;; *) echo 'absolute evidence directory required' >&2; exit 2;; esac
mkdir -p "$evidence"
sha=$(git -C "$root" rev-parse HEAD)
digest=0000000000000000000000000000000000000000000000000000000000000000
inputs="$evidence/absent-inputs"
# Deliberately absent SDK inputs stop execution after host admission. No uname,
# SDK builder or product function is replaced by the test.
test ! -e "$inputs"
uname -s > "$evidence/host.txt"
uname -m >> "$evidence/host.txt"
python3 - "$root" > "$evidence/product.sha256" <<'PY'
import hashlib
from pathlib import Path
import sys
root = Path(sys.argv[1])
for name in ('ci/bootstrap/gha_run.sh', 'ci/bootstrap/bootstrap.sh'):
    print(hashlib.sha256((root / name).read_bytes()).hexdigest(), name)
PY
rc=0
env GITHUB_WORKSPACE="$root" CANGJIE_WORKSPACE="$inputs" \
  CJCJ_BOOTSTRAP_BASE="$inputs/base" \
  CJCJ_BOOTSTRAP_HOST_LLVM_SO="$inputs/host-llvm" \
  CJCJ_BOOTSTRAP_HOST_LLVM_SHA256="$digest" \
  CJCJ_BOOTSTRAP_COLOUR_LLVM_SO="$inputs/colour-llvm" \
  CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA256="$digest" \
  CJCJ_BOOTSTRAP_AST_SUPPORT="$inputs/ast" \
  CJCJ_BOOTSTRAP_AST_SUPPORT_SHA256="$digest" \
  CJCJ_BOOTSTRAP_COLOUR_TUPLE="$inputs/tuple" \
  CJCJ_BOOTSTRAP_COLOUR_LLVM_SHA="$sha" \
  CJCJ_BOOTSTRAP_COLOUR_RT="$inputs/colour-runtime" \
  CJCJ_BOOTSTRAP_HOST_RT="$inputs/host-runtime" \
  CJCJ_BOOTSTRAP_CPP_SRC="$inputs/cpp" \
  CJCJ_BOOTSTRAP_CJCJ_SHA="$sha" \
  bash "$root/ci/bootstrap/gha_run.sh" stage0 > "$evidence/entry.log" 2>&1 || rc=$?
printf '%s\n' "$rc" > "$evidence/entry.rc"
observed=$(sed -n 's/^HOST-TUPLE \([^ ]*\) .*/\1/p' "$evidence/entry.log")
printf 'ASSERT native-host-route expected=%s observed=%s entry_rc=%s\n' \
  "$expected" "${observed:-missing}" "$rc"
if [ "$observed" != "$expected" ]; then
  cat "$evidence/entry.log"
  echo 'FAIL native-host-route' >&2
  exit 1
fi
echo 'PASS native-host-route (host admission only; SDK bootstrap not exercised)'
