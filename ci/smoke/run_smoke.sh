#!/usr/bin/env bash
# Smoke driver: compile+run each ci/smoke sample with a deployed cjcj and check output.
# Usage: run_smoke.sh <cjcj-binary> [workdir]
#   <cjcj-binary>  needs a sibling ../runtime (macro engine resolves <bin>/../runtime/lib/<host>);
#                  a release bin/cjcj satisfies this.
#   [workdir]      scratch dir, default mktemp.
# Requires CANGJIE_HOME / LD_LIBRARY_PATH / cjHeapSize exported by the caller.
# Exits non-zero on any compile failure or output mismatch.
set -uo pipefail

CJCJ="${1:?usage: run_smoke.sh <cjcj-binary> [workdir]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${2:-$(mktemp -d)}"
mkdir -p "$WORK"

if [ ! -x "$CJCJ" ]; then
    echo "FATAL: cjcj binary not executable: $CJCJ" >&2
    exit 2
fi

pass=0
fail=0

# single-file sample -> expected output
declare -A EXPECT=(
    ["01_hello"]="hello from cjcj"
    ["02_generics"]="42 hi 7"
    ["03_closures"]="30"
    ["04_iface_enum"]="12.560000 3"
    ["05_ffi"]="7"
)

run_one() {
    local name="$1" expect="$2"
    local src="$HERE/${name}.cj" exe="$WORK/${name}"
    echo "--- smoke: ${name} ---"
    if ! "$CJCJ" "$src" -o "$exe" >"$WORK/${name}.build.log" 2>&1; then
        echo "  COMPILE FAIL:"; sed 's/^/    /' "$WORK/${name}.build.log"; fail=$((fail+1)); return
    fi
    local got; got="$("$exe" 2>"$WORK/${name}.run.log")"
    if [ "$got" = "$expect" ]; then
        echo "  OK  -> [$got]"; pass=$((pass+1))
    else
        echo "  OUTPUT MISMATCH: expected [$expect] got [$got]"; fail=$((fail+1))
    fi
}

for name in 01_hello 02_generics 03_closures 04_iface_enum 05_ffi; do
    run_one "$name" "${EXPECT[$name]}"
done

# macro sample: two-step compile (--compile-macro, then --import-path)
echo "--- smoke: 06_macro ---"
MDIR="$HERE/macro_demo"
MBUILD="$WORK/macro_demo"; rm -rf "$MBUILD"; cp -r "$MDIR" "$MBUILD"
macro_ok=1
if ! ( cd "$MBUILD/mymacros" && "$CJCJ" --compile-macro def.cj ) >"$WORK/macro.build.log" 2>&1; then
    echo "  MACRO-PKG COMPILE FAIL:"; sed 's/^/    /' "$WORK/macro.build.log"; macro_ok=0
fi
if [ "$macro_ok" = 1 ]; then
    if ! ( cd "$MBUILD/app" && "$CJCJ" main.cj --import-path "$MBUILD/mymacros" -o "$MBUILD/app/app" ) >"$WORK/macro.app.log" 2>&1; then
        echo "  MACRO-APP COMPILE FAIL:"; sed 's/^/    /' "$WORK/macro.app.log"; macro_ok=0
    fi
fi
if [ "$macro_ok" = 1 ]; then
    got="$("$MBUILD/app/app" 2>"$WORK/macro.run.log")"
    want="$(printf 'tick\ntick')"
    if [ "$got" = "$want" ]; then echo "  OK  -> [${got//$'\n'/\\n}]"; pass=$((pass+1)); else
        echo "  OUTPUT MISMATCH: expected [tick\\ntick] got [${got//$'\n'/\\n}]"; fail=$((fail+1)); fi
else
    fail=$((fail+1))
fi

echo "==================================="
echo "smoke summary: pass=$pass fail=$fail (workdir=$WORK)"
[ "$fail" -eq 0 ]
