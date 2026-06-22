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
    printf 'SEPTEST-DIAG-FAIL %s\n' "$1"
    exit 1
}

extract_field() {
    local field="$1"
    local file="$2"
    sed -n "s/.*\"$field\": \"\\(.*\\)\",/\\1/p" "$file" | head -n 1
}

extract_number_field() {
    local field="$1"
    local occurrence="$2"
    local file="$3"
    sed -n "s/.*\"$field\": \\([0-9][0-9]*\\).*/\\1/p" "$file" | sed -n "${occurrence}p"
}

assert_absent() {
    local needle="$1"
    local file="$2"
    if grep -Fq "$needle" "$file"; then
        fail "unexpected text '$needle' in $file"
    fi
}

[[ -x "$REF" ]] || fail "missing reference cjc at $REF"
[[ -x "$SELF" ]] || fail "missing selfhost cjc at $SELF"
[[ -d "$CANGJIE_HOME" ]] || fail "missing CANGJIE_HOME at $CANGJIE_HOME"

mkdir -p "$WORK/pkgA" "$WORK/pkgB" "$WORK/ref" "$WORK/self"
cp "$FIXTURE/pkgA/pkgA.cj" "$WORK/pkgA/pkgA.cj"
cp "$FIXTURE/pkgB/missing_decl.cj" "$WORK/pkgB/missing_decl.cj"
cp "$FIXTURE/pkgB/generic_func_without_type_arg.cj" "$WORK/pkgB/generic_func_without_type_arg.cj"

"$REF" "$WORK/pkgA/pkgA.cj" --output-type=staticlib -o "$WORK/pkgA/libpkgA.a" --set-runtime-rpath \
    >"$WORK/pkgA.ref.stdout" 2>"$WORK/pkgA.ref.stderr" ||
    fail "reference pkgA compile failed: $(tr '\n' ' ' <"$WORK/pkgA.ref.stderr")"

[[ -f "$WORK/pkgA/pkgA.cjo" ]] || fail "reference pkgA did not produce pkgA.cjo"
[[ -f "$WORK/pkgA/libpkgA.a" ]] || fail "reference pkgA did not produce libpkgA.a"

run_missing_decl() {
    local name="$1"
    local compiler="$2"
    local exe="$WORK/$name/missing_decl"

    set +e
    "$compiler" "$WORK/pkgB/missing_decl.cj" --diagnostic-format json \
        --import-path "$WORK/pkgA" -L "$WORK/pkgA" -lpkgA \
        -o "$exe" --set-runtime-rpath >"$WORK/$name.stdout" 2>"$WORK/$name.stderr"
    local rc=$?
    set -e

    [[ "$rc" -ne 0 ]] || fail "$name unexpectedly succeeded"
    printf 'SEPTEST-DIAG-PASS %s failed exit=%s\n' "$name" "$rc"
}

run_missing_decl ref "$REF"
run_missing_decl self "$SELF"

ref_kind=$(extract_field DiagKind "$WORK/ref.stderr")
self_kind=$(extract_field DiagKind "$WORK/self.stderr")
ref_message=$(extract_field Message "$WORK/ref.stderr")
self_message=$(extract_field Message "$WORK/self.stderr")
ref_range_begin_col=$(extract_number_field Column 2 "$WORK/ref.stderr")
ref_range_end_col=$(extract_number_field Column 3 "$WORK/ref.stderr")
self_range_begin_col=$(extract_number_field Column 2 "$WORK/self.stderr")
self_range_end_col=$(extract_number_field Column 3 "$WORK/self.stderr")

[[ "$ref_kind" = "package_decl_not_find_in_package" ]] ||
    fail "reference kind '$ref_kind' did not match package_decl_not_find_in_package"
printf 'SEPTEST-DIAG-PASS reference kind=%s\n' "$ref_kind"

[[ "$self_kind" = "$ref_kind" ]] ||
    fail "selfhost kind '$self_kind' did not match reference '$ref_kind'"
printf 'SEPTEST-DIAG-PASS selfhost kind matches reference\n'

[[ -n "$ref_message" ]] || fail "reference message was empty"
[[ "$self_message" = "$ref_message" ]] ||
    fail "selfhost message '$self_message' did not match reference '$ref_message'"
printf 'SEPTEST-DIAG-PASS selfhost message matches reference: %s\n' "$self_message"

case "$self_message" in
    *doesNotExist*pkgA*) ;;
    *) fail "selfhost message '$self_message' did not name missing decl and package" ;;
