#!/usr/bin/env bash
# anno_gate.sh — annotation-focused compile/run gate for the selfhost compiler.
#
# Purpose: give the annotation-factory wiring (CHIR AST2CHIR TranslateAnnotation port,
# scattered across fix/subexprloc) a fixture-backed gate that the 114-file difftest
# corpus cannot provide (that corpus contains NO reflective custom annotations — only
# @When conditional-compilation and @C FFI, whose annotationsArray is empty). It
# compiles + runs a set of single-file programs that declare and/or use a minimal
# reflective `@Annotation` type at each decl mount point, records the reference
# compiler's behaviour (compile exit code, normalized diagnostics, run exit code) as
# golden, then replays the identical sequence with a selfhost compiler and diffs.
#
# Modes:
#   (default)            establish/refresh golden using the REFERENCE compiler
#   --self <cjc>         run the same sequence with <cjc> and diff against golden
#   --check              re-run REFERENCE and diff against golden (self-consistency)
#
# Env overrides:
#   CANGJIE_HOME   default the pinned nightly toolchain (std + runtime)
#   REF_CJC        default /root/.cjv/bin/cjc
#
# Fixture taxonomy (see the .cj headers):
#   w*  WIRED mount points (nominal defs + global var) — CreateAnnoFactorySignatures
#       attaches AnnoInfo and TranslateAnnoFactoryBodies emits the factory. Expected
#       to compile+run identically to the reference.
#   u*  WIRED mount point, annotated decl USED at a value site — exercises the whole
#       frontend→CHIR path end to end.
#   b*  BLOCKED mount points (function, enum constructor) — annotation-factory wiring
#       is intentionally not ported yet (recorded BLOCKED in the fix/subexprloc port).
#
# Notes:
#   * Fixtures compile in throwaway temp dirs; the committed fixture tree is never
#     polluted with .cached/binaries.
#   * The selfhost compiler reuses the reference CANGJIE_HOME for std + runtime; only
#     the cjc frontend binary differs.

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXROOT="$HERE/anno_fixtures"
GOLDEN_DIR="$FIXROOT/golden"

CANGJIE_HOME="${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}"
REF_CJC="${REF_CJC:-/root/.cjv/bin/cjc}"
RUNTIME_LIB="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative"
LLVM_LIB="$CANGJIE_HOME/third_party/llvm/lib"
TOOLS_LIB="$CANGJIE_HOME/tools/lib"

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
export LD_LIBRARY_PATH="$LLVM_LIB:$RUNTIME_LIB:$TOOLS_LIB:${LD_LIBRARY_PATH:-}"
export cjHeapSize="${cjHeapSize:-12GB}"   # selfhost cjc OOMs without an explicit heap size

if [ ! -x "$CJC" ]; then
    echo "FATAL: compiler not executable: $CJC" >&2
    exit 2
fi

mkdir -p "$GOLDEN_DIR"

# Ordered fixture list (basename without .cj).
FIXTURES=(
    w1_class_declonly
    w2_struct_declonly
    w3_globalvar_declonly
    w4_enum_declonly
    u1_class_used
    u2_globalvar_used
    b1_func_declonly
    b2_enum_ctor
)

# Normalize compiler output so golden is stable across build dirs / temp paths.
normalize() {
    sed -e 's/\x1b\[[0-9;]*m//g' \
        -e "s#$BUILD#<BUILD>#g" \
        -e 's#/tmp/cangjie-tmp-[^ '"'"']*#<TMP>#g' \
        -e 's#/root/cj_build/[^ '"'"']*#<CJC>#g' \
        -e "s#$CANGJIE_HOME#<HOME>#g" \
        -e 's/[[:space:]]*$//'
}

RESULTS=()
PASS=0
FAIL=0

for fx in "${FIXTURES[@]}"; do
    SRC="$FIXROOT/$fx.cj"
    if [ ! -f "$SRC" ]; then
        RESULTS+=("$fx: NO-FIXTURE")
        FAIL=$((FAIL+1))
        continue
    fi
    BUILD="$(mktemp -d)"
    TRANSCRIPT="$BUILD/transcript.txt"
    : > "$TRANSCRIPT"
    cp "$SRC" "$BUILD/prog.cj"

    # 1) compile (annotation expansion + CHIR annotation-factory generation under test)
    cout="$(cd "$BUILD" && "$CJC" prog.cj -o "$BUILD/app" 2>&1)"; crc=$?
    {
        echo "[compile] rc=$crc"
        printf '%s\n' "$cout" | normalize
    } >> "$TRANSCRIPT"
    # 2) run the produced binary (only if compile succeeded) and record its exit code
    if [ "$crc" -eq 0 ] && [ -x "$BUILD/app" ]; then
        "$BUILD/app" >/dev/null 2>&1; rrc=$?
        echo "[run] exit=$rrc" >> "$TRANSCRIPT"
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
echo "===== anno_gate summary ($LABEL) ====="
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
