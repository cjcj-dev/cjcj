#!/usr/bin/env bash

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURES="$ROOT/scripts/w4annot_fixtures"
CJC="${1:-$ROOT/target/release/bin/cangjie_compiler::cjc}"
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

expect_failure() {
    local name="$1"
    local expected="$2"
    local output="$WORK/$name.out"
    if (cd "$WORK" && "$CJC" "$FIXTURES/$name.cj" -o "$WORK/$name") >"$output" 2>&1; then
        fail "$name accepted"
    elif grep -F "$expected" "$output" >/dev/null; then
        pass "$name rejected with $expected"
    else
        fail "$name rejected without $expected"
        sed -n '1,20p' "$output"
    fi
}

if (cd "$WORK" && "$CJC" "$FIXTURES/legal.cj" -o "$WORK/legal") >"$WORK/legal.out" 2>&1 &&
    [ "$("$WORK/legal")" = "43" ]; then
    pass "legal annotations compile and run"
else
    fail "legal annotations"
    sed -n '1,20p' "$WORK/legal.out"
fi

expect_failure noheap_bad "@NoHeapAlloc"
expect_failure noheap_array_bad "RawArrayAllocate"
expect_failure noheap_box_bad "heap allocation 'Allocate'"
expect_failure nowritebarrierrec_bad "static call path: barrierRoot -> makeHolder"
expect_failure nowritebarrierrec_cycle_bad "recursive static-call cycle: cycleRoot -> cycleA -> cycleB -> cycleA"
expect_failure invalid_target "@NoStackGrow"

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
