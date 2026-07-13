#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/scripts/w4annot_fixtures"
CJC="${1:-$ROOT/target/release/bin/cjcj::cjc}"
CANGJIE_HOME="${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}"
export CANGJIE_HOME
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize="${cjHeapSize:-12GB}"

PASS=0
FAIL=0
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass() {
    echo "PASS $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "FAIL $1"
    FAIL=$((FAIL + 1))
}

expect_failure_exact() {
    local name="$1"
    shift
    local expected=("$@")
    local output="$WORK/$name.out"
    if (cd "$WORK" && "$CJC" "$FIXTURES/$name.cj" --diagnostic-format=noColor \
        -o "$WORK/$name") >"$output" 2>&1; then
        fail "$name accepted"
        return
    fi
    local actual=()
    mapfile -t actual < <(grep -E '^(error|note):|^  # note:' "$output" || true)
    if [ "${#actual[@]}" -ne "${#expected[@]}" ]; then
        fail "$name diagnostic count expected=${#expected[@]} actual=${#actual[@]}"
        sed -n '1,80p' "$output"
        return
    fi
    local index=0
    while [ "$index" -lt "${#expected[@]}" ]; do
        if [ "${actual[$index]}" != "${expected[$index]}" ]; then
            fail "$name diagnostic[$index] mismatch"
            echo "EXPECTED: ${expected[$index]}"
            echo "ACTUAL:   ${actual[$index]}"
            return
        fi
        index=$((index + 1))
    done
    local expected_location=""
    if [ "$name" = "noheap_array_bad" ]; then
        expected_location="noheap_array_bad.cj:3:"
    elif [ "$name" = "noheap_closure_bad" ]; then
        expected_location="noheap_closure_bad.cj:5:"
    fi
    if [ -n "$expected_location" ] && ! grep -F "$expected_location" "$output" >/dev/null; then
        fail "$name missing allocation-site location $expected_location"
        sed -n '1,40p' "$output"
        return
    fi
    pass "$name rejected with exact diagnostics"
}

if (cd "$WORK" && "$CJC" "$FIXTURES/legal.cj" -o "$WORK/legal") >"$WORK/legal.out" 2>&1 &&
    [ "$("$WORK/legal")" = "43" ]; then
    pass "legal annotations compile and run"
else
    fail "legal annotations"
    sed -n '1,20p' "$WORK/legal.out"
fi

expect_failure_exact noheap_bad \
    "error: '@NoHeapAlloc' not applicable to static call closure emitted heap allocation 'llvm.cj.malloc.object'" \
    "note: @NoHeapAlloc root is 'allocateObject'" \
    "note: static call path: allocateObject"
expect_failure_exact noheap_array_bad \
    "error: '@NoHeapAlloc' not applicable to static call closure emitted heap allocation 'llvm.cj.malloc.array'" \
    "note: @NoHeapAlloc root is 'allocateArray'" \
    "note: static call path: allocateArray"
expect_failure_exact noheap_box_bad \
    "error: '@NoHeapAlloc' not applicable to static call closure emitted heap allocation 'llvm.cj.malloc.object'" \
    "note: @NoHeapAlloc root is 'noHeapBox'" \
    "note: static call path: noHeapBox -> boxInteger"
expect_failure_exact noheap_closure_bad \
    "error: '@NoHeapAlloc' not applicable to static call closure emitted heap allocation 'llvm.cj.malloc.object'" \
    "note: @NoHeapAlloc root is 'makeClosure'" \
    "note: static call path: makeClosure"
expect_failure_exact nowritebarrier_bad \
    "error: '@NoWriteBarrier' not applicable to static call closure emitted write barrier while lowering 'StoreElementRef'" \
    "note: @NoWriteBarrier root is 'barrier'" \
    "note: static call path: barrier"
expect_failure_exact nowritebarrierrec_bad \
    "error: '@NoWriteBarrierRec' not applicable to static call closure emitted write barrier while lowering 'StoreElementRef'" \
    "note: @NoWriteBarrierRec root is 'barrierRoot'" \
    "note: static call path: barrierRoot -> makeHolder -> init"
expect_failure_exact nowritebarrierrec_cycle_bad \
    "error: '@NoWriteBarrierRec' not applicable to static call closure emitted write barrier while lowering 'StoreElementRef'" \
    "  # note: recursive static-call cycle: cycleRoot -> cycleA -> cycleB -> cycleA" \
    "note: @NoWriteBarrierRec root is 'cycleRoot'" \
    "note: static call path: cycleRoot -> cycleA -> init"
expect_failure_exact nowritebarrierrec_aggregate_bad \
    "error: '@NoWriteBarrierRec' not applicable to static call closure emitted write barrier while lowering 'Apply'" \
    "note: @NoWriteBarrierRec root is 'aggregateBarrier'" \
    "note: static call path: aggregateBarrier"
expect_failure_exact nowritebarrierrec_tuple_bad \
    "error: '@NoWriteBarrierRec' not applicable to static call closure emitted write barrier while lowering 'Tuple'" \
    "note: @NoWriteBarrierRec root is 'tupleBarrier'" \
    "note: static call path: tupleBarrier"
expect_failure_exact nowritebarrierrec_box_bad \
    "error: '@NoWriteBarrierRec' not applicable to static call closure emitted write barrier while lowering 'Box'" \
    "note: @NoWriteBarrierRec root is 'boxBarrier'" \
    "note: static call path: boxBarrier"
expect_failure_exact invalid_target \
    "error: class cannot be modified with '@NoStackGrow'"
expect_failure_exact systemstack_invalid_target \
    "error: class cannot be modified with '@SystemStack'"

if (cd "$WORK" && "$CJC" "$FIXTURES/nostackgrow.cj" --output-type=staticlib \
    -o "$WORK/libnostackgrow.a") >"$WORK/nostackgrow.out" 2>&1; then
    for bitcode in "$WORK"/.cached/*.bc; do
        "$CANGJIE_HOME/third_party/llvm/bin/llvm-dis" "$bitcode" -o "$bitcode.ll" 2>/dev/null || true
    done
fi
nostack_ir="$(rg -l 'define .*noGrow.*#[0-9]+' "$WORK"/.cached/*.ll 2>/dev/null | head -n 1)"
nostack_attr=""
if [ -n "$nostack_ir" ]; then
    nostack_attr="$(rg 'define .*noGrow.*#[0-9]+' "$nostack_ir" | head -n 1 | sed -E 's/.*#([0-9]+).*/\1/')"
fi
if [ -n "$nostack_attr" ] && rg "attributes #$nostack_attr = .*\"gc-leaf-function\"" "$nostack_ir" >/dev/null; then
    pass "NoStackGrow emits gc-leaf-function"
else
    fail "NoStackGrow LLVM attribute"
    sed -n '1,30p' "$WORK/nostackgrow.out"
fi

echo "W4ANNOT: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
