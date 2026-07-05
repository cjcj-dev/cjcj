#!/usr/bin/env bash
# generic_gate.sh — generic-call resolution gate for the selfhost compiler.
#
# Purpose: give the sema C2 campaign (CheckGenericCallCompatible cluster,
# audit_persist/SEMA_C2_DESIGN.md) a fixture-backed gate the 114-file difftest
# corpus does not isolate: single-file programs that exercise generic-call
# resolution (constraint generics, overload resolution, nested instantiation,
# two-param return-target inference, ambiguous-overload diagnostics). Records the
# reference compiler's behaviour (compile exit, run exit, normalized output/diags)
# as golden; --self replays with a selfhost cjc and diffs.
#
# Modes:  (default) establish golden with REFERENCE cjc | --self <cjc> compare | --check
# Env:    CANGJIE_HOME (default /root/cj_build/cangjie_compiler/output), REF_CJC
#
# The selfhost cjc needs a large managed heap for some fixtures; the gate exports
# cjHeapSize=12GB (harmless for the C++ reference cjc).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXROOT="$HERE/generic_fixtures"
GOLDEN_DIR="$FIXROOT/golden"
CANGJIE_HOME="${CANGJIE_HOME:-/root/cj_build/cangjie_compiler/output}"
REF_CJC="${REF_CJC:-$CANGJIE_HOME/bin/cjc}"
RUNTIME_LIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"

MODE="golden"; CJC="$REF_CJC"; LABEL="reference"; EXTRA=""
while [ $# -gt 0 ]; do
    case "$1" in
        --self) MODE="self"; CJC="${2:?--self needs a cjc path}"; LABEL="selfhost"; EXTRA="--set-runtime-rpath"; shift 2 ;;
        --check) MODE="check"; CJC="$REF_CJC"; LABEL="reference-check"; shift ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
export CANGJIE_HOME
export LD_LIBRARY_PATH="$RUNTIME_LIB:${LD_LIBRARY_PATH:-}"
export cjHeapSize="${cjHeapSize:-12GB}"
[ -x "$CJC" ] || { echo "FATAL: compiler not executable: $CJC" >&2; exit 2; }

normalize() {
    sed -e 's/\x1b\[[0-9;]*m//g' -e "s#$WORK#<WORK>#g" \
        -e 's#/tmp/cangjie-tmp-[^ '"'"']*#<TMP>#g' -e "s#$CANGJIE_HOME#<HOME>#g" -e 's/[[:space:]]*$//'
}

mkdir -p "$GOLDEN_DIR"
FAIL=0; PASS=0; declare -a RESULTS
for src in "$FIXROOT"/*.cj; do
    name="$(basename "$src" .cj)"
    WORK="$(mktemp -d)"; TRANSCRIPT="$WORK/t.txt"; : > "$TRANSCRIPT"
    cp "$src" "$WORK/$name.cj"
    out="$("$CJC" "$WORK/$name.cj" -o "$WORK/$name.app" $EXTRA 2>&1)"; rc=$?
    { echo "[compile] rc=$rc"; printf '%s\n' "$out" | normalize; } >> "$TRANSCRIPT"
    if [ "$rc" = 0 ]; then
        rout="$(timeout 30 "$WORK/$name.app" 2>/dev/null)"; rrc=$?
        { echo "[run] exit=$rrc"; printf '%s\n' "$rout" | normalize; } >> "$TRANSCRIPT"
    fi
    GOLDEN="$GOLDEN_DIR/$name.golden"
    if [ "$MODE" = "golden" ]; then
        cp "$TRANSCRIPT" "$GOLDEN"; RESULTS+=("$name: golden written"); PASS=$((PASS+1))
    elif [ ! -f "$GOLDEN" ]; then
        RESULTS+=("$name: NO-GOLDEN"); FAIL=$((FAIL+1))
    elif diff -u "$GOLDEN" "$TRANSCRIPT" > "$WORK/d.txt" 2>&1; then
        RESULTS+=("$name: PASS"); PASS=$((PASS+1))
    else
        RESULTS+=("$name: FAIL (differs)"); FAIL=$((FAIL+1))
        echo "----- $name diff ($LABEL vs golden) -----"; cat "$WORK/d.txt"
    fi
    rm -rf "$WORK"
done
echo ""; echo "===== generic_gate summary ($LABEL) ====="
echo "compiler: $CJC"
for r in "${RESULTS[@]}"; do echo "  $r"; done
if [ "$MODE" = "golden" ]; then echo "GOLDEN-ESTABLISHED: $PASS"; exit 0
else echo "$LABEL COMPARISON: PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ] && exit 0 || exit 1; fi
