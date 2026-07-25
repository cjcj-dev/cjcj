#!/bin/bash
# Stub-backed ObjC BeforeTypeCheck parity gate. The Linux SDK has no objc.internal/objc.lang modules,
# so the AST dump is the product: it proves the Desugar.cpp branches ran before the intentional
# missing-objc.lang diagnostic frontier. It does not validate ObjC runtime glue or macOS execution.
# Integration prerequisite: ffin0 commit 0719a1ee (the real ObjC PrepareTypeCheck entry wiring).
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
fixtures="$root/scripts/objc_interop_fixtures"
toolchain=${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458}
reference=${OBJC_GATE_REFERENCE:-$toolchain/bin/cjc}
self=${OBJC_GATE_SELF:-$root/target/release/bin/cjcj::cjc}
jobs=${OBJC_GATE_JOBS:-24}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --self) self=${2:?--self requires a compiler path}; shift 2 ;;
        --reference) reference=${2:?--reference requires a compiler path}; shift 2 ;;
        -j|--jobs) jobs=${2:?--jobs requires a number}; shift 2 ;;
        -h|--help)
            echo "usage: $0 [--self CJC] [--reference CJC] [-j JOBS]"
            exit 0
            ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [ ! -x "$reference" ]; then echo "FATAL reference compiler is not executable: $reference" >&2; exit 2; fi
if [ ! -x "$self" ]; then echo "FATAL candidate compiler is not executable: $self" >&2; exit 2; fi
if ! [[ "$jobs" =~ ^[1-9][0-9]*$ ]]; then echo "FATAL invalid jobs: $jobs" >&2; exit 2; fi

export CANGJIE_HOME="$toolchain"
export LD_LIBRARY_PATH="$toolchain/third_party/llvm/lib:$toolchain/runtime/lib/linux_x86_64_cjnative:$toolchain/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize=${cjHeapSize:-24GB}

work=$(mktemp -d /tmp/objc-interop-gate.XXXXXX)
cleanup() {
    if [ "${OBJC_GATE_KEEP_WORK:-0}" = 1 ]; then
        echo "OBJC_GATE_WORKDIR=$work"
    else
        rm -rf "$work"
    fi
}
trap cleanup EXIT

mkdir -p "$work/stub-src" "$work/import/objc" "$work/source"
cp "$fixtures/stub_objc_internal.cj" "$work/stub-src/stub.cj"
cp "$fixtures/mirrors.cj" "$work/source/mirrors.cj"

(cd "$work" && "$reference" -j "$jobs" -p stub-src --module-name objc.internal \
    --output-dir import/objc --output-type=staticlib -o stub.a) >"$work/stub-build.log" 2>&1
stub_rc=$?
if [ "$stub_rc" -ne 0 ] || [ ! -f "$work/import/objc/objc.internal.cjo" ]; then
    echo "FAIL stub objc.internal build rc=$stub_rc"
    sed -n '1,80p' "$work/stub-build.log"
    exit 1
fi

compile_one() {
    local label=$1
    local compiler=$2
    (cd "$work/source" && "$compiler" -j "$jobs" mirrors.cj --import-path "$work/import" \
        --diagnostic-format=noColor --output-type=staticlib --dump-ast --dump-to-screen \
        -o "$label.a") >"$work/$label.dump" 2>&1
    echo $? >"$work/$label.rc"
    rm -f "$work/source/$label.a"
}

compile_one official "$reference"
compile_one candidate "$self"

extract_section() {
    local dump=$1
    local start=$2
    local stop=$3
    local output=$4
    awk -v start="$start" -v stop="$stop" '
        index($0, "ClassDecl: " start " {") { active = 1 }
        active && stop != "" && index($0, "ClassDecl: " stop " {") { exit }
        active { print }
    ' "$dump" >"$output"
}

has_text() {
    if grep -Fq "$1" "$2"; then printf 1; else printf 0; fi
}

count_text() {
    local count
    count=$(grep -F -c "$1" "$2" 2>/dev/null || true)
    printf '%s' "$count"
}

