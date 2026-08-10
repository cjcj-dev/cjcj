#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$ROOT/.." && pwd)
OFFICIAL_TC=${OFFICIAL_TC:-${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458}}
SELFHOST_TC=${SELFHOST_TC:-$OFFICIAL_TC}
OFFICIAL_CJC=${OFFICIAL_CJC:-$OFFICIAL_TC/bin/cjc}
SELFHOST_CJC=${SELFHOST_CJC:-$REPO/target/release/bin/cjcj::cjc}
JOBS=${JOBS:-4}
CJC_JOBS=${CJC_JOBS:-1}

toolchain_ld_path() {
    local tc=$1
    printf '%s' "$tc/third_party/llvm/lib:$tc/runtime/lib/linux_x86_64_cjnative:$tc/tools/lib:${LD_LIBRARY_PATH:-}"
}

run_binary() {
    local binary=$1 out=$2 exits=$3
    set +e
    timeout 30 "$binary" >>"$out" 2>/dev/null
    local rc=$?
    set -e
    printf '%s\n' "$rc" >>"$exits"
}

compile_libs() {
    local cjc=$1 case_dir=$2 work=$3
    shift 3
    local archives=() lib
    for lib in "$@"; do
        timeout 180 "$cjc" -j "$CJC_JOBS" --output-type=staticlib --import-path "$work/build" \
            "$case_dir/libs/$lib"/*.cj "${archives[@]}" -o "$work/build/$lib.a" \
            >>"$work/compile.log" 2>&1
        archives+=("$work/build/$lib.a")
    done
    printf '%s\0' "${archives[@]}" >"$work/archives.list"
}

run_recipe() {
    local cjc=$1 tc=$2 case_dir=$3 work=$4
    # Declared before the source so a value cannot carry over between cases.
    # ORIGIN is set by every cases/*/case.conf to record the upstream test it
    # came from and is read by nothing here, which is what SC2034 sees; scoping
    # it is still the point, so the check is silenced rather than the variable
    # dropped.
    # shellcheck disable=SC2034
    local KIND='' LIBS='' ORIGIN=''
    # shellcheck disable=SC1090
    source "$case_dir/case.conf"
    mkdir -p "$work/build"
    : >"$work/compile.log"
    : >"$work/out.bin"
    : >"$work/exits.txt"
    cd "$work"
    case "$KIND" in
        import)
            # shellcheck disable=SC2086
            compile_libs "$cjc" "$case_dir" "$work" $LIBS
            local archives=()
            while IFS= read -r -d '' item; do archives+=("$item"); done <"$work/archives.list"
            local link_archives=() i
            for ((i=${#archives[@]}-1; i>=0; i--)); do link_archives+=("${archives[$i]}"); done
            timeout 180 "$cjc" -j "$CJC_JOBS" --import-path "$work/build" "$case_dir/main.cj" \
                "${link_archives[@]}" -o "$work/main" --set-runtime-rpath >>"$work/compile.log" 2>&1
            run_binary "$work/main" "$work/out.bin" "$work/exits.txt"
            ;;
        macro-import)
            timeout 180 "$cjc" -j "$CJC_JOBS" --compile-macro "$case_dir/macro"/*.cj \
                >>"$work/compile.log" 2>&1
            # shellcheck disable=SC2086
            compile_libs "$cjc" "$case_dir" "$work" $LIBS
            local macro_archives=()
            while IFS= read -r -d '' item; do macro_archives+=("$item"); done <"$work/archives.list"
            local macro_link_archives=() j
            for ((j=${#macro_archives[@]}-1; j>=0; j--)); do macro_link_archives+=("${macro_archives[$j]}"); done
            env LD_LIBRARY_PATH="$work:$(toolchain_ld_path "$tc")" timeout 180 "$cjc" -j "$CJC_JOBS" \
                --import-path "$work" --import-path "$work/build" "$case_dir/main.cj" "${macro_link_archives[@]}" \
                -o "$work/main" --set-runtime-rpath >>"$work/compile.log" 2>&1
            run_binary "$work/main" "$work/out.bin" "$work/exits.txt"
            ;;
        incremental-build)
            mkdir -p "$work/src"
            cp "$case_dir/old"/*.cj "$work/src/"
            timeout 180 "$cjc" -j "$CJC_JOBS" --incremental-compile --experimental --output-type=staticlib \
                "$work/src"/*.cj -o "$work/build/incremental.a" >>"$work/compile.log" 2>&1
            timeout 180 "$cjc" -j "$CJC_JOBS" --output-type=staticlib "$work/src"/*.cj \
                -o "$work/build/run.a" >>"$work/compile.log" 2>&1
            timeout 180 "$cjc" -j "$CJC_JOBS" --import-path "$work/build" "$case_dir/main.cj" \
                "$work/build/run.a" -o "$work/main" --set-runtime-rpath >>"$work/compile.log" 2>&1
            run_binary "$work/main" "$work/out.bin" "$work/exits.txt"
            cp "$case_dir/new"/*.cj "$work/src/"
            timeout 180 "$cjc" -j "$CJC_JOBS" --incremental-compile --experimental --output-type=staticlib \
                "$work/src"/*.cj -o "$work/build/incremental.a" >>"$work/compile.log" 2>&1
            timeout 180 "$cjc" -j "$CJC_JOBS" --output-type=staticlib "$work/src"/*.cj \
                -o "$work/build/run.a" >>"$work/compile.log" 2>&1
            timeout 180 "$cjc" -j "$CJC_JOBS" --import-path "$work/build" "$case_dir/main.cj" \
                "$work/build/run.a" -o "$work/main" --set-runtime-rpath >>"$work/compile.log" 2>&1
            run_binary "$work/main" "$work/out.bin" "$work/exits.txt"
            ;;
        *)
            printf 'unknown KIND=%s\n' "$KIND" >&2
            return 2
            ;;
    esac
}

run_one() {
    local case_dir=$1 name work off_rc self_rc status detail
    name=$(basename "$case_dir")
    work=$(mktemp -d)
    mkdir -p "$work/official" "$work/selfhost"
    env CANGJIE_HOME="$OFFICIAL_TC" LD_LIBRARY_PATH="$(toolchain_ld_path "$OFFICIAL_TC")" \
        cjHeapSize=32GB bash -c 'set -e; run_recipe "$1" "$2" "$3" "$4"' \
        _ "$OFFICIAL_CJC" "$OFFICIAL_TC" "$case_dir" "$work/official"
    off_rc=$?
    env CANGJIE_HOME="$SELFHOST_TC" LD_LIBRARY_PATH="$(toolchain_ld_path "$SELFHOST_TC")" \
        cjHeapSize=32GB bash -c 'set -e; run_recipe "$1" "$2" "$3" "$4"' \
        _ "$SELFHOST_CJC" "$SELFHOST_TC" "$case_dir" "$work/selfhost"
    self_rc=$?
    if [[ $off_rc -eq 0 && $self_rc -eq 0 ]] && \
       cmp -s "$work/official/out.bin" "$work/selfhost/out.bin" && \
       cmp -s "$work/official/exits.txt" "$work/selfhost/exits.txt"; then
        status=PASS
        detail="bytes=$(wc -c <"$work/official/out.bin") exits=$(tr '\n' ',' <"$work/official/exits.txt" | sed 's/,$//')"
    elif [[ $off_rc -ne 0 || $self_rc -ne 0 ]]; then
        status=FAIL
        detail="compile official=$off_rc selfhost=$self_rc"
    else
        status=MISMATCH
        detail="runtime-output-or-exit"
    fi
    printf '%s\t%s\t%s\n' "$status" "$name" "$detail"
    rm -rf "$work"
}

export ROOT REPO OFFICIAL_TC SELFHOST_TC OFFICIAL_CJC SELFHOST_CJC CJC_JOBS
export -f toolchain_ld_path run_binary compile_libs run_recipe run_one
results=$(mktemp)
trap 'rm -f "$results"' EXIT
find "$ROOT/cases" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z \
    | xargs -0 -P "$JOBS" -I{} bash -c 'run_one "$1"' _ {} >"$results"
sort -k2,2 "$results"
pass=$(awk -F'\t' '$1 == "PASS" {n++} END {print n+0}' "$results")
mismatch=$(awk -F'\t' '$1 == "MISMATCH" {n++} END {print n+0}' "$results")
fail=$(awk -F'\t' '$1 == "FAIL" {n++} END {print n+0}' "$results")
printf 'TOTAL=%s PASS=%s MISMATCH=%s FAIL=%s\n' "$((pass+mismatch+fail))" "$pass" "$mismatch" "$fail"
test "$mismatch" -eq 0 -a "$fail" -eq 0
