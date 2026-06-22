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

mkdir -p "$WORK/pkgA" "$WORK/pkgSig" "$WORK/pkgA4" "$WORK/pkgB" "$WORK/pkgB4" "$WORK/ref" "$WORK/self"
cp "$FIXTURE/pkgA/pkgA.cj" "$WORK/pkgA/pkgA.cj"
cp "$FIXTURE/pkgSig/pkgSig.cj" "$WORK/pkgSig/pkgSig.cj"
cp "$FIXTURE/pkgA4/pkgA4.cj" "$WORK/pkgA4/pkgA4.cj"
cp "$FIXTURE/pkgB/function.cj" "$WORK/pkgB/function.cj"
cp "$FIXTURE/pkgB/function_single.cj" "$WORK/pkgB/function_single.cj"
cp "$FIXTURE/pkgB/greeting.cj" "$WORK/pkgB/greeting.cj"
cp "$FIXTURE/pkgB/imported_signature.cj" "$WORK/pkgB/imported_signature.cj"
cp "$FIXTURE/pkgB4/protected_lub.cj" "$WORK/pkgB4/protected_lub.cj"

"$REF" "$WORK/pkgA/pkgA.cj" --output-type=staticlib -o "$WORK/pkgA/libpkgA.a" --set-runtime-rpath \
    >"$WORK/pkgA.ref.stdout" 2>"$WORK/pkgA.ref.stderr" ||
    fail "reference pkgA compile failed: $(tr '\n' ' ' <"$WORK/pkgA.ref.stderr")"

[[ -f "$WORK/pkgA/pkgA.cjo" ]] || fail "reference pkgA did not produce pkgA.cjo"
[[ -f "$WORK/pkgA/libpkgA.a" ]] || fail "reference pkgA did not produce libpkgA.a"

"$REF" "$WORK/pkgSig/pkgSig.cj" --output-type=staticlib -o "$WORK/pkgSig/libpkgSig.a" --set-runtime-rpath \
    >"$WORK/pkgSig.ref.stdout" 2>"$WORK/pkgSig.ref.stderr" ||
    fail "reference pkgSig compile failed: $(tr '\n' ' ' <"$WORK/pkgSig.ref.stderr")"

[[ -f "$WORK/pkgSig/pkgSig.cjo" ]] || fail "reference pkgSig did not produce pkgSig.cjo"
[[ -f "$WORK/pkgSig/libpkgSig.a" ]] || fail "reference pkgSig did not produce libpkgSig.a"

"$REF" "$WORK/pkgA4/pkgA4.cj" --output-type=staticlib -o "$WORK/pkgA4/libpkgA4.a" --set-runtime-rpath \
    >"$WORK/pkgA4.ref.stdout" 2>"$WORK/pkgA4.ref.stderr" ||
    fail "reference pkgA4 compile failed: $(tr '\n' ' ' <"$WORK/pkgA4.ref.stderr")"

[[ -f "$WORK/pkgA4/pkgA4.cjo" ]] || fail "reference pkgA4 did not produce pkgA4.cjo"
[[ -f "$WORK/pkgA4/libpkgA4.a" ]] || fail "reference pkgA4 did not produce libpkgA4.a"

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

"$REF" "$WORK/pkgB/imported_signature.cj" --import-path "$WORK/pkgSig" -L "$WORK/pkgSig" -lpkgSig \
    -o "$WORK/ref/imported_signature" --set-runtime-rpath \
    >"$WORK/imported_signature.ref.stdout" 2>"$WORK/imported_signature.ref.stderr" ||
    fail "reference pkgB imported_signature compile failed: $(tr '\n' ' ' <"$WORK/imported_signature.ref.stderr")"

"$SELF" "$WORK/pkgB/imported_signature.cj" --import-path "$WORK/pkgSig" -L "$WORK/pkgSig" -lpkgSig \
    -o "$WORK/self/imported_signature" --set-runtime-rpath \
    >"$WORK/imported_signature.self.stdout" 2>"$WORK/imported_signature.self.stderr" ||
    fail "selfhost pkgB imported_signature compile failed: $(tr '\n' ' ' <"$WORK/imported_signature.self.stderr")"

set +e
imported_ref_out=$("$WORK/ref/imported_signature" 2>"$WORK/imported_signature.ref.run.stderr")
imported_ref_status=$?
imported_self_out=$("$WORK/self/imported_signature" 2>"$WORK/imported_signature.self.run.stderr")
imported_self_status=$?
set -e

[[ "$imported_ref_status" -eq "$imported_self_status" ]] ||
    fail "imported_signature exit mismatch: reference=$imported_ref_status selfhost=$imported_self_status"
[[ "$imported_ref_out" = "$imported_self_out" ]] ||
    fail "imported_signature output mismatch: reference='$imported_ref_out' selfhost='$imported_self_out'"

printf 'SEPTEST-imported_signature-PASS output=%s exit=%s\n' "$imported_self_out" "$imported_self_status"

"$REF" "$WORK/pkgB4/protected_lub.cj" --import-path "$WORK/pkgA4" -L "$WORK/pkgA4" -lpkgA4 \
    -o "$WORK/ref/protected_lub" --set-runtime-rpath \
    >"$WORK/protected_lub.ref.stdout" 2>"$WORK/protected_lub.ref.stderr" ||
    fail "reference pkgB4 protected_lub compile failed: $(tr '\n' ' ' <"$WORK/protected_lub.ref.stderr")"

"$SELF" "$WORK/pkgB4/protected_lub.cj" --import-path "$WORK/pkgA4" -L "$WORK/pkgA4" -lpkgA4 \
    -o "$WORK/self/protected_lub" --set-runtime-rpath \
    >"$WORK/protected_lub.self.stdout" 2>"$WORK/protected_lub.self.stderr" ||
    fail "selfhost pkgB4 protected_lub compile failed: $(tr '\n' ' ' <"$WORK/protected_lub.self.stderr")"

set +e
protected_ref_out=$("$WORK/ref/protected_lub" 2>"$WORK/protected_lub.ref.run.stderr")
protected_ref_status=$?
protected_self_out=$("$WORK/self/protected_lub" 2>"$WORK/protected_lub.self.run.stderr")
protected_self_status=$?
set -e

[[ "$protected_ref_status" -eq "$protected_self_status" ]] ||
    fail "protected_lub exit mismatch: reference=$protected_ref_status selfhost=$protected_self_status"
[[ "$protected_ref_out" = "$protected_self_out" ]] ||
    fail "protected_lub output mismatch: reference='$protected_ref_out' selfhost='$protected_self_out'"
[[ "$protected_self_out" = "17" ]] ||
    fail "protected_lub output '$protected_self_out' did not match expected '17'"

printf 'SEPTEST-protected_lub-PASS output=%s exit=%s\n' "$protected_self_out" "$protected_self_status"

printf 'SEPTEST-PASS\n'
