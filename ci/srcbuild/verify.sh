#!/usr/bin/env bash
# Fail-closed verification for an SDK containing both bin/cjc (the C++ oracle)
# and bin/cjcj (the self-host compiler).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${1:?usage: verify.sh <sdk-dir>}"
SELF="$SDK/bin/cjcj"
ORACLE="$SDK/bin/cjc"
JOBS="${CJCJ_VERIFY_JOBS:-$(nproc)}"
if [ "$JOBS" -gt 16 ]; then JOBS=16; fi

test -x "$SELF"
test -x "$ORACLE"

export CANGJIE_HOME="$SDK"
export PATH="$SDK/bin:$SDK/tools/bin:$PATH"
export LD_LIBRARY_PATH="$SDK/third_party/llvm/lib:$SDK/runtime/lib/linux_x86_64_cjnative:$SDK/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize="${cjHeapSize:-12GB}"

WORK="${RUNNER_TEMP:-/tmp}/cjcj-srcbuild-verify"
rm -rf "$WORK"
mkdir -p "$WORK"

echo "[1/4] difftest: cjcj vs source-built C++ cjc"
DIFFTEST_TC="$SDK" DIFFTEST_SELF="$SELF" DIFFTEST_REF="$ORACLE" \
    bash "$ROOT/scripts/difftest.sh" -j "$JOBS" | tee "$WORK/difftest.log"
grep -Eq 'TOTAL=[0-9]+[[:space:]]+PASS=[0-9]+[[:space:]]+MISMATCH=0[[:space:]]+FAIL=0' \
    "$WORK/difftest.log"

echo "[2/4] deployed SDK smoke"
bash "$ROOT/ci/smoke/run_smoke.sh" "$SELF" "$WORK/smoke"

echo "[3/4] compiler-package smoke (includes incremental_compilation)"
packages=(
    option conditional_compilation mangle frontend_tool incremental_compilation
    modules driver meta_transformation lex ast frontend cjc basic codegen macro
)
for pkg in "${packages[@]}"; do
    echo "  package: $pkg"
    timeout 900 "$SELF" \
        --package "$ROOT/packages/$pkg/src" \
        --module-name cjcj \
        --import-path "$ROOT/target/release" \
        --output-type=staticlib \
        -o "$WORK/$pkg.a"
done

echo "[4/4] bitcode parity gate"
python3 "$ROOT/scripts/bcgate.py" \
    --self "$SELF" \
    --base "$ORACLE" \
    --corpus "$ROOT/scripts/difftest_corpus" \
    -j "$JOBS" | tee "$WORK/bcgate.log"
grep -Eq 'byte-identical: [0-9]+ \(100\.0%\)[[:space:]]+\|[[:space:]]+differing: 0' \
    "$WORK/bcgate.log"
grep -Eq 'compile-errors: 0' "$WORK/bcgate.log"
if grep -q 'functions present on only one side' "$WORK/bcgate.log"; then
    echo "bcgate failed: functions are present on only one side" >&2
    exit 1
fi

echo "srcbuild verification: PASS"
