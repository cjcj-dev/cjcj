#!/usr/bin/env bash
# test_gate.sh — `--test` / mock focused compile gate for the selfhost compiler.
#
# Purpose: give the TestManager+Mock live-integration campaign (design doc
# audit_persist/TESTMANAGER_LIVE_DESIGN.md, slice S5) a fixture-backed gate that
# the 114-file difftest corpus and sc_bcgate cannot provide (neither contains any
# `--test`/mock samples). It compiles a set of `--test` fixtures and records the
# reference compiler's behaviour (compile exit code, test-binary run exit code,
# and the presence of `--test`/mock entry symbols) as golden, then can replay the
# identical sequence with a selfhost compiler and diff against golden.
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
#   * Baseline expectation while slices S3/S4 are not yet wired: the selfhost
#     `--test` build may diverge from golden (no mark pass, no mock accessors).
#     Recording that divergence is the intended baseline for this gate.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXROOT="$HERE/test_fixtures"
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
# The selfhost cjc is itself a Cangjie program; compiling the std.unittest-heavy
# fixtures needs a large managed heap or it OOMs. Harmless for the C++ reference cjc.
export cjHeapSize="${cjHeapSize:-12GB}"

if [ ! -x "$CJC" ]; then
    echo "FATAL: compiler not executable: $CJC" >&2
    exit 2
fi

# Ordered fixture list. Each is a directory under test_fixtures/ with a single
# package source; compile commands are fixture-specific (see run_fixture).
FIXTURES=(t1_test_basic t2_mock_member t3_test_vs_normal)

# Normalize compiler output so golden is stable across build dirs / temp paths.
normalize() {
    sed -e 's/\x1b\[[0-9;]*m//g' \
        -e "s#$BUILD#<BUILD>#g" \
        -e 's#/tmp/cangjie-tmp-[^ '"'"']*#<TMP>#g' \
        -e "s#$CANGJIE_HOME#<HOME>#g" \
        -e 's/[[:space:]]*$//'
}

# Run a compiler command; append "[tag] rc=<n>" then normalized combined output.
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

# Run a produced binary (timeout-guarded); record only its exit code, never its
# stdout (test-runner stdout carries timings / progress bars that are not stable).
record_run() {
    local tag="$1" bin="$2"
    if [ -x "$bin" ]; then
        timeout 60 "$bin" >/dev/null 2>&1; echo "[$tag] exit=$?" >> "$TRANSCRIPT"
    else
        echo "[$tag] exit=<no-binary>" >> "$TRANSCRIPT"
    fi
}

# Run a binary and record BOTH its exit code and its stdout. Use only for binaries
# with deterministic, timing-free stdout (e.g. a plain `main` that prints a value),
# so the normal-vs-`--test` product difference is visible in golden.
record_run_out() {
    local tag="$1" bin="$2"
    if [ -x "$bin" ]; then
        local out rc
        out="$(timeout 60 "$bin" 2>/dev/null)"; rc=$?
        { echo "[$tag] exit=$rc"; printf '%s\n' "$out" | normalize; } >> "$TRANSCRIPT"
    else
        echo "[$tag] exit=<no-binary>" >> "$TRANSCRIPT"
    fi
}

# Record a stable count of the `--test`/mock entry symbols in a binary. Names are
# deterministic from the source; addresses are dropped by counting only.
record_syms() {
    local tag="$1" bin="$2"
    if [ ! -x "$bin" ]; then
        echo "[$tag] <no-binary>" >> "$TRANSCRIPT"
        return
    fi
    local nmout; nmout="$(nm "$bin" 2>/dev/null)"
    {
        echo "[$tag]"
        echo "  TestPackage=$(printf '%s\n' "$nmout" | grep -c 'TestPackage')"
        echo "  registerSuite=$(printf '%s\n' "$nmout" | grep -cE 'register[A-Za-z0-9_]*Suite')"
        echo "  testEntry=$(printf '%s\n' "$nmout" | grep -c 'entry_main')"
        echo "  ToMock=$(printf '%s\n' "$nmout" | grep -c 'ToMock')"
    } >> "$TRANSCRIPT"
}

run_fixture() {
    local fx="$1"
    case "$fx" in
        t1_test_basic)
            record "compile-test" "$CJC" --test "$BUILD/basic_test.cj" -o "$BUILD/t1.app"
            record_run "run-test" "$BUILD/t1.app"
            record_syms "symbols-test" "$BUILD/t1.app"
            ;;
        t2_mock_member)
            record "compile-test-mock" "$CJC" --test --mock=on "$BUILD/mock_test.cj" -o "$BUILD/t2.app"
            record_run "run-test-mock" "$BUILD/t2.app"
            record_syms "symbols-test-mock" "$BUILD/t2.app"
            ;;
        t3_test_vs_normal)
            # Same source, two modes: normal builds a `main` app; --test builds the
            # test runner. The product difference is the behaviour under test.
            record "compile-normal" "$CJC" "$BUILD/dual.cj" -o "$BUILD/t3_normal.app"
            record_run_out "run-normal" "$BUILD/t3_normal.app"
            record_syms "symbols-normal" "$BUILD/t3_normal.app"
            record "compile-test" "$CJC" --test "$BUILD/dual.cj" -o "$BUILD/t3_test.app"
            record_run "run-test" "$BUILD/t3_test.app"
            record_syms "symbols-test" "$BUILD/t3_test.app"
            ;;
    esac
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

    cp "$SRC"/*.cj "$BUILD/"
    run_fixture "$fx"

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
echo "===== test_gate summary ($LABEL) ====="
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
