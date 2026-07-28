#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
    echo "usage: $0 <candidate-cjc> <official-cjc> <cpus> <evidence-dir> [outer-jobs]" >&2
    exit 2
fi

candidate=$(realpath "$1")
official=$(realpath "$2")
cpus=$3
evidence=$(realpath -m "$4")
outer_jobs=${5:-8}
expected_functions=${APCDEFAULT_EXPECTED_FUNCTIONS:-2490}
repo=$(realpath "$(dirname "$0")/..")
llvm_dis=${CANGJIE_HOME:?CANGJIE_HOME must be set}/third_party/llvm/bin/llvm-dis

mkdir -p "$evidence"
wrappers=$(mktemp -d)
trap 'rm -rf "$wrappers"' EXIT

make_wrapper() {
    local output=$1
    local compiler=$2
    local jobs=$3
    local mode=$4
    {
        printf '#!/usr/bin/env bash\n'
        printf 'exec taskset -c %q %q "$@" --jobs %q' "$cpus" "$compiler" "$jobs"
        if [[ $mode == compat ]]; then
            printf ' --apc=1'
        fi
        printf '\n'
    } > "$output"
    chmod +x "$output"
}

run_bcgate() {
    local label=$1
    local self_wrapper=$2
    local base_wrapper=$3
    local log=$evidence/$label.log
    (
        cd "$repo"
        taskset -c "$cpus" python3 scripts/bcgate.py \
            --self "$self_wrapper" --base "$base_wrapper" -j "$outer_jobs"
    ) | tee "$log"
    local summary
    summary=$(grep '^shared functions:' "$log" | tail -n 1)
    local samples
    samples=$(grep '^fully-identical samples:' "$log" | tail -n 1)
    if [[ $summary != "shared functions: $expected_functions  |  byte-identical: $expected_functions (100.0%)  |  differing: 0" ||
          $samples != 'fully-identical samples: 114/114  |  compile-errors: 0' ]]; then
        echo "$label: FAIL: $summary; $samples" >&2
        exit 1
    fi
    echo "$label=$expected_functions/$expected_functions"
}

make_wrapper "$wrappers/candidate-default-j1" "$candidate" 1 default
for jobs in 1 2 24; do
    make_wrapper "$wrappers/candidate-default-j$jobs" "$candidate" "$jobs" default
    run_bcgate "GATE_A_J$jobs" "$wrappers/candidate-default-j$jobs" "$wrappers/candidate-default-j1"
done

for jobs in 1 2 24; do
    make_wrapper "$wrappers/candidate-compat-j$jobs" "$candidate" "$jobs" compat
    make_wrapper "$wrappers/official-compat-j$jobs" "$official" "$jobs" compat
    run_bcgate "GATE_B_J$jobs" "$wrappers/candidate-compat-j$jobs" "$wrappers/official-compat-j$jobs"
done

source_file=$repo/scripts/difftest_corpus/01_return.cj
for jobs in 1 2 24; do
    output=$evidence/gate-c-j$jobs
    rm -rf "$output"
    mkdir -p "$output"
    taskset -c "$cpus" "$candidate" "$source_file" --jobs "$jobs" \
        --save-temps "$output" -o "$output/a" > "$output/stdout.txt" 2> "$output/stderr.txt"
    for bitcode in "$output"/*.bc; do
        "$llvm_dis" "$bitcode" -o "$bitcode.ll"
    done
    if ! grep -Eq 'call (void @_CGPatifHv|.*void \(\)\* @_CGPatifHv)' "$output"/*.ll; then
        echo "GATE_C_J$jobs=missing-call" >&2
        exit 1
    fi
    echo "GATE_C_J$jobs=call-present"
    rm -f "$output/a" "$output"/*.o "$output"/*.s "$output"/*.bc "$output"/*.cjo "$output"/*.chir
    rm -rf "$output/.cached"
done

echo "APCDEFAULT_GATE=PASS"
