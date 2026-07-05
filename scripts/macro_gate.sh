#!/usr/bin/env bash
# macro_gate.sh — macro-focused compile/expand gate for the selfhost compiler.
#
# Purpose: give the frontend<->macro integration campaign (design doc
# audit_persist/MACRO_INTEGRATION_DESIGN.md, slice S4) a fixture-backed gate that
# the 114-file difftest corpus cannot provide (that corpus contains no real macro
# samples). It compiles a set of macro packages + user packages and records the
# reference compiler's behaviour (exit codes, normalized diagnostics, run result)
# as golden, then can replay the identical sequence with a selfhost compiler and
# diff against golden.
#
# Modes:
#   (default)            establish/refresh golden using the REFERENCE compiler
#   --self <cjc>         run the same sequence with <cjc> and diff against golden
#   --check              re-run REFERENCE and diff against golden (self-consistency)
#
# Env overrides:
#   CANGJIE_HOME   default /root/cj_build/cangjie_compiler/output (std + runtime)
#   REF_CJC        default $CANGJIE_HOME/bin/cjc
#
# Notes:
#   * Fixtures are built in throwaway temp dirs; the committed fixture tree is
#     never polluted with .cjo/.so/binaries.
#   * The selfhost compiler is assumed to reuse the reference CANGJIE_HOME for the
#     std library and runtime; only the cjc frontend binary differs.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXROOT="$HERE/macro_fixtures"
GOLDEN_DIR="$FIXROOT/golden"

CANGJIE_HOME="${CANGJIE_HOME:-/root/cj_build/cangjie_compiler/output}"
REF_CJC="${REF_CJC:-$CANGJIE_HOME/bin/cjc}"
RUNTIME_LIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"

MODE="golden"        # golden | self | check
CJC="$REF_CJC"
LABEL="reference"

while [ $# -gt 0 ]; do
    case "$1" in
        --self) MODE="self"; CJC="${2:?--self needs a cjc path}"; LABEL="selfhost"; shift 2 ;;
        --check) MODE="check"; CJC="$REF_CJC"; LABEL="reference-check"; shift ;;
        -h|--help) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

export CANGJIE_HOME
export LD_LIBRARY_PATH="$RUNTIME_LIB:${LD_LIBRARY_PATH:-}"

if [ ! -x "$CJC" ]; then
    echo "FATAL: compiler not executable: $CJC" >&2
    exit 2
fi

# Ordered fixture list. Each is a directory under macro_fixtures/ containing
# mdef/ (macro package) and use/ (user package); f5 additionally has control/.
FIXTURES=(f1_decl_identity f2_multi_decl f3_nested f4_attr_macro f5_unused_import)

# Normalize compiler output so golden is stable across build dirs / temp paths.
normalize() {
    sed -e 's/\x1b\[[0-9;]*m//g' \
        -e "s#$BUILD#<BUILD>#g" \
        -e 's#/tmp/cangjie-tmp-[^ '"'"']*#<TMP>#g' \
        -e "s#$CANGJIE_HOME#<HOME>#g" \
        -e 's/[[:space:]]*$//'
}

# Run a compiler command; append "rc=<n>" then normalized combined output to $OUT.
record() {
    local tag="$1"; shift
    local out rc
    out="$("$@" 2>&1)"; rc=$?
    {
        echo "[$tag] rc=$rc"
        printf '%s\n' "$out" | normalize
    } >> "$TRANSCRIPT"
    return $rc
}

mkdir -p "$GOLDEN_DIR"
FAIL=0
PASS=0
declare -a RESULTS

for fx in "${FIXTURES[@]}"; do
    SRC="$FIXROOT/$fx"
    BUILD="$(mktemp -d)"
    TRANSCRIPT="$BUILD/transcript.txt"
    : > "$TRANSCRIPT"

    cp -r "$SRC/mdef" "$SRC/use" "$BUILD/"
    [ -d "$SRC/control" ] && cp -r "$SRC/control" "$BUILD/"
    mkdir -p "$BUILD/out"

    # 1) compile the macro-definition package into an output dir (setup; -Woff
    #    unused keeps it clean). --compile-macro names the .cjo/.so after the
    #    package and requires an existing directory for -o.
    record "macro-compile" "$CJC" --compile-macro "$BUILD"/mdef/*.cj -Woff unused -o "$BUILD/out"

    # 2) compile the user package (this triggers macro expansion — behaviour under test)
    if record "user-compile" "$CJC" "$BUILD"/use/*.cj --import-path "$BUILD/out" -o "$BUILD/use/app"; then
        # 3) run the produced binary and record its exit code
        "$BUILD/use/app" >/dev/null 2>&1; runrc=$?
        echo "[run] exit=$runrc" >> "$TRANSCRIPT"
    fi

    # 4) f5 control: a genuinely unused wildcard import must still warn
    if [ -d "$BUILD/control" ]; then
        record "control-compile" "$CJC" "$BUILD"/control/*.cj -o "$BUILD/control/app"
    fi

    GOLDEN="$GOLDEN_DIR/$fx.golden"
    if [ "$MODE" = "golden" ]; then
        cp "$TRANSCRIPT" "$GOLDEN"
        RESULTS+=("$fx: golden written")
        PASS=$((PASS+1))
    else
        if [ ! -f "$GOLDEN" ]; then
            RESULTS+=("$fx: NO-GOLDEN")
            FAIL=$((FAIL+1))
        elif diff -u "$GOLDEN" "$TRANSCRIPT" > "$BUILD/diff.txt" 2>&1; then
            RESULTS+=("$fx: PASS")
            PASS=$((PASS+1))
        else
            RESULTS+=("$fx: FAIL (differs from golden)")
            FAIL=$((FAIL+1))
            echo "----- $fx diff ($LABEL vs golden) -----"
            cat "$BUILD/diff.txt"
        fi
    fi

    rm -rf "$BUILD"
done

echo ""
echo "===== macro_gate summary ($LABEL) ====="
echo "compiler: $CJC"
echo "CANGJIE_HOME: $CANGJIE_HOME"
for r in "${RESULTS[@]}"; do echo "  $r"; done
if [ "$MODE" = "golden" ]; then
    echo "GOLDEN-ESTABLISHED: $PASS fixtures written to $GOLDEN_DIR"
    exit 0
else
    echo "$LABEL COMPARISON: PASS=$PASS FAIL=$FAIL"
    [ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi
