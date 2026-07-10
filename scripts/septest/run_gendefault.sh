#!/usr/bin/env bash
set -euo pipefail
TC=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}
export CANGJIE_HOME="$TC"
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
FIXTURE="$REPO/scripts/septest"
REF=${REF_CJC:-/root/.cjv/bin/cjc}
SELF=${SELF_CJC:-"$REPO/target/release/bin/cjcj::cjc"}
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
fail() { printf 'SEPTEST-GENDEFAULT-FAIL %s\n' "$1"; exit 1; }
[[ -x "$REF" ]] || fail "missing reference cjc"
[[ -x "$SELF" ]] || fail "missing selfhost cjc"
mkdir -p "$WORK/dep"
cp "$FIXTURE/pkgGenDef/lib.cj" "$WORK/dep/lib.cj"
# Build the generic-default-param dependency with the REFERENCE cjc (canonical .cjo)
"$REF" "$WORK/dep/lib.cj" --output-type=staticlib -o "$WORK/dep/libpkgGenDef.a" --set-runtime-rpath \
    >"$WORK/dep.stdout" 2>"$WORK/dep.stderr" || fail "ref dep compile failed: $(tr '\n' ' ' <"$WORK/dep.stderr")"
run_consumer() {
    local who="$1" cc="$2"
    "$cc" "$FIXTURE/pkgGenDefUse/main.cj" --import-path "$WORK/dep" -L "$WORK/dep" -lpkgGenDef \
        -o "$WORK/use_$who" --set-runtime-rpath >"$WORK/$who.stdout" 2>"$WORK/$who.stderr" \
        || fail "$who consumer compile failed (imported generic-default-param mangle): $(tr '\n' ' ' <"$WORK/$who.stderr")"
    local out; out=$("$WORK/use_$who" 2>/dev/null) || fail "$who consumer run nonzero"
    printf '%s' "$out"
}
self_out=$(run_consumer self "$SELF")
ref_out=$(run_consumer ref "$REF")
[[ "$self_out" = "$ref_out" ]] || fail "selfhost '$self_out' != reference '$ref_out'"
[[ "$self_out" = "3" ]] || fail "output '$self_out' != expected 3"
printf 'SEPTEST-GENDEFAULT-PASS self=%s ref=%s\n' "$self_out" "$ref_out"
