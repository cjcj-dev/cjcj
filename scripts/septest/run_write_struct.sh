#!/usr/bin/env bash
set -euo pipefail

TC=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export CANGJIE_HOME="$TC"
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$REPO/scripts/septest"
REF=${REF_CJC:-/root/.cjv/bin/cjc}
SELF=${SELF_CJC:-"$REPO/target/release/bin/cjcj::cjc"}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

fail() {
    printf 'SEPTEST-WRITE-STRUCT-FAIL %s\n' "$1"
    exit 1
}

[[ -x "$REF" ]] || fail "missing reference cjc at $REF"
[[ -x "$SELF" ]] || fail "missing selfhost cjc at $SELF"
[[ -d "$CANGJIE_HOME" ]] || fail "missing CANGJIE_HOME at $CANGJIE_HOME"

mkdir -p "$WORK/pkgA3" "$WORK/pkgB3" "$WORK/self" "$WORK/ref"
cp "$FIXTURE/pkgA3/pkgA3.cj" "$WORK/pkgA3/pkgA3.cj"
cp "$FIXTURE/pkgB3/use_struct.cj" "$WORK/pkgB3/use_struct.cj"

"$SELF" "$WORK/pkgA3/pkgA3.cj" --output-type=staticlib -o "$WORK/pkgA3/libpkgA3.a" --set-runtime-rpath \
    >"$WORK/pkgA3.self.stdout" 2>"$WORK/pkgA3.self.stderr" ||
    fail "selfhost pkgA3 compile failed: $(tr '\n' ' ' <"$WORK/pkgA3.self.stderr")"

[[ -f "$WORK/pkgA3/pkgA3.cjo" ]] || fail "selfhost pkgA3 did not produce pkgA3.cjo"
[[ -f "$WORK/pkgA3/libpkgA3.a" ]] || fail "selfhost pkgA3 did not produce libpkgA3.a"

magic=$(dd if="$WORK/pkgA3/pkgA3.cjo" bs=1 skip=4 count=4 2>/dev/null)
[[ "$magic" = "CJOF" ]] || fail "selfhost pkgA3.cjo has wrong file identifier '$magic'"
printf 'SEPTEST-WRITE-STRUCT-PASS pkgA3 magic=CJOF\n'

run_case() {
    local compiler_name="$1"
    local compiler="$2"
    local exe="$WORK/$compiler_name/use_struct"

    "$compiler" "$WORK/pkgB3/use_struct.cj" --import-path "$WORK/pkgA3" -L "$WORK/pkgA3" -lpkgA3 \
        -o "$exe" --set-runtime-rpath >"$WORK/$compiler_name.use_struct.stdout" 2>"$WORK/$compiler_name.use_struct.stderr" ||
        fail "$compiler_name pkgB3 compile failed: $(tr '\n' ' ' <"$WORK/$compiler_name.use_struct.stderr")"

    local output status
    set +e
    output=$("$exe" 2>"$WORK/$compiler_name.use_struct.run.stderr")
    status=$?
    set -e

    [[ "$status" -eq 0 ]] || fail "$compiler_name pkgB3 exited with $status"
    [[ "$output" = "49" ]] ||
        fail "$compiler_name pkgB3 output '$output' did not match expected '49'"

    printf 'SEPTEST-WRITE-STRUCT-PASS %s:use_struct output=%s\n' "$compiler_name" "$output"
}

run_case self "$SELF"
run_case ref "$REF"

printf 'SEPTEST-WRITE-STRUCT-PASS\n'