esac
printf 'SEPTEST-DIAG-PASS selfhost message names missing decl and package\n'

[[ -n "$ref_range_begin_col" && -n "$ref_range_end_col" ]] || fail "reference range columns were empty"
[[ -n "$self_range_begin_col" && -n "$self_range_end_col" ]] || fail "selfhost range columns were empty"
[[ "$self_range_begin_col" = "$ref_range_begin_col" && "$self_range_end_col" = "$ref_range_end_col" ]] ||
    fail "selfhost range columns ${self_range_begin_col}-${self_range_end_col} did not match reference ${ref_range_begin_col}-${ref_range_end_col}"
printf 'SEPTEST-DIAG-PASS selfhost range matches reference columns=%s-%s\n' \
    "$self_range_begin_col" "$self_range_end_col"

assert_absent "undeclared identifier" "$WORK/self.stderr"
printf 'SEPTEST-DIAG-PASS old diagnostic absent\n'

run_generic_func_without_type_arg() {
    local name="$1"
    local compiler="$2"
    local exe="$WORK/$name/generic_func_without_type_arg"

    set +e
    "$compiler" "$WORK/pkgB/generic_func_without_type_arg.cj" --diagnostic-format json \
        -o "$exe" --set-runtime-rpath >"$WORK/$name.generic.stdout" 2>"$WORK/$name.generic.stderr"
    local rc=$?
    set -e

    [[ "$rc" -ne 0 ]] || fail "$name generic func without type arg unexpectedly succeeded"
    printf 'SEPTEST-DIAG-PASS %s generic-func-without-type-arg failed exit=%s\n' "$name" "$rc"
}

run_generic_func_without_type_arg ref "$REF"
run_generic_func_without_type_arg self "$SELF"

ref_generic_kind=$(extract_field DiagKind "$WORK/ref.generic.stderr")
self_generic_kind=$(extract_field DiagKind "$WORK/self.generic.stderr")
ref_generic_message=$(extract_field Message "$WORK/ref.generic.stderr")
self_generic_message=$(extract_field Message "$WORK/self.generic.stderr")
ref_generic_range_begin_col=$(extract_number_field Column 2 "$WORK/ref.generic.stderr")
ref_generic_range_end_col=$(extract_number_field Column 3 "$WORK/ref.generic.stderr")
self_generic_range_begin_col=$(extract_number_field Column 2 "$WORK/self.generic.stderr")
self_generic_range_end_col=$(extract_number_field Column 3 "$WORK/self.generic.stderr")

[[ "$ref_generic_kind" = "sema_generic_func_without_type_arg" ]] ||
    fail "reference generic kind '$ref_generic_kind' did not match sema_generic_func_without_type_arg"
printf 'SEPTEST-DIAG-PASS reference generic kind=%s\n' "$ref_generic_kind"

[[ "$self_generic_kind" = "$ref_generic_kind" ]] ||
    fail "selfhost generic kind '$self_generic_kind' did not match reference '$ref_generic_kind'"
printf 'SEPTEST-DIAG-PASS selfhost generic kind matches reference\n'

[[ "$self_generic_message" = "$ref_generic_message" ]] ||
    fail "selfhost generic message '$self_generic_message' did not match reference '$ref_generic_message'"
printf 'SEPTEST-DIAG-PASS selfhost generic message matches reference: %s\n' "$self_generic_message"

[[ "$self_generic_message" = "type arguments needed for the generic function 'id'" ]] ||
    fail "selfhost generic message '$self_generic_message' did not name id"

[[ -n "$ref_generic_range_begin_col" && -n "$ref_generic_range_end_col" ]] ||
    fail "reference generic range columns were empty"
[[ -n "$self_generic_range_begin_col" && -n "$self_generic_range_end_col" ]] ||
    fail "selfhost generic range columns were empty"
[[ "$self_generic_range_begin_col" = "$ref_generic_range_begin_col" &&
    "$self_generic_range_end_col" = "$ref_generic_range_end_col" ]] ||
    fail "selfhost generic range columns ${self_generic_range_begin_col}-${self_generic_range_end_col} did not match reference ${ref_generic_range_begin_col}-${ref_generic_range_end_col}"
printf 'SEPTEST-DIAG-PASS selfhost generic range matches reference columns=%s-%s\n' \
    "$self_generic_range_begin_col" "$self_generic_range_end_col"

assert_absent "IllegalStateException" "$WORK/self.generic.stderr"
printf 'SEPTEST-DIAG-PASS selfhost generic diagnostic did not crash\n'

printf 'SEPTEST-DIAG-PASS\n'
