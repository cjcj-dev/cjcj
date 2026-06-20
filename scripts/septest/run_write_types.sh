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
    printf 'SEPTEST-WRITE-TYPES-FAIL %s\n' "$1"
    exit 1
}

[[ -x "$REF" ]] || fail "missing reference cjc at $REF"
[[ -x "$SELF" ]] || fail "missing selfhost cjc at $SELF"
[[ -d "$CANGJIE_HOME" ]] || fail "missing CANGJIE_HOME at $CANGJIE_HOME"

mkdir -p "$WORK/pkgA2" "$WORK/pkgB2" "$WORK/self" "$WORK/ref"
cp "$FIXTURE/pkgA2/pkgA2.cj" "$WORK/pkgA2/pkgA2.cj"
cp "$FIXTURE/pkgB2/use_types.cj" "$WORK/pkgB2/use_types.cj"

"$SELF" "$WORK/pkgA2/pkgA2.cj" --output-type=staticlib -o "$WORK/pkgA2/libpkgA2.a" --set-runtime-rpath \
    >"$WORK/pkgA2.self.stdout" 2>"$WORK/pkgA2.self.stderr" ||
    fail "selfhost pkgA2 compile failed: $(tr '\n' ' ' <"$WORK/pkgA2.self.stderr")"

[[ -f "$WORK/pkgA2/pkgA2.cjo" ]] || fail "selfhost pkgA2 did not produce pkgA2.cjo"
[[ -f "$WORK/pkgA2/libpkgA2.a" ]] || fail "selfhost pkgA2 did not produce libpkgA2.a"

magic=$(dd if="$WORK/pkgA2/pkgA2.cjo" bs=1 skip=4 count=4 2>/dev/null)
[[ "$magic" = "CJOF" ]] || fail "selfhost pkgA2.cjo has wrong file identifier '$magic'"
printf 'SEPTEST-WRITE-TYPES-PASS pkgA2 magic=CJOF\n'

run_case() {
    local compiler_name="$1"
    local compiler="$2"
    local exe="$WORK/$compiler_name/use_types"

    "$compiler" "$WORK/pkgB2/use_types.cj" --import-path "$WORK/pkgA2" -L "$WORK/pkgA2" -lpkgA2 \
        -o "$exe" --set-runtime-rpath >"$WORK/$compiler_name.use_types.stdout" 2>"$WORK/$compiler_name.use_types.stderr" ||
        fail "$compiler_name pkgB2 compile failed: $(tr '\n' ' ' <"$WORK/$compiler_name.use_types.stderr")"

    local output status
    set +e
    output=$("$exe" 2>"$WORK/$compiler_name.use_types.run.stderr")
    status=$?
    set -e

    [[ "$status" -eq 0 ]] || fail "$compiler_name pkgB2 exited with $status"
    [[ "$output" = "61" ]] ||
        fail "$compiler_name pkgB2 output '$output' did not match expected '61'"

    printf 'SEPTEST-WRITE-TYPES-PASS %s:use_types output=%s\n' "$compiler_name" "$output"
}

run_case self "$SELF"
run_case ref "$REF"

printf 'SEPTEST-WRITE-TYPES-PASS\n'
