#!/usr/bin/env bash
set -euo pipefail

TC=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export CANGJIE_HOME="$TC"
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$REPO/scripts/septest"
REF=${REF_CJC:-/root/.cjv/bin/cjc}
SELF=${SELF_CJC:-"$REPO/target/release/bin/cangjie_compiler::cjc"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail() {
    printf 'SEPTEST-WRITE-FAIL %s\n' "$1"
    exit 1
}

[[ -x "$REF" ]] || fail "missing reference cjc at $REF"
[[ -x "$SELF" ]] || fail "missing selfhost cjc at $SELF"
[[ -d "$CANGJIE_HOME" ]] || fail "missing CANGJIE_HOME at $CANGJIE_HOME"

mkdir -p "$WORK/pkgA" "$WORK/pkgB" "$WORK/ref" "$WORK/self"
cp "$FIXTURE/pkgA/pkgA.cj" "$WORK/pkgA/pkgA.cj"
cp "$FIXTURE/pkgB/function.cj" "$WORK/pkgB/function.cj"
cp "$FIXTURE/pkgB/function_single.cj" "$WORK/pkgB/function_single.cj"
cp "$FIXTURE/pkgB/greeting.cj" "$WORK/pkgB/greeting.cj"

"$SELF" "$WORK/pkgA/pkgA.cj" --output-type=staticlib -o "$WORK/pkgA/libpkgA.a" --set-runtime-rpath \
    >"$WORK/pkgA.self.stdout" 2>"$WORK/pkgA.self.stderr" ||
    fail "selfhost pkgA compile failed: $(tr '\n' ' ' <"$WORK/pkgA.self.stderr")"

[[ -f "$WORK/pkgA/pkgA.cjo" ]] || fail "selfhost pkgA did not produce pkgA.cjo"
[[ -f "$WORK/pkgA/libpkgA.a" ]] || fail "selfhost pkgA did not produce libpkgA.a"

magic=$(dd if="$WORK/pkgA/pkgA.cjo" bs=1 skip=4 count=4 2>/dev/null)
[[ "$magic" = "CJOF" ]] || fail "selfhost pkgA.cjo has wrong file identifier '$magic'"
printf 'SEPTEST-WRITE-PASS pkgA magic=CJOF\n'

run_case() {
    local compiler_name="$1"
    local compiler="$2"
    local name="$3"
    local expected="$4"
    local src="$WORK/pkgB/$name.cj"
    local exe="$WORK/$compiler_name/$name"

    "$compiler" "$src" --import-path "$WORK/pkgA" -L "$WORK/pkgA" -lpkgA \
        -o "$exe" --set-runtime-rpath >"$WORK/$compiler_name.$name.stdout" 2>"$WORK/$compiler_name.$name.stderr" ||
        fail "$compiler_name pkgB $name compile failed: $(tr '\n' ' ' <"$WORK/$compiler_name.$name.stderr")"

    local output status
    set +e
    output=$("$exe" 2>"$WORK/$compiler_name.$name.run.stderr")
    status=$?
    set -e

    [[ "$status" -eq 0 ]] || fail "$compiler_name pkgB $name exited with $status"
    [[ "$output" = "$expected" ]] ||
        fail "$compiler_name pkgB $name output '$output' did not match expected '$expected'"

    printf 'SEPTEST-WRITE-PASS %s:%s output=%s\n' "$compiler_name" "$name" "$output"
}

run_case self "$SELF" function 42
run_case self "$SELF" function_single 42
run_case self "$SELF" greeting "hello from pkgA"
run_case ref "$REF" function 42
run_case ref "$REF" greeting "hello from pkgA"

printf 'SEPTEST-WRITE-PASS\n'