make_manifest() {
    local label=$1
    local dump="$work/$label.dump"
    local out="$work/$label.manifest"
    local class_name next field getter setter section
    : >"$out"
    while read -r class_name next field getter setter; do
        section="$work/$label.$class_name.section"
        extract_section "$dump" "$class_name" "$next" "$section"
        printf '%s ATTR=%s PROP=%s VAR=%s GETTER=%s SETTER=%s INIT=%s INIT_TY=%s TOSTRING=%s\n' \
            "$class_name" \
            "$(has_text OBJ_C_MIRROR "$section")" \
            "$(count_text "PropDecl: $field" "$section")" \
            "$(count_text "VarDecl: var $field" "$section")" \
            "$(count_text "FuncDecl: \$$getter" "$section")" \
            "$(count_text "FuncDecl: \$$setter" "$section")" \
            "$(count_text 'FuncDecl: init ' "$section")" \
            "$(has_text 'ty: (Struct-String) -> Class-NSStringMirror' "$section")" \
            "$(count_text 'FuncDecl: toString ' "$section")" >>"$out"
    done <<'EOF'
NSStringMirror NSObjectMirror stringField stringFieldget stringFieldset
NSObjectMirror PlainMirror objectField objectFieldget objectFieldset
PlainMirror Unrelated plainField plainFieldget plainFieldset
Unrelated "" untouchedField untouchedFieldget untouchedFieldset
EOF
}

make_manifest official
make_manifest candidate

echo "PREREQUISITE=ffin0:0719a1ee ObjC PrepareTypeCheck entry wiring"
if grep -q '^NSStringMirror ATTR=1 PROP=0 VAR=1 .* INIT=0 ' "$work/candidate.manifest" &&
    grep -q '^NSObjectMirror ATTR=1 PROP=0 VAR=1 ' "$work/candidate.manifest" &&
    grep -q '^PlainMirror ATTR=1 PROP=0 VAR=1 ' "$work/candidate.manifest"; then
    echo "PREREQUISITE_NOT_MET=ffin0:0719a1ee; candidate retained raw mirror fields and generated no N1b members"
fi

# Diagnostics precede the AST dump. Comparing the entire prefix checks quantity, text, locations,
# hints, kind, and order rather than accepting a summary-only match.
awk '/^Package: / { exit } { print }' "$work/official.dump" >"$work/official.diag"
awk '/^Package: / { exit } { print }' "$work/candidate.dump" >"$work/candidate.diag"

pass=0
fail=0
check_equal() {
    local name=$1
    local left=$2
    local right=$3
    if cmp -s "$left" "$right"; then
        echo "PASS $name"
        pass=$((pass + 1))
    else
        echo "FAIL $name"
        diff -u "$left" "$right" | sed -n '1,160p'
        fail=$((fail + 1))
    fi
}

official_rc=$(cat "$work/official.rc")
candidate_rc=$(cat "$work/candidate.rc")
if [ "$official_rc" = 1 ] && [ "$candidate_rc" = 1 ]; then
    echo "PASS expected diagnostic frontier rc=1/1"
    pass=$((pass + 1))
else
    echo "FAIL expected diagnostic frontier official=$official_rc candidate=$candidate_rc"
    fail=$((fail + 1))
fi

check_equal "official AST manifest matches N1b branch golden" \
    "$fixtures/expected_manifest.txt" "$work/official.manifest"
check_equal "candidate AST manifest matches official" "$work/official.manifest" "$work/candidate.manifest"
check_equal "diagnostics exact (quantity/kind/text/location/order)" "$work/official.diag" "$work/candidate.diag"

echo "OFFICIAL_MANIFEST_SHA256=$(sha256sum "$work/official.manifest" | awk '{print $1}')"
echo "CANDIDATE_MANIFEST_SHA256=$(sha256sum "$work/candidate.manifest" | awk '{print $1}')"
echo "OFFICIAL_DIAG_SHA256=$(sha256sum "$work/official.diag" | awk '{print $1}')"
echo "CANDIDATE_DIAG_SHA256=$(sha256sum "$work/candidate.diag" | awk '{print $1}')"
echo "OBJC_INTEROP_GATE PASS=$pass FAIL=$fail"
echo "GATE_STRENGTH=stub front-end compile/diagnostic/AST parity; no ObjC runtime glue or macOS end-to-end validation"

if [ "$fail" -ne 0 ]; then exit 1; fi
