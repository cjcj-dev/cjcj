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
    printf 'SEPTEST-FAIL %s\n' "$1"
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

"$REF" "$WORK/pkgA/pkgA.cj" --output-type=staticlib -o "$WORK/pkgA/libpkgA.a" --set-runtime-rpath \
    >"$WORK/pkgA.ref.stdout" 2>"$WORK/pkgA.ref.stderr" ||
    fail "reference pkgA compile failed: $(tr '\n' ' ' <"$WORK/pkgA.ref.stderr")"

[[ -f "$WORK/pkgA/pkgA.cjo" ]] || fail "reference pkgA did not produce pkgA.cjo"
[[ -f "$WORK/pkgA/libpkgA.a" ]] || fail "reference pkgA did not produce libpkgA.a"

run_case() {
    local name="$1"
    local expected="$2"
    local src="$WORK/pkgB/$name.cj"
    local ref_exe="$WORK/ref/$name"
    local self_exe="$WORK/self/$name"

    "$REF" "$src" --import-path "$WORK/pkgA" -L "$WORK/pkgA" -lpkgA \
        -o "$ref_exe" --set-runtime-rpath >"$WORK/$name.ref.stdout" 2>"$WORK/$name.ref.stderr" ||
        fail "reference pkgB $name compile failed: $(tr '\n' ' ' <"$WORK/$name.ref.stderr")"

    "$SELF" "$src" --import-path "$WORK/pkgA" -L "$WORK/pkgA" -lpkgA \
        -o "$self_exe" --set-runtime-rpath >"$WORK/$name.self.stdout" 2>"$WORK/$name.self.stderr" ||
        fail "selfhost pkgB $name compile failed: $(tr '\n' ' ' <"$WORK/$name.self.stderr")"

    local ref_out self_out ref_status self_status
    set +e
    ref_out=$("$ref_exe" 2>"$WORK/$name.ref.run.stderr")
    ref_status=$?
    self_out=$("$self_exe" 2>"$WORK/$name.self.run.stderr")
    self_status=$?
    set -e

    [[ "$ref_status" -eq "$self_status" ]] ||
        fail "$name exit mismatch: reference=$ref_status selfhost=$self_status"
    [[ "$ref_out" = "$self_out" ]] ||
        fail "$name output mismatch: reference='$ref_out' selfhost='$self_out'"
    [[ "$self_out" = "$expected" ]] ||
        fail "$name output '$self_out' did not match expected '$expected'"

    printf 'SEPTEST-%s-PASS output=%s exit=%s\n' "$name" "$self_out" "$self_status"
}

run_case function 42
run_case function_single 42
run_case greeting "hello from pkgA"

printf 'SEPTEST-PASS\n'
