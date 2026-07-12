#!/usr/bin/env bash
# Minimal repro corpus manager. Stored cases carry their source and expected compiler result.
set -euo pipefail
ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
REPORTS_ROOT="${REPORTS_ROOT:-/root/cj_build/reports}"
CORPUS="${REPROBANK_DIR:-/root/cj_build/tests/repros}"

usage() {
    cat >&2 <<'EOF'
usage:
  reprobank.sh collect <family> <PASS|COMPILE-ERROR> <root-cause> <reports-source.cj> [...]
  reprobank.sh collect-existing
  reprobank.sh run <path-to-cjc>
EOF
    exit 2
}

collect() {
    local family="$1" expected="$2" cause="$3"; shift 3
    [[ "$expected" == PASS || "$expected" == COMPILE-ERROR ]] || usage
    [[ $# -gt 0 ]] || usage
    mkdir -p "$CORPUS"
    local source base dest date
    date="$(date -u +%Y%m%d)"
    for source in "$@"; do
        [[ -f "$source" ]] || { echo "missing repro: $source" >&2; return 1; }
        base="$(basename "$source" .cj)"
        dest="$CORPUS/${family}_${date}_${base}.cj"
        {
            echo "// reprobank-source: $source"
            echo "// reprobank-source-lane: $family"
            echo "// reprobank-root-cause: $cause"
            echo "// reprobank-expected: $expected"
            cat "$source"
        } >"$dest"
        echo "COLLECTED $dest"
    done
}

run() {
    local cjc="$1"
    [[ -x "$cjc" ]] || { echo "compiler is not executable: $cjc" >&2; return 2; }
    [[ -d "$CORPUS" ]] || { echo "no corpus: $CORPUS" >&2; return 2; }
    export CANGJIE_HOME="${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}"
    export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    local case_file expected log out rc total=0 pass=0 fail=0
    while IFS= read -r -d '' case_file; do
        expected="$(sed -n 's#^// reprobank-expected: ##p' "$case_file" | head -1)"
        [[ "$expected" == PASS || "$expected" == COMPILE-ERROR ]] || { echo "INVALID-METADATA $case_file"; ((fail+=1)); continue; }
        log="$(mktemp /tmp/reprobank.XXXXXX.log)"; out="$(mktemp /tmp/reprobank.XXXXXX.a)"
        set +e; "$cjc" --output-type=staticlib -o "$out" "$case_file" >"$log" 2>&1; rc=$?; set -e
        rm -f "$out"; ((total+=1))
        if { [[ "$expected" == PASS ]] && [[ $rc -eq 0 ]]; } || { [[ "$expected" == COMPILE-ERROR ]] && [[ $rc -ne 0 ]]; }; then
            echo "PASS expected=$expected file=$(basename "$case_file")"; ((pass+=1))
        else
            echo "FAIL expected=$expected exit=$rc file=$case_file"; sed -n '1,12p' "$log"; ((fail+=1))
        fi
        rm -f "$log"
    done < <(find "$CORPUS" -maxdepth 1 -type f -name '*.cj' -print0 | sort -z)
    echo "TOTAL=$total PASS=$pass FAIL=$fail"
    [[ $fail -eq 0 ]]
}

[[ $# -ge 1 ]] || usage
case "$1" in
    collect) [[ $# -ge 5 ]] || usage; shift; collect "$@" ;;
    collect-existing) rg --files "$REPORTS_ROOT" -g '*.cj' | sort ;;
    run) [[ $# -eq 2 ]] || usage; run "$2" ;;
    *) usage ;;
esac
