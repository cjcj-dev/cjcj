#!/usr/bin/env bash

# Run the source-build portion of .github/workflows/srcbuild.yml on kkk2.
# The step numbers intentionally match the GitHub Actions UI: step 1 is the
# implicit "Set up job", so the first repository step is step 2.

set -Eeuo pipefail

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly SCRIPT_PATH
REPO_ROOT=$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd -P)
readonly REPO_ROOT
readonly HOST_TOOLCHAIN_PIN="$REPO_ROOT/ci/host_sdk_pin.env"
# Numeric GHA ids kept for --from-step/--through-step. Deleted ids 15-19 and
# 27-28 are not in this order: bootstrap (31+32) and final-std (33) run after
# P07/step 14, then stdx/tools/package, then shim/inject.
DAG_ORDER=(2 3 4 5 6 7 8 9 10 11 12 13 14 31 32 33 20 21 22 23 24 25 26 29 30)
readonly ORIGINAL_ARGS=("$@")

read_host_toolchain_pin() {
    local line key value toolchain= seen_toolchain=0
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -z $line ]] && continue
        [[ $line =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || {
            echo "unsupported host toolchain pin record: $line" >&2
            return 1
        }
        key=${line%%=*}
        value=${line#*=}
        if [[ $key == CJCJ_TOOLCHAIN ]]; then
            [[ $seen_toolchain == 0 ]] || {
                echo "CJCJ_TOOLCHAIN is duplicated in $HOST_TOOLCHAIN_PIN" >&2
                return 1
            }
            seen_toolchain=1
            toolchain=$value
        fi
    done < "$HOST_TOOLCHAIN_PIN"
    [[ -n $toolchain ]] || {
        echo "CJCJ_TOOLCHAIN is missing from $HOST_TOOLCHAIN_PIN" >&2
        return 1
    }
    printf '%s\n' "$toolchain"
}

resolve_host_toolchain_pin() {
    local pinned_toolchain
    pinned_toolchain=$(read_host_toolchain_pin) || return
    CJCJ_TOOLCHAIN=$pinned_toolchain
    export CJCJ_TOOLCHAIN
}

dag_contains() {
    local want=$1 s
    for s in "${DAG_ORDER[@]}"; do
        [[ $s == "$want" ]] && return 0
    done
    return 1
}

validate_dag_range() {
    local from=$1 through=$2 s seen_from=0
    dag_contains "$from" || {
        echo "from-step $from is not in DAG (removed 15-19 and 27-28; bootstrap is 31-32 after 14)" >&2
        return 2
    }
    dag_contains "$through" || {
        echo "through-step $through is not in DAG (removed 15-19 and 27-28; bootstrap is 31-32 after 14)" >&2
        return 2
    }
    for s in "${DAG_ORDER[@]}"; do
        if ((s == from)); then seen_from=1; fi
        if ((s == through)); then
            ((seen_from)) || {
                echo "through-step $through precedes from-step $from in DAG order" >&2
                return 2
            }
            return 0
        fi
    done
    return 2
}

selected_dag_steps() {
    local from=$1 through=$2 s started=0
    for s in "${DAG_ORDER[@]}"; do
        if ((s == from)); then started=1; fi
        if ((started)); then printf '%s\n' "$s"; fi
        if ((s == through)); then break; fi
    done
}

current_cpuset() {
    local affinity
    affinity=$(LC_ALL=C taskset -pc "$$") || return 1
    affinity=${affinity##*: }
    [[ -n $affinity ]] || {
        echo "taskset returned an empty CPU affinity" >&2
        return 1
    }
    printf '%s\n' "$affinity"
}

cpuset_width() {
    local cpuset=$1
    awk -v cpuset="$cpuset" '
        BEGIN {
            n = split(cpuset, groups, ",")
            width = 0
            for (i = 1; i <= n; i++) {
                if (groups[i] ~ /^[0-9]+$/) {
                    width++
                } else if (groups[i] ~ /^[0-9]+-[0-9]+$/) {
                    split(groups[i], bounds, "-")
                    if (bounds[2] < bounds[1]) exit 1
                    width += bounds[2] - bounds[1] + 1
                } else {
                    exit 1
                }
            }
            if (width < 1) exit 1
            print width
        }
    '
}

explicit_cpuset() {
    local requested=$1 first last
    [[ $requested =~ ^[0-9]+-[0-9]+$ ]] || {
        echo "CJCJ_SRCBUILD_CPUSET must be one contiguous range such as 96-159" >&2
        return 1
    }
    first=${requested%-*}
    last=${requested#*-}
    ((10#$first <= 10#$last)) || {
        echo "CJCJ_SRCBUILD_CPUSET has a descending range: $requested" >&2
        return 1
    }
    printf '%d-%d\n' "$((10#$first))" "$((10#$last))"
}

apply_source_mirror_profile() {
    local profile=$1
    if [[ $profile == kkk2 ]]; then
        : "${CJCJ_SRCBUILD_REQUIRE_MIRRORS:=1}"
        export CJCJ_SRCBUILD_REQUIRE_MIRRORS
    fi
}

# Step 8 compiler-cache setup.  sccache wins when it is on PATH; otherwise a
# ccache installation enables the CMAKE_*_COMPILER_LAUNCHER variables with a
# dedicated cache directory (never the shared /root/.ccache).  CCACHE_BASEDIR
# rewrites source/include argv paths to workspace-relative keys so independent
# per-run workspaces can share entries.  The C/C++ stages also receive
# -ffile-prefix-map via build/srcbuild/stages/common.mjs; this keeps the
# compiler's __FILE__ and DWARF paths identical after ccache rewrites argv.
# build/cli.mjs (build/toolchain/sccache.mjs maybeEnable) leaves pre-set
# launcher variables untouched, so these records flow through GITHUB_ENV
# into the compiler/runtime configure steps unchanged.
# Defined in the --lib-only section so tests can exercise the branch decisions
# without entering the kkk2 driver.  Opt out with CJCJ_SRCBUILD_CCACHE=0.
srcbuild_setup_compiler_cache() {
    if command -v sccache >/dev/null; then
        append_env SCCACHE_PATH "$(command -v sccache)"
        sccache --start-server
        sccache --zero-stats
        return 0
    fi
    if [[ ${CJCJ_SRCBUILD_CCACHE:-1} == 0 ]]; then
        local basedir=${CANGJIE_WORKSPACE:-$REPO_ROOT}
        local canon=$REPO_ROOT/tools/srcbuild_pathcanon.sh
        export CCACHE_BASEDIR="$basedir"
        append_env CMAKE_C_COMPILER_LAUNCHER "$canon"
        append_env CMAKE_CXX_COMPILER_LAUNCHER "$canon"
        append_env CCACHE_BASEDIR "$basedir"
        echo "CJCJ_SRCBUILD_CCACHE=0; CMAKE compiler launcher is pathcanon basedir=$basedir"
        return 0
    fi
    if ! command -v ccache >/dev/null; then
        echo "sccache is absent; build/cli.mjs will leave compiler launchers unset"
        return 0
    fi
    local dir=${CJCJ_SRCBUILD_CCACHE_DIR:-${SRCBUILD_USER_HOME:-${HOME:-/root}}/.cache/cjcj-srcbuild/ccache}
    local basedir=${CANGJIE_WORKSPACE:-$REPO_ROOT}
    mkdir -p "$dir"
    export CCACHE_DIR="$dir"
    export CCACHE_BASEDIR="$basedir"
    export CCACHE_NOHASHDIR=true
    export CCACHE_SLOPPINESS=pch_defines,include_file_mtime,locale
    append_env CMAKE_C_COMPILER_LAUNCHER ccache
    append_env CMAKE_CXX_COMPILER_LAUNCHER ccache
    append_env CCACHE_DIR "$dir"
    append_env CCACHE_BASEDIR "$basedir"
    append_env CCACHE_NOHASHDIR true
    append_env CCACHE_SLOPPINESS pch_defines,include_file_mtime,locale
    CCACHE_DIR="$dir" ccache -M "${CJCJ_SRCBUILD_CCACHE_SIZE:-60G}" >/dev/null
    CCACHE_DIR="$dir" ccache -z >/dev/null
    echo "ccache enabled as CMAKE compiler launcher: dir=$dir max_size=${CJCJ_SRCBUILD_CCACHE_SIZE:-60G} basedir=$basedir"
}

validate_verifier_report_request() {
    local report=$1 from_step=$2 through_step=$3
    [[ -z $report ]] && return 0
    [[ $report == /* ]] || {
        echo "verifier report path must be absolute: $report" >&2
        return 2
    }
    echo "verifier report mode targeted removed stdlib step 19; stdlib is produced by bootstrap after step 14" >&2
    return 2
}

sanitize_verifier_environment() {
    unset CJCJ_SRCBUILD_VERIFIER_REPORT_ACTIVE CJ_IR_VERIFIER_REPORT
    export CJ_IR_VERIFIER_MODE=strict
}

reject_diagnostic_workspace() {
    local marker=$1 context=${2:-source-build}
    [[ ! -e $marker ]] && return 0
    echo "refusing $context in workspace marked diagnostic: $marker" >&2
    return 5
}

if [[ ${1:-} == --lib-only ]]; then
    [[ $# == 1 ]] || {
        echo "--lib-only does not accept other arguments" >&2
        return 2 2>/dev/null || exit 2
    }
    return 0 2>/dev/null || exit 0
fi

# shellcheck disable=SC1091
source "$REPO_ROOT/build/lib/srcbuild_git.sh"

usage() {
    cat <<'EOF'
Usage: tools/srcbuild_kkk2.sh [TARGET [JOBS [FROM_STEP]]]
       tools/srcbuild_kkk2.sh [--target TARGET] [--jobs N]
                              [--from-step N] [--through-step N]
                              [--verifier-report ABSOLUTE_TSV] [--dry-run]
       source tools/srcbuild_kkk2.sh --lib-only

Defaults:
  TARGET=linux-x64  JOBS=<selected CPU window width>
  FROM_STEP=2  THROUGH_STEP=33
  DAG after verify-source-pins: bootstrap stage0/stage1, final-std, then stdx/tools/package.

CPU placement:
  CJCJ_SRCBUILD_CPUSET=96-159 selects an explicit contiguous 64-core window.
  When it is unset, the driver inherits its caller's current taskset affinity.
  JOBS always equals the selected window width unless given explicitly, so
  claiming a wider window is how compile parallelism is raised.

Compiler cache:
  Step 8 uses sccache when present, else falls back to ccache with a dedicated
  CCACHE_DIR (default ~/.cache/cjcj-srcbuild/ccache, override with
  CJCJ_SRCBUILD_CCACHE_DIR; size with CJCJ_SRCBUILD_CCACHE_SIZE, default 60G).
  CJCJ_SRCBUILD_CCACHE=0 disables the ccache fallback.

Final source-build steps:
  32  Build stage 2 compiler (cjpm build -j 1, cjHeapSize=20GB)
  33  Build stage 3 compiler and final std

--dry-run validates referenced step scripts and their command contracts, then
prints the selected commands and environment without executing them.

--verifier-report is rejected: the old stdlib step 19 is no longer in the DAG.

--lib-only is source-only and defines the strict host pin reader/resolver
without entering the kkk2 build driver.

The script must run on kkk2.  Invoke it through the shared box entry point,
for example:
  tools/box.sh kkk2 'cd /path/to/cjcj && tools/srcbuild_kkk2.sh'

Step numbers are the GitHub Actions UI numbers from srcbuild.yml.  State and
logs are retained under .srcbuild, so a failed step can be retried with
--from-step without repeating its successful predecessors.
EOF
}

TARGET=linux-x64
JOBS=
JOBS_EXPLICIT=0
FROM_STEP=2
THROUGH_STEP=33
DRY_RUN=0
VERIFIER_REPORT=${CJCJ_SRCBUILD_VERIFIER_REPORT:-}

positional=()
while (($#)); do
    case "$1" in
        --target)
            [[ $# -ge 2 ]] || { echo "--target requires a value" >&2; exit 2; }
            TARGET=$2
            shift 2
            ;;
        --jobs|-j)
            [[ $# -ge 2 ]] || { echo "$1 requires a value" >&2; exit 2; }
            JOBS=$2
            JOBS_EXPLICIT=1
            shift 2
            ;;
        --from-step)
            [[ $# -ge 2 ]] || { echo "--from-step requires a value" >&2; exit 2; }
            FROM_STEP=$2
            shift 2
            ;;
        --through-step)
            [[ $# -ge 2 ]] || { echo "--through-step requires a value" >&2; exit 2; }
            THROUGH_STEP=$2
            shift 2
            ;;
        --verifier-report)
            [[ $# -ge 2 ]] || { echo "--verifier-report requires a value" >&2; exit 2; }
            if [[ -n $VERIFIER_REPORT && $VERIFIER_REPORT != "$2" ]]; then
                echo "--verifier-report disagrees with CJCJ_SRCBUILD_VERIFIER_REPORT" >&2
                exit 2
            fi
            VERIFIER_REPORT=$2
            shift 2
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            positional+=("$@")
            break
            ;;
        -*)
            echo "unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
        *)
            positional+=("$1")
            shift
            ;;
    esac
done

if ((${#positional[@]} > 3)); then
    echo "expected at most three positional arguments" >&2
    exit 2
fi
if ((${#positional[@]} >= 1)); then TARGET=${positional[0]}; fi
if ((${#positional[@]} >= 2)); then
    JOBS=${positional[1]}
    JOBS_EXPLICIT=1
fi
if ((${#positional[@]} >= 3)); then FROM_STEP=${positional[2]}; fi

inherited_cpuset=$(current_cpuset) || exit 2
if [[ -n ${CJCJ_SRCBUILD_CPUSET:-} ]]; then
    CPUSET=$(explicit_cpuset "$CJCJ_SRCBUILD_CPUSET") || exit 2
else
    CPUSET=$inherited_cpuset
fi
CPUSET_WIDTH=$(cpuset_width "$CPUSET") || {
    echo "cannot determine CPU count from affinity '$CPUSET'" >&2
    exit 2
}
if ((JOBS_EXPLICIT == 0)); then JOBS=$CPUSET_WIDTH; fi

[[ $TARGET == linux-x64 ]] || {
    echo "kkk2 is Linux/x86_64; srcbuild target '$TARGET' requires its matching native runner" >&2
    exit 2
}
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || { echo "jobs must be a positive integer" >&2; exit 2; }
((JOBS <= CPUSET_WIDTH)) || {
    echo "jobs ($JOBS) must not exceed selected CPU window width ($CPUSET_WIDTH for $CPUSET)" >&2
    exit 2
}
[[ $FROM_STEP =~ ^[0-9]+$ ]] || { echo "from-step must be an integer" >&2; exit 2; }
[[ $THROUGH_STEP =~ ^[0-9]+$ ]] || { echo "through-step must be an integer" >&2; exit 2; }
((FROM_STEP >= 1 && FROM_STEP <= 33)) || { echo "from-step must be in 1..33" >&2; exit 2; }
((THROUGH_STEP >= 2 && THROUGH_STEP <= 33)) || { echo "through-step must be in 2..33" >&2; exit 2; }
((FROM_STEP <= THROUGH_STEP)) || { echo "from-step must not exceed through-step" >&2; exit 2; }
if ((FROM_STEP == 1)); then FROM_STEP=2; fi
validate_dag_range "$FROM_STEP" "$THROUGH_STEP" || exit $?
validate_verifier_report_request "$VERIFIER_REPORT" "$FROM_STEP" "$THROUGH_STEP" || exit $?

host_name=$(hostname -s)
[[ $host_name == kkk2 ]] || {
    echo "refusing build load on host '$host_name': run this script on kkk2 via tools/box.sh" >&2
    exit 3
}
apply_source_mirror_profile "$host_name"

if [[ ${CJCJ_KKK2_AFFINED:-} != "$CPUSET" ]]; then
    exec taskset -c "$CPUSET" env CJCJ_KKK2_AFFINED="$CPUSET" \
        bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
fi
actual_cpuset=$(current_cpuset) || exit 3
[[ $actual_cpuset == "$CPUSET" ]] || {
    echo "taskset affinity mismatch: requested=$CPUSET actual=$actual_cpuset" >&2
    exit 3
}

# The request has now survived the affinity self-restart.  From this point the
# public and LLVM variables are sanitized; bootstrap no longer sets a private
# verifier-report child environment.
unset CJCJ_SRCBUILD_VERIFIER_REPORT
sanitize_verifier_environment

readonly STATE_ROOT="$REPO_ROOT/.srcbuild"
readonly LOG_ROOT="$STATE_ROOT/logs"
readonly RUNNER_TEMP="$STATE_ROOT/tmp"
readonly GITHUB_ENV="$STATE_ROOT/kkk2-github.env"
readonly GITHUB_PATH="$STATE_ROOT/kkk2-github.path"
readonly TIMINGS="$STATE_ROOT/kkk2-timings.tsv"
readonly SIGNATURE="$STATE_ROOT/kkk2-crash-signature.txt"
readonly PRIVATE_HOME="$STATE_ROOT/home"
readonly CANGJIE_WORKSPACE="$STATE_ROOT/workspace"
readonly CANGJIE_BUILD_ROOT="$STATE_ROOT/buildtools"
readonly CJCJ_FIXED_LLVM_DIR="$STATE_ROOT/fixed-llc"
readonly STAGE1_STEP_SCRIPT="$REPO_ROOT/ci/srcbuild/steps/build-stage1.mjs"
readonly STAGE2_STEP_SCRIPT="$REPO_ROOT/ci/srcbuild/steps/build-stage2.mjs"
readonly STAGE3_STEP_SCRIPT="$REPO_ROOT/ci/srcbuild/steps/build-stage3.mjs"
readonly STAGE2_PRODUCT_DIR="$REPO_ROOT/target/release/bin"
readonly BUILD_TYPE=relwithdebinfo
readonly VERIFIER_DIAGNOSTIC_MARKER="$CANGJIE_WORKSPACE/.cjcj-verifier-diagnostic.json"
readonly VERIFIER_INVENTORY="${VERIFIER_REPORT:+${VERIFIER_REPORT}.artifacts.tsv}"
START_STAMP=$(date -u +%Y%m%dT%H%M%SZ)
readonly START_STAMP
readonly BASE_PATH="$PRIVATE_HOME/.local/bin:$PATH"

if ((DRY_RUN == 0)); then
    mkdir -p "$LOG_ROOT" "$RUNNER_TEMP" "$PRIVATE_HOME" "$CANGJIE_WORKSPACE" \
        "$CANGJIE_BUILD_ROOT" "$CJCJ_FIXED_LLVM_DIR"
fi

reject_diagnostic_workspace "$VERIFIER_DIAGNOSTIC_MARKER" source-build || exit $?

    readonly SRCBUILD_USER_HOME="${HOME:-/root}"
    export HOME="$PRIVATE_HOME"
export GITHUB_WORKSPACE="$REPO_ROOT"
export GITHUB_ENV GITHUB_PATH RUNNER_TEMP
export CANGJIE_WORKSPACE CANGJIE_BUILD_ROOT CJCJ_FIXED_LLVM_DIR
export CJCJ_SRCBUILD_TARGET="$TARGET"
export SCCACHE_GHA_ENABLED=false
export SCCACHE_LOG=warn
export cjHeapSize=12GB
export cjHeapSwap=on
export CJCJ_STAGE3_STDLIB_BUILD_TYPE="$BUILD_TYPE"
export CMAKE_BUILD_PARALLEL_LEVEL="$JOBS"
export MAKEFLAGS="-j$JOBS"
export CARGO_BUILD_JOBS="$JOBS"
export PATH="$BASE_PATH"

if ((DRY_RUN)); then
    :
elif ((FROM_STEP == 2)); then
    : > "$GITHUB_ENV"
    : > "$GITHUB_PATH"
    printf 'kind\tstep\tname\trc\twall_s\tlog\n' > "$TIMINGS"
    : > "$SIGNATURE"
else
    [[ -f $GITHUB_ENV && -f $GITHUB_PATH ]] || {
        echo "no retained GitHub environment; restart with --from-step 2" >&2
        exit 4
    }
    [[ -f $TIMINGS ]] || printf 'kind\tstep\tname\trc\twall_s\tlog\n' > "$TIMINGS"
fi

append_env() {
    local key=$1 value=$2
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_ENV"
}

load_github_state() {
    local line key value path_prefix=
    export PATH="$BASE_PATH"
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -z $line ]] && continue
        [[ $line =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || {
            echo "unsupported GITHUB_ENV record: $line" >&2
            return 1
        }
        key=${line%%=*}
        value=${line#*=}
        printf -v "$key" '%s' "$value"
        export "${key?}"
    done < "$GITHUB_ENV"
    while IFS= read -r line || [[ -n $line ]]; do
        [[ -z $line ]] && continue
        if [[ -z $path_prefix ]]; then path_prefix=$line; else path_prefix="$path_prefix:$line"; fi
    done < "$GITHUB_PATH"
    if [[ -n $path_prefix ]]; then export PATH="$path_prefix:$BASE_PATH"; fi
    sanitize_verifier_environment
}

elapsed_seconds() {
    local start_ns=$1 end_ns=$2
    awk -v start="$start_ns" -v end="$end_ns" 'BEGIN { printf "%.3f", (end-start)/1000000000 }'
}

last_field() {
    local field=$1 input=$2
    perl -ne 'BEGIN {$f=$ARGV[0]; shift @ARGV} while (/\b\Q$f\E=([^[:space:]]+)/g) {$v=$1} END {print defined($v) ? $v : "UNRESOLVED"}' \
        "$field" "$input"
}

record_crash_signature() {
    local log=$1
    local si_code si_addr pc_mod gc_phase
    si_code=$(last_field si_code "$log")
    si_addr=$(last_field si_addr "$log")
    pc_mod=$(last_field pc_mod "$log")
    gc_phase=$(last_field gc_phase "$log")
    printf 'si_code=%s si_addr=%s pc_mod=%s gc_phase=%s source=%s\n' \
        "$si_code" "$si_addr" "$pc_mod" "$gc_phase" "$log" > "$SIGNATURE"
    printf 'CRASH_SIGNATURE si_code=%s si_addr=%s pc_mod=%s gc_phase=%s\n' \
        "$si_code" "$si_addr" "$pc_mod" "$gc_phase"
}

capture_build_child_affinity() {
    local root_pid=$1 step=$2 stop_file=$3
    local candidate pid command elapsed preferred arguments affinity actual
    local best_pid= best_command= best_arguments= best_actual=
    local best_elapsed=-1 best_preferred=0
    while [[ ! -e $stop_file ]]; do
        candidate=$(LC_ALL=C ps -eo pid=,ppid=,etimes=,comm=,args= | awk -v root_pid="$root_pid" '
            {
                pid = $1
                parent[pid] = $2
                elapsed[pid] = $3
                command[pid] = $4
                $1 = $2 = $3 = $4 = ""
                sub(/^[[:space:]]+/, "")
                arguments[pid] = $0
            }
            function is_descendant(pid, ancestor, depth) {
                for (depth = 0; depth < 64 && pid in parent; depth++) {
                    pid = parent[pid]
                    if (pid == root_pid) return 1
                    if (pid <= 1) return 0
                }
                return 0
            }
            END {
                best_pid = 0
                best_elapsed = -1
                best_preferred = -1
                for (pid in parent) {
                    if ((command[pid] == "cmake" || command[pid] == "ninja" ||
                         command[pid] == "make" || command[pid] == "gmake") &&
                        is_descendant(pid)) {
                        preferred = ((command[pid] == "make" || command[pid] == "gmake") &&
                                     arguments[pid] ~ /(^|[[:space:]])DESTDIR=/)
                        if (preferred > best_preferred ||
                            (preferred == best_preferred && elapsed[pid] >= best_elapsed)) {
                            best_pid = pid
                            best_elapsed = elapsed[pid]
                            best_preferred = preferred
                        }
                    }
                }
                if (best_pid != 0) {
                    printf "%s\t%s\t%s\t%s\t%s\n", best_pid, command[best_pid],
                        elapsed[best_pid], best_preferred, arguments[best_pid]
                }
            }
        ') || return 1
        if [[ -n $candidate ]]; then
            IFS=$'\t' read -r pid command elapsed preferred arguments <<< "$candidate"
            affinity=$(LC_ALL=C taskset -pc "$pid" 2>/dev/null) || continue
            actual=${affinity##*: }
            if ((preferred > best_preferred ||
                (preferred == best_preferred && elapsed >= best_elapsed))); then
                best_pid=$pid
                best_command=$command
                best_elapsed=$elapsed
                best_preferred=$preferred
                best_actual=$actual
                best_arguments=$arguments
            fi
        fi
        sleep 0.02
    done
    if [[ -n $best_pid ]]; then
        printf 'affinity\tstep=%s\tpid=%s\tcommand=%s\trequested=%s\tactual=%s\targs=%s\n' \
            "$step" "$best_pid" "$best_command" "$CPUSET" "$best_actual" "$best_arguments" >> "$TIMINGS"
    fi
}

run_step() {
    local step=$1 name=$2 function_name=$3
    local log="$LOG_ROOT/${START_STAMP}-step${step}.log"
    local stop_file="$STATE_ROOT/.affinity-${START_STAMP}-step${step}-$$.stop"
    local start_ns end_ns wall rc monitor_pid
    start_ns=$(date +%s%N)
    capture_build_child_affinity "$$" "$step" "$stop_file" &
    monitor_pid=$!
    set +e
    "$function_name" > "$log" 2>&1
    rc=$?
    set -e
    : > "$stop_file"
    wait "$monitor_pid" || true
    end_ns=$(date +%s%N)
    wall=$(elapsed_seconds "$start_ns" "$end_ns")
    printf 'step\t%s\t%s\t%s\t%s\t%s\n' "$step" "$name" "$rc" "$wall" "$log" >> "$TIMINGS"
    printf 'STEP=%s name=%s rc=%s wall_s=%s log=%s\n' "$step" "$name" "$rc" "$wall" "$log"
    if ((rc != 0)); then
        if ((step == 31)); then record_crash_signature "$log"; fi
    else
        load_github_state
    fi
    if [[ -n ${CCACHE_DIR:-} ]] && command -v ccache >/dev/null; then
        {
            printf '[ccache -s after step %s]\n' "$step"
            CCACHE_DIR="$CCACHE_DIR" ccache -s
        } >> "$log" 2>&1
    fi
    if ((rc != 0)); then
        return "$rc"
    fi
}

fixed_tuple_is_current() {
    local tuple_dir=${1:-$CJCJ_FIXED_LLVM_DIR}
    local manifest="$tuple_dir/llvm-tools.manifest" manifest_llvm opt_llvm
    [[ -s $tuple_dir/llc.gz ]] || return 1
    [[ -s $tuple_dir/opt.gz ]] || return 1
    [[ -s $tuple_dir/cjselfhost_llvmshim.o ]] || return 1
    [[ -s $manifest ]] || return 1
    # shellcheck disable=SC1091
    source "$REPO_ROOT/ci/llvm_pin.env" || return 1
    [[ $(awk -F= '$1=="PLATFORM" {print $2}' "$manifest") == linux_x86_64 ]] || return 1
    manifest_llvm=$(awk -F= '$1=="LLVM_SHA" {print $2}' "$manifest") || return 1
    [[ $manifest_llvm == "$LLVM_SHA" ]] || return 1
    opt_llvm=$(gzip -dc "$tuple_dir/opt.gz" \
        | strings | sed -n 's/^CJLLVM-COMMIT:\([0-9a-f]\{40\}\)$/\1/p') || return 1
    [[ $opt_llvm == "$manifest_llvm" ]] || return 1
    [[ $(awk -F= '$1=="CANGJIE_COMPILER_SHA" {print $2}' "$manifest") == "$CANGJIE_COMPILER_SHA" ]] || return 1
    [[ $(awk -F= '$1=="FLATBUFFERS_SHA" {print $2}' "$manifest") == "$FLATBUFFERS_SHA" ]] || return 1
    node "$REPO_ROOT/ci/llvm-tools-manifest.mjs" validate native "$manifest" >/dev/null || return 1
}

resolve_depot_tuple_root() {
    local depot_root=${1:-${CJCJ_LLVM_DEPOT_ROOT:-/root/llvmdepot}}
    local nested="$depot_root/$LLVM_SHA/$CANGJIE_COMPILER_SHA"
    local legacy="$depot_root/$LLVM_SHA"
    local manifest_compiler
    if [[ -d $nested/fixed-llc && -s $nested/SHA256SUMS ]]; then
        printf '%s\n' "$nested"
        return 0
    fi
    if [[ -d $legacy/fixed-llc && -s $legacy/SHA256SUMS && -s $legacy/fixed-llc/llvm-tools.manifest ]]; then
        manifest_compiler=$(awk -F= '$1=="CANGJIE_COMPILER_SHA" {print $2}' "$legacy/fixed-llc/llvm-tools.manifest") || return 1
        if [[ $manifest_compiler == "$CANGJIE_COMPILER_SHA" ]]; then
            printf '%s\n' "$legacy"
            return 0
        fi
        echo "fixed LLVM depot legacy layout skipped: compiler sha $manifest_compiler != pin $CANGJIE_COMPILER_SHA at $legacy" >&2
    fi
    return 1
}

publish_fixed_tuple_to_depot() {
    local depot_root=${1:-${CJCJ_LLVM_DEPOT_ROOT:-/root/llvmdepot}}
    local depot="$depot_root/$LLVM_SHA/$CANGJIE_COMPILER_SHA"
    local tuple="$depot/fixed-llc"
    local payload
    local -a payloads=(llc.gz opt.gz cjselfhost_llvmshim.o llvm-tools.manifest)
    [[ -n ${LLVM_SHA:-} && -n ${CANGJIE_COMPILER_SHA:-} ]] || return 1
    mkdir -p "$tuple"
    for payload in "${payloads[@]}"; do
        cp -- "$CJCJ_FIXED_LLVM_DIR/$payload" "$tuple/$payload"
    done
    (
        cd "$depot" || exit 1
        sha256sum -- "./fixed-llc/llc.gz" "./fixed-llc/opt.gz" \
            "./fixed-llc/cjselfhost_llvmshim.o" "./fixed-llc/llvm-tools.manifest" > SHA256SUMS
    ) || return 1
    echo "published fixed LLVM tuple to depot $depot"
}

seed_fixed_tuple_from_depot() {
    local depot_root=${1:-${CJCJ_LLVM_DEPOT_ROOT:-/root/llvmdepot}}
    local depot tuple payload sums_sha
    local -a payloads=(llc.gz opt.gz cjselfhost_llvmshim.o llvm-tools.manifest)
    if [[ -z ${LLVM_SHA:-} ]]; then
        LLVM_SHA=$(awk -F= '$1=="LLVM_SHA" {print $2}' "$REPO_ROOT/ci/llvm_pin.env") || return 1
    fi
    if [[ -z ${CANGJIE_COMPILER_SHA:-} ]]; then
        CANGJIE_COMPILER_SHA=$(awk -F= '$1=="CANGJIE_COMPILER_SHA" {print $2}' "$REPO_ROOT/ci/llvm_pin.env") || return 1
    fi
    depot=$(resolve_depot_tuple_root "$depot_root") || {
        echo "fixed LLVM depot seed unavailable under $depot_root/$LLVM_SHA/{${CANGJIE_COMPILER_SHA},} (missing nested or matching-legacy fixed-llc); rebuilding" >&2
        return 1
    }
    tuple="$depot/fixed-llc"
    for payload in "${payloads[@]}"; do
        [[ -f $tuple/$payload && ! -L $tuple/$payload ]] || {
            echo "fixed LLVM depot seed rejected: missing or non-regular fixed-llc/$payload; rebuilding" >&2
            return 1
        }
    done
    [[ ${LLVM_TUPLE_SUMS_SHA:-} =~ ^[0-9a-f]{64}$ ]] || {
        echo "fixed LLVM depot seed rejected: LLVM_TUPLE_SUMS_SHA is missing or malformed; rebuilding" >&2
        return 1
    }
    sums_sha=$(sha256sum "$depot/SHA256SUMS" | awk '{print $1}') || return 1
    [[ $sums_sha == "$LLVM_TUPLE_SUMS_SHA" ]] || {
        echo "fixed LLVM depot seed rejected: SHA256SUMS digest disagrees with ci/llvm_pin.env at $depot; rebuilding" >&2
        return 1
    }
    if ! (cd "$depot" && sha256sum --strict -c SHA256SUMS); then
        echo "fixed LLVM depot seed rejected: SHA256SUMS verification failed at $depot; rebuilding" >&2
        return 1
    fi
    if ! fixed_tuple_is_current "$tuple"; then
        echo "fixed LLVM depot seed rejected: pin, manifest, and opt lineage disagree at $tuple; rebuilding" >&2
        return 1
    fi

    mkdir -p "$CJCJ_FIXED_LLVM_DIR"
    for payload in "${payloads[@]}"; do
        cp -- "$tuple/$payload" "$CJCJ_FIXED_LLVM_DIR/$payload"
    done
    if ! fixed_tuple_is_current; then
        echo "fixed LLVM depot seed rejected after copy; rebuilding" >&2
        return 1
    fi
    echo "seeded fixed LLVM tuple from verified depot $depot"
}

checkout_exact() {
    local directory=$1 url=$2 revision=$3
    if [[ ! -d $directory/.git ]]; then
        git init "$directory" || return 1
    fi
    if git -C "$directory" remote get-url origin >/dev/null 2>&1; then
        git -C "$directory" remote set-url origin "$url" || return 1
    else
        git -C "$directory" remote add origin "$url" || return 1
    fi
    srcbuild_git_fetch "$directory" "$url" "$revision" || return 1
    git -C "$directory" checkout --detach FETCH_HEAD || return 1
    [[ $(git -C "$directory" rev-parse HEAD) == "$revision" ]]
}

checkout_sparse_exact() {
    local directory=$1 url=$2 revision=$3 sparse_path=$4
    if [[ ! -d $directory/.git ]]; then
        git init "$directory" || return 1
    fi
    if git -C "$directory" remote get-url origin >/dev/null 2>&1; then
        git -C "$directory" remote set-url origin "$url" || return 1
    else
        git -C "$directory" remote add origin "$url" || return 1
    fi
    git -C "$directory" sparse-checkout init --cone || return 1
    git -C "$directory" sparse-checkout set "$sparse_path" || return 1
    srcbuild_git_fetch "$directory" "$url" "$revision" || return 1
    git -C "$directory" checkout --detach FETCH_HEAD || return 1
    [[ $(git -C "$directory" rev-parse HEAD) == "$revision" ]]
}

build_fixed_tuple() {
    if fixed_tuple_is_current; then
        echo "fixed LLVM tuple matches ci/llvm_pin.env; reusing it"
        return
    fi
    # shellcheck disable=SC1091
    source "$REPO_ROOT/ci/llvm_pin.env"
    if seed_fixed_tuple_from_depot; then
        return
    fi
    if ((DRY_RUN)); then
        echo "DRY_RUN PREREQUISITE=fixed-llvm action=rebuild"
        return
    fi

    export LLVM_URL LLVM_SHA CANGJIE_COMPILER_URL CANGJIE_COMPILER_SHA
    export FLATBUFFERS_URL FLATBUFFERS_SHA
    local build_root="$STATE_ROOT/fixed-llvm-build"
    local llvm_fork="$build_root/llvm-fork"
    local compiler="$build_root/cangjie-compiler"
    local flatbuffers="$build_root/flatbuffers"
    local llc_build="$build_root/llc-build"
    local flatbuffers_build="$build_root/flatbuffers-build"
    local generated="$build_root/shim-generated"
    local llc_sha opt_sha shim_sha

    mkdir -p "$build_root"
    checkout_exact "$llvm_fork" "$LLVM_URL" "$LLVM_SHA" || return 1
    checkout_sparse_exact "$compiler" "$CANGJIE_COMPILER_URL" "$CANGJIE_COMPILER_SHA" schema || return 1
    checkout_exact "$flatbuffers" "$FLATBUFFERS_URL" "$FLATBUFFERS_SHA" || return 1

    cmake -G Ninja -S "$llvm_fork/llvm" -B "$llc_build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DLLVM_ENABLE_ASSERTIONS=OFF \
        -DBUILD_SHARED_LIBS=OFF \
        -DLLVM_LINK_LLVM_DYLIB=OFF \
        -DLLVM_BUILD_LLVM_DYLIB=OFF \
        -DLLVM_ENABLE_RTTI=OFF \
        -DLLVM_TARGETS_TO_BUILD=X86 \
        -DLLVM_ENABLE_PROJECTS= \
        -DCMAKE_C_COMPILER=clang \
        -DCMAKE_CXX_COMPILER=clang++ \
        '-DCMAKE_CXX_FLAGS=-gline-tables-only -include cstdint -include unordered_map -include map -include vector -include string'
    ninja -j "$JOBS" -C "$llc_build" llc opt
    gzip -n -c -9 "$llc_build/bin/llc" > "$CJCJ_FIXED_LLVM_DIR/llc.gz"
    gzip -n -c -9 "$llc_build/bin/opt" > "$CJCJ_FIXED_LLVM_DIR/opt.gz"

    cmake -G Ninja -S "$flatbuffers" -B "$flatbuffers_build" \
        -DFLATBUFFERS_BUILD_TESTS=OFF \
        -DFLATBUFFERS_BUILD_FLATLIB=OFF \
        -DFLATBUFFERS_BUILD_SHAREDLIB=OFF
    ninja -j "$JOBS" -C "$flatbuffers_build" flatc
    mkdir -p "$generated/flatbuffers"
    "$flatbuffers_build/flatc" --no-warnings -c -o "$generated/flatbuffers" \
        "$compiler/schema/ModuleFormat.fbs"
    clang++ -std=c++17 -O2 -fPIC -fno-rtti -fno-exceptions \
        -I"$llvm_fork/llvm/include" -I"$llc_build/include" \
        -I"$flatbuffers/include" -I"$generated" \
        -c "$REPO_ROOT/runtime_shim/cjselfhost_llvmshim.cpp" \
        -o "$CJCJ_FIXED_LLVM_DIR/cjselfhost_llvmshim.o"

    llc_sha=$(sha256sum "$llc_build/bin/llc" | awk '{print $1}')
    opt_sha=$(sha256sum "$llc_build/bin/opt" | awk '{print $1}')
    shim_sha=$(sha256sum "$CJCJ_FIXED_LLVM_DIR/cjselfhost_llvmshim.o" | awk '{print $1}')
    {
        printf 'PLATFORM=linux_x86_64\n'
        printf 'LLVM_SHA=%s\n' "$LLVM_SHA"
        printf 'CANGJIE_COMPILER_SHA=%s\n' "$CANGJIE_COMPILER_SHA"
        printf 'FLATBUFFERS_SHA=%s\n' "$FLATBUFFERS_SHA"
        printf 'LLC_SHA256=%s\n' "$llc_sha"
        printf 'OPT_SHA256=%s\n' "$opt_sha"
        printf 'SHIM_SHA256=%s\n' "$shim_sha"
    } > "$CJCJ_FIXED_LLVM_DIR/llvm-tools.manifest"
    fixed_tuple_is_current || return 1
    if [[ ${CJCJ_LLVM_DEPOT_PUBLISH:-0} == 1 ]]; then
        publish_fixed_tuple_to_depot || return 1
    fi
}

run_fixed_tuple_prerequisite() {
    local log="$LOG_ROOT/${START_STAMP}-fixed-llvm.log"
    local start_ns end_ns wall rc
    start_ns=$(date +%s%N)
    set +e
    build_fixed_tuple > "$log" 2>&1
    rc=$?
    set -e
    end_ns=$(date +%s%N)
    wall=$(elapsed_seconds "$start_ns" "$end_ns")
    printf 'prerequisite\tfixed-llvm\tBuild native LLVM tools\t%s\t%s\t%s\n' "$rc" "$wall" "$log" >> "$TIMINGS"
    printf 'PREREQUISITE=fixed-llvm rc=%s wall_s=%s log=%s\n' "$rc" "$wall" "$log"
    return "$rc"
}

step_2() {
    git -C "$REPO_ROOT" rev-parse --is-inside-work-tree
    git -C "$REPO_ROOT" rev-parse HEAD
}

step_3() {
    cat "$HOST_TOOLCHAIN_PIN" >> "$GITHUB_ENV"
    cat "$REPO_ROOT/ci/source_pin.env" >> "$GITHUB_ENV"
}

step_4() {
    npx --yes zx@8 "$REPO_ROOT/ci/load_runtime_pin.mjs"
}

step_5() {
    load_github_state
    # Resolve through the strict reader so retries cannot reuse a retained
    # pre-1.3 GITHUB_ENV value, including when the pin is malformed.
    resolve_host_toolchain_pin
    export CJCJ_SDK_STOCK_LLC=1
    npx --yes zx@8 "$REPO_ROOT/ci/setup_sdk.mjs"
    local host_sdk="$HOME/.cjv/toolchains/$CJCJ_TOOLCHAIN"
    [[ -d $host_sdk ]]
    append_env CJCJ_SRCBUILD_BOOTSTRAP_SDK "$host_sdk"
    append_env CJCJ_SRCBUILD_HOST_SDK "$host_sdk"
}

step_6() {
    npx --yes zx@8 "$REPO_ROOT/build/cli.mjs" --target "$TARGET" install-system-deps
}

step_7() {
    append_env SCCACHE_ERROR_LOG "$RUNNER_TEMP/sccache-error.log"
}

step_8() {
    srcbuild_setup_compiler_cache
}

support_cache_root() {
    printf '%s\n' "${CJCJ_SRCBUILD_SUPPORT_CACHE:-${SRCBUILD_USER_HOME:-$HOME}/.cache/cjcj-srcbuild/support}"
}

srcbuild_tarball_resolve_mirror() {
    local original=$1 mappings=${CJCJ_SRCBUILD_TARBALL_MIRRORS:-} entry source mirror resolved=$1 matched=0
    local -A seen=()
    local -a entries=()
    IFS=';' read -r -a entries <<< "$mappings"
    for entry in "${entries[@]}"; do
        [[ -n $entry ]] || continue
        [[ $entry == *=* && -n ${entry%%=*} && -n ${entry#*=} ]] || {
            echo "invalid CJCJ_SRCBUILD_TARBALL_MIRRORS entry: $entry" >&2
            return 1
        }
        source=${entry%%=*}
        mirror=${entry#*=}
        [[ -z ${seen[$source]+set} ]] || {
            echo "duplicate CJCJ_SRCBUILD_TARBALL_MIRRORS source: $source" >&2
            return 1
        }
        seen[$source]=1
        if [[ $source == "$original" ]]; then
            resolved=$mirror
            matched=1
        fi
    done
    if ((matched == 0)); then
        echo "TARBALL-MIRROR none, falling back to $original" >&2
        [[ ${CJCJ_SRCBUILD_REQUIRE_MIRRORS:-0} != 1 ]] || {
            echo "tarball mirror required by CJCJ_SRCBUILD_REQUIRE_MIRRORS=1: $original" >&2
            return 1
        }
    fi
    printf '%s\n' "$resolved"
}

support_tarball_sha256() {
    local url=$1 dest=$2 resolved path_file
    if [[ -f $dest ]]; then
        sha256sum "$dest" | awk '{print $1}'
        return 0
    fi
    resolved=$(srcbuild_tarball_resolve_mirror "$url") || return 1
    path_file=$resolved
    [[ $path_file == file://* ]] && path_file=${path_file#file://}
    if [[ -f $path_file ]]; then
        sha256sum "$path_file" | awk '{print $1}'
        return 0
    fi
    return 1
}

support_cache_key() {
    local ncurses_url='https://ftp.gnu.org/pub/gnu/ncurses/ncurses-6.5.tar.gz'
    local libedit_url='https://thrysoee.dk/editline/libedit-20210910-3.1.tar.gz'
    local ncurses_tar="$CANGJIE_BUILD_ROOT/ncurses-6.5.tar.gz"
    local libedit_tar="$CANGJIE_BUILD_ROOT/libedit-20210910-3.1.tar.gz"
    local ncurses_sha libedit_sha
    ncurses_sha=$(support_tarball_sha256 "$ncurses_url" "$ncurses_tar") || return 1
    libedit_sha=$(support_tarball_sha256 "$libedit_url" "$libedit_tar") || return 1
    printf '%s-%s\n' "$ncurses_sha" "$libedit_sha"
}

support_cache_dir() {
    local key
    key=$(support_cache_key) || return 1
    printf '%s/%s\n' "$(support_cache_root)" "$key"
}

step_9() {
    local cache_dir
    if cache_dir=$(support_cache_dir) && [[ -f $cache_dir/.ok ]]; then
        echo "local support-library cache hit $cache_dir"
    else
        echo "local support-library cache miss"
    fi
}

step_10() {
    local cache_dir
    if cache_dir=$(support_cache_dir) && [[ -f $cache_dir/.ok ]]; then
        echo "support libraries already retained in shared cache $cache_dir"
        mkdir -p "$CANGJIE_BUILD_ROOT"
        cp -a -- "$cache_dir/." "$CANGJIE_BUILD_ROOT/"
        rm -f "$CANGJIE_BUILD_ROOT/.ok"
    else
        npx --yes zx@8 "$REPO_ROOT/build/cli.mjs" --target "$TARGET" install-static-libs
    fi
}

step_11() {
    local cache_dir
    [[ -d $CANGJIE_BUILD_ROOT ]]
    cache_dir=$(support_cache_dir) || return 1
    mkdir -p "$cache_dir"
    cp -a -- "$CANGJIE_BUILD_ROOT/." "$cache_dir/"
    touch "$cache_dir/.ok"
}

step_12() {
    local value
    value=$(npx --yes zx@8 "$REPO_ROOT/build/cli.mjs" --cangjie-version "${CJCJ_CANGJIE_REF:-}" print-version)
    append_env CJCJ_SRCBUILD_VERSION "$value"
    printf 'Cangjie source SDK version: %s\n' "$value"
}

build_cli() {
    npx --yes zx@8 "$REPO_ROOT/build/cli.mjs" \
        --target "$TARGET" --build-type "$BUILD_TYPE" \
        --cangjie-version "$CJCJ_SRCBUILD_VERSION" "$@"
}

ensure_exact_clone() {
    local directory=$1 url=$2 revision=$3 attempt
    [[ -d $directory ]] || return 0
    local actual_url=
    if ! git -C "$directory" remote get-url origin >/dev/null 2>&1; then
        git -C "$directory" remote add origin "$url"
    else
        actual_url=$(git -C "$directory" remote get-url origin)
        [[ $actual_url == "$url" ]] || {
            echo "source remote mismatch: path=$directory actual=$actual_url expected=$url" >&2
            return 1
        }
    fi
    if [[ $(git -C "$directory" rev-parse HEAD 2>/dev/null || true) == "$revision" ]]; then
        return 0
    fi
    for attempt in 1 2 3; do
        if srcbuild_git_fetch "$directory" "$url" "$revision"; then
            git -C "$directory" checkout --detach FETCH_HEAD
            [[ $(git -C "$directory" rev-parse HEAD) == "$revision" ]]
            return
        fi
        echo "interrupted clone repair retry=$attempt path=$directory" >&2
    done
    return 1
}

step_13() {
    # shallowClone creates the directory before its network fetch.  A dropped
    # connection therefore leaves a directory that fetch.mjs would otherwise
    # mistake for a completed clone on --from-step retries.
    ensure_exact_clone "$CANGJIE_WORKSPACE/cangjie_compiler" "$COMPILER_SRC_URL" "$COMPILER_REF" || return 1
    ensure_exact_clone "$CANGJIE_WORKSPACE/cangjie_runtime" "$RUNTIME_SRC_URL" "$RUNTIME_REF" || return 1
    ensure_exact_clone "$CANGJIE_WORKSPACE/cangjie_tools" "$TOOLS_SRC_URL" "$TOOLS_REF" || return 1
    ensure_exact_clone "$CANGJIE_WORKSPACE/cangjie_stdx" "$STDX_SRC_URL" "$STDX_REF" || return 1
    build_cli fetch \
        --repo-url "compiler=$COMPILER_SRC_URL" --repo-tag "compiler=$COMPILER_REF" \
        --repo-url "runtime=$RUNTIME_SRC_URL" --repo-tag "runtime=$RUNTIME_REF" \
        --repo-url "tools=$TOOLS_SRC_URL" --repo-tag "tools=$TOOLS_REF" \
        --repo-url "stdx=$STDX_SRC_URL" --repo-tag "stdx=$STDX_REF"
}

step_14() {
    npx --yes zx@8 "$REPO_ROOT/ci/srcbuild/steps/verify-source-pins.mjs"
}

step_20() { build_cli build stdx; }
step_21() { build_cli build tools; }

step_22() {
    node "$REPO_ROOT/ci/release/prepare_cjpm_artifact.mjs" \
        --platform "$TARGET" \
        --binary "$CANGJIE_WORKSPACE/cangjie_tools/cjpm/dist/cjpm" \
        --outdir "$REPO_ROOT/.release-cjpm/$TARGET"
}

step_23() {
    [[ -s $REPO_ROOT/.release-cjpm/$TARGET/cjpm ]]
    echo "source cjpm artifact retained locally"
}

step_24() {
    node "$REPO_ROOT/ci/release/prepare_hle_artifact.mjs" \
        --platform "$TARGET" \
        --binary "$CANGJIE_WORKSPACE/cangjie_tools/hyperlangExtension/target/bin/main" \
        --outdir "$REPO_ROOT/.release-hle/$TARGET"
}

step_25() {
    [[ -d $REPO_ROOT/.release-hle/$TARGET ]]
    echo "source hle artifact retained locally"
}

step_26() {
    build_cli package
    build_cli verify
}

step_29() {
    export CANGJIE_CPP_SRC="$CANGJIE_WORKSPACE/cangjie_compiler"
    npx --yes zx@8 "$REPO_ROOT/ci/srcbuild/steps/build-shim.mjs"
}

step_30() {
    export SOURCE_SDK_VERSION="$CJCJ_SRCBUILD_VERSION"
    npx --yes zx@8 "$REPO_ROOT/ci/srcbuild/tests/inject-version.test.mjs"
    npx --yes zx@8 "$REPO_ROOT/ci/srcbuild/steps/inject-version.mjs"
}

step_31() {
    ulimit -c unlimited || true
    npx --yes zx@8 "$STAGE1_STEP_SCRIPT"
}

step_32() {
    export cjHeapSize=20GB
    npx --yes zx@8 "$STAGE2_STEP_SCRIPT"
}

step_33() {
    npx --yes zx@8 "$STAGE3_STEP_SCRIPT"
}

declare -Ar STEP_NAMES=(
    [2]='Checkout cjcj'
    [3]='Load source pins'
    [4]='Load and validate runtime pin'
    [5]='Provision uncoloured host SDK'
    [6]='Install build dependencies'
    [7]='Configure sccache diagnostics'
    [8]='Set up sccache'
    [9]='Restore support library cache'
    [10]='Build support libraries'
    [11]='Save support library cache'
    [12]='Generate SDK version'
    [13]='Download pinned source'
    [14]='Verify source revisions'
    [20]='Build stdx from source'
    [21]='Build SDK tools from source'
    [22]='Prepare source-built cjpm artifact'
    [23]='Upload source-built cjpm artifact'
    [24]='Prepare source-built hle artifact'
    [25]='Upload source-built hle artifact'
    [26]='Package and verify SDK'
    [29]='Build compiler shim'
    [30]='Inject selfhost compiler version'
    [31]='Bootstrap stage0 (cjpm -O1)'
    [32]='Bootstrap stage1 (cjpm -j1 cjHeapSize=20GB)'
    [33]='Build stage 3 compiler and final std'
)

validate_stage_step_contracts() {
    includes_step() {
        local want=$1
        if declare -F selected_dag_steps >/dev/null 2>&1; then
            selected_dag_steps "$FROM_STEP" "$THROUGH_STEP" | /usr/bin/grep -qx "$want"
        else
            ((FROM_STEP <= want && THROUGH_STEP >= want))
        fi
    }
    if includes_step 31; then
        [[ -f $STAGE1_STEP_SCRIPT ]] || {
            echo "dry-run referenced step script is missing: $STAGE1_STEP_SCRIPT" >&2
            return 1
        }
        /usr/bin/grep -Fq 'cjpm build' "$STAGE1_STEP_SCRIPT" || {
            echo "dry-run stage0 contract missing: cjpm build in $STAGE1_STEP_SCRIPT" >&2
            return 1
        }
        /usr/bin/grep -Fq 'compile-option = "-O1"' "$STAGE1_STEP_SCRIPT" || {
            echo "dry-run stage0 contract missing: compile-option=-O1 in $STAGE1_STEP_SCRIPT" >&2
            return 1
        }
        /usr/bin/grep -Fq 'cjc -O1 -o' "$STAGE1_STEP_SCRIPT" && {
            echo "dry-run stage0 contract forbids cjc -O1 -o in $STAGE1_STEP_SCRIPT" >&2
            return 1
        }
    fi
    if includes_step 32; then
        [[ -f $STAGE2_STEP_SCRIPT ]] || {
            echo "dry-run referenced step script is missing: $STAGE2_STEP_SCRIPT" >&2
            return 1
        }
        /usr/bin/grep -Fq "cjHeapSize: '20GB'" "$STAGE2_STEP_SCRIPT" || {
            echo "dry-run stage2 contract missing: cjHeapSize=20GB in $STAGE2_STEP_SCRIPT" >&2
            return 1
        }
        /usr/bin/grep -Fq 'cjpm build -j 1' "$STAGE2_STEP_SCRIPT" || {
            echo "dry-run stage2 contract missing: cjpm build -j 1 in $STAGE2_STEP_SCRIPT" >&2
            return 1
        }
    fi
    if includes_step 33; then
        [[ -f $STAGE3_STEP_SCRIPT ]] || {
            echo "dry-run referenced step script is missing: $STAGE3_STEP_SCRIPT" >&2
            return 1
        }
        [[ -d $STAGE2_PRODUCT_DIR ]] || {
            echo "dry-run stage3 input missing: stage2 product directory $STAGE2_PRODUCT_DIR" >&2
            return 1
        }
    fi
}

print_dry_step() {
    local step=$1 toolchain=$2
    printf 'DRY_RUN STEP=%s name=%s\n' "$step" "${STEP_NAMES[$step]}"
    case "$step" in
        5)
            printf 'DRY_RUN ENV CJCJ_SDK_STOCK_LLC=1 CJCJ_TOOLCHAIN=%s\n' "$toolchain"
            printf 'DRY_RUN COMMAND=npx --yes zx@8 %q\n' "$REPO_ROOT/ci/setup_sdk.mjs"
            ;;
        31)
            printf 'DRY_RUN COMMAND=bootstrap --stage stage0 --colour-tuple %q --src %q\n' \
                "$CJCJ_FIXED_LLVM_DIR" "$REPO_ROOT"
            printf 'DRY_RUN COMMAND=npx --yes zx@8 %q\n' "$STAGE1_STEP_SCRIPT"
            printf 'DRY_RUN INNER_COMMAND=cjpm build\n'
            printf 'DRY_RUN COMPILE_OPTION=-O1\n'
            ;;
        32)
            printf 'DRY_RUN ASSUME=stage1-artifact-exists\n'
            printf 'DRY_RUN ENV cjHeapSize=20GB cjHeapSwap=on\n'
            printf 'DRY_RUN COMMAND=npx --yes zx@8 %q\n' "$STAGE2_STEP_SCRIPT"
            printf 'DRY_RUN INNER_COMMAND=cjpm build -j 1\n'
            ;;
        33)
            printf 'DRY_RUN ENV CJCJ_STAGE3_STDLIB_BUILD_TYPE=%s cjHeapSwap=on\n' "$BUILD_TYPE"
            printf 'DRY_RUN COMMAND=npx --yes zx@8 %q\n' "$STAGE3_STEP_SCRIPT"
            ;;
    esac
}

if ((DRY_RUN)); then
    validate_stage_step_contracts
    resolve_host_toolchain_pin
    dry_run_toolchain=$CJCJ_TOOLCHAIN
    readonly dry_run_toolchain
    printf 'DRY_RUN host=%s target=%s jobs=%s cpuset=%s from_step=%s through_step=%s\n' \
        "$host_name" "$TARGET" "$JOBS" "$CPUSET" "$FROM_STEP" "$THROUGH_STEP"
    build_fixed_tuple
    while IFS= read -r step; do
        print_dry_step "$step" "$dry_run_toolchain"
    done < <(selected_dag_steps "$FROM_STEP" "$THROUGH_STEP")
    printf 'DRY_RUN RESULT=success through_step=%s\n' "$THROUGH_STEP"
    exit 0
fi

load_github_state
printf 'CPU window=%s width=%s => JOBS=%s\n' "$CPUSET" "$CPUSET_WIDTH" "$JOBS"
printf 'RUN host=%s target=%s jobs=%s cpuset=%s from_step=%s through_step=%s\n' \
    "$host_name" "$TARGET" "$JOBS" "$CPUSET" "$FROM_STEP" "$THROUGH_STEP"

# fixed-llvm is a needs: dependency of srcbuild.yml, so it completes before the
# numbered srcbuild steps rather than being invented as an in-band step 27 build.
run_fixed_tuple_prerequisite

while IFS= read -r step; do
    reject_diagnostic_workspace "$VERIFIER_DIAGNOSTIC_MARKER" "step $step" || exit $?
    run_step "$step" "${STEP_NAMES[$step]}" "step_$step"
done < <(selected_dag_steps "$FROM_STEP" "$THROUGH_STEP")

printf 'RESULT=success through_step=%s timings=%s\n' "$THROUGH_STEP" "$TIMINGS"
