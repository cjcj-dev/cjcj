#!/usr/bin/env bash
# Layout contract only: fixture bytes are not LLVM/compiler acceptance evidence.
set -euo pipefail
export LC_ALL=C
REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
source "$REPO_ROOT/ci/llvm-tuple-layout.sh"
source "$REPO_ROOT/ci/llvm_pin.env"
work=${1:?usage: test-llvm-tuple-layout.sh EMPTY_WORK_DIRECTORY}
mkdir "$work"
CJCJ_FIXED_LLVM_DIR="$work/fixed"
mkdir "$CJCJ_FIXED_LLVM_DIR"
for tool in llc opt; do
    printf 'fixture %s\n' "$tool" | gzip -n > "$CJCJ_FIXED_LLVM_DIR/$tool.gz"
done
printf 'fixture shim\n' > "$CJCJ_FIXED_LLVM_DIR/cjselfhost_llvmshim.o"
printf 'fixture manifest\n' > "$CJCJ_FIXED_LLVM_DIR/llvm-tools.manifest"
publish_fixed_tuple_to_depot "$work/depot"
tuple="$work/depot/$LLVM_SHA/$CANGJIE_COMPILER_SHA"
check() { (cd "$tuple" && sha256sum --strict -c SHA256SUMS); }
check > "$work/green.log" 2>&1
test "$(wc -l < "$tuple/SHA256SUMS")" -eq 8
cp "$tuple/lib/STATIC_LLVM.txt" "$work/static.saved"
rm "$tuple/lib/STATIC_LLVM.txt"
set +e
check > "$work/cut.log" 2>&1
cut_rc=$?
set -e
test "$cut_rc" -ne 0
test "$(grep -c ': OK$' "$work/cut.log")" -eq 7
test "$(grep -c '^./lib/STATIC_LLVM.txt: FAILED' "$work/cut.log")" -eq 1
cp "$work/static.saved" "$tuple/lib/STATIC_LLVM.txt"
check > "$work/restored.log" 2>&1
cmp "$work/green.log" "$work/restored.log"
printf 'layout target executed: green_rc=0 cut_rc=%s restored_rc=0; cut OK=7 FAILED=1\n' "$cut_rc"
