#!/usr/bin/env bash

# Run the source-build portion of .github/workflows/srcbuild.yml on kkk2.
# The step numbers intentionally match the GitHub Actions UI: step 1 is the
# implicit "Set up job", so the first repository step is step 2.

set -Eeuo pipefail

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
readonly SCRIPT_PATH
REPO_ROOT=$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd -P)
readonly REPO_ROOT
readonly HOST_TOOLCHAIN_PIN="$REPO_ROOT/ci/cjpm_pin.env"
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

if [[ ${1:-} == --lib-only ]]; then
    [[ $# == 1 ]] || {
        echo "--lib-only does not accept other arguments" >&2
        return 2 2>/dev/null || exit 2
    }
    return 0 2>/dev/null || exit 0
fi

usage() {
    cat <<'EOF'
Usage: tools/srcbuild_kkk2.sh [TARGET [JOBS [FROM_STEP]]]
       tools/srcbuild_kkk2.sh [--target TARGET] [--jobs N]
                              [--from-step N] [--through-step N] [--dry-run]
       source tools/srcbuild_kkk2.sh --lib-only

Defaults:
  TARGET=linux-x64  JOBS=96  FROM_STEP=2  THROUGH_STEP=33

Final source-build steps:
  32  Build stage 2 compiler (cjpm build -j 1, cjHeapSize=20GB)
  33  Build stage 3 compiler and final std

--dry-run validates referenced step scripts and their command contracts, then
prints the selected commands and environment without executing them.

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
JOBS=96
FROM_STEP=2
THROUGH_STEP=33
DRY_RUN=0

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
if ((${#positional[@]} >= 2)); then JOBS=${positional[1]}; fi
if ((${#positional[@]} >= 3)); then FROM_STEP=${positional[2]}; fi

[[ $TARGET == linux-x64 ]] || {
    echo "kkk2 is Linux/x86_64; srcbuild target '$TARGET' requires its matching native runner" >&2
    exit 2
}
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || { echo "jobs must be a positive integer" >&2; exit 2; }
((JOBS <= 96)) || { echo "jobs must not exceed this lane's reserved CPUs 0-95" >&2; exit 2; }
[[ $FROM_STEP =~ ^[0-9]+$ ]] || { echo "from-step must be an integer" >&2; exit 2; }
[[ $THROUGH_STEP =~ ^[0-9]+$ ]] || { echo "through-step must be an integer" >&2; exit 2; }
((FROM_STEP >= 1 && FROM_STEP <= 33)) || { echo "from-step must be in 1..33" >&2; exit 2; }
((THROUGH_STEP >= 2 && THROUGH_STEP <= 33)) || { echo "through-step must be in 2..33" >&2; exit 2; }
((FROM_STEP <= THROUGH_STEP)) || { echo "from-step must not exceed through-step" >&2; exit 2; }
if ((FROM_STEP == 1)); then FROM_STEP=2; fi

host_name=$(hostname -s)
[[ $host_name == kkk2 ]] || {
    echo "refusing build load on host '$host_name': run this script on kkk2 via tools/box.sh" >&2
    exit 3
}

cpu_last=$((JOBS - 1))
CPUSET="0-$cpu_last"
if [[ ${CJCJ_KKK2_AFFINED:-} != "$CPUSET" ]]; then
    exec taskset -c "$CPUSET" env CJCJ_KKK2_AFFINED="$CPUSET" \
        bash "$SCRIPT_PATH" "${ORIGINAL_ARGS[@]}"
fi

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
readonly BUILD_TYPE=relwithdebinfo
START_STAMP=$(date -u +%Y%m%dT%H%M%SZ)
readonly START_STAMP
readonly BASE_PATH="$PRIVATE_HOME/.local/bin:$PATH"

if ((DRY_RUN == 0)); then
    mkdir -p "$LOG_ROOT" "$RUNNER_TEMP" "$PRIVATE_HOME" "$CANGJIE_WORKSPACE" \
        "$CANGJIE_BUILD_ROOT" "$CJCJ_FIXED_LLVM_DIR"
fi

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

run_step() {
    local step=$1 name=$2 function_name=$3
    local log="$LOG_ROOT/${START_STAMP}-step${step}.log"
    local start_ns end_ns wall rc
    start_ns=$(date +%s%N)
    set +e
    "$function_name" > "$log" 2>&1
    rc=$?
    set -e
    end_ns=$(date +%s%N)
    wall=$(elapsed_seconds "$start_ns" "$end_ns")
    printf 'step\t%s\t%s\t%s\t%s\t%s\n' "$step" "$name" "$rc" "$wall" "$log" >> "$TIMINGS"
    printf 'STEP=%s name=%s rc=%s wall_s=%s log=%s\n' "$step" "$name" "$rc" "$wall" "$log"
    if ((rc != 0)); then
        if ((step == 31)); then record_crash_signature "$log"; fi
        return "$rc"
    fi
    load_github_state
}

fixed_tuple_is_current() {
    local manifest="$CJCJ_FIXED_LLVM_DIR/llvm-tools.manifest"
    [[ -s $CJCJ_FIXED_LLVM_DIR/llc.gz ]] || return 1
    [[ -s $CJCJ_FIXED_LLVM_DIR/opt.gz ]] || return 1
    [[ -s $CJCJ_FIXED_LLVM_DIR/cjselfhost_llvmshim.o ]] || return 1
    [[ -s $manifest ]] || return 1
    # shellcheck disable=SC1091
    source "$REPO_ROOT/ci/llvm_pin.env" || return 1
    [[ $(awk -F= '$1=="PLATFORM" {print $2}' "$manifest") == linux_x86_64 ]] || return 1
    [[ $(awk -F= '$1=="LLVM_SHA" {print $2}' "$manifest") == "$LLVM_SHA" ]] || return 1
    [[ $(awk -F= '$1=="CANGJIE_COMPILER_SHA" {print $2}' "$manifest") == "$CANGJIE_COMPILER_SHA" ]] || return 1
    [[ $(awk -F= '$1=="FLATBUFFERS_SHA" {print $2}' "$manifest") == "$FLATBUFFERS_SHA" ]] || return 1
    node "$REPO_ROOT/ci/llvm-tools-manifest.mjs" validate native "$manifest" >/dev/null || return 1
}

checkout_exact() {
    local directory=$1 url=$2 revision=$3
    if [[ ! -d $directory/.git ]]; then
        git clone --filter=blob:none --no-checkout "$url" "$directory"
    fi
    git -C "$directory" fetch --depth=1 origin "$revision"
    git -C "$directory" checkout --detach FETCH_HEAD
    [[ $(git -C "$directory" rev-parse HEAD) == "$revision" ]]
}

checkout_sparse_exact() {
    local directory=$1 url=$2 revision=$3 sparse_path=$4
    if [[ ! -d $directory/.git ]]; then
        git clone --filter=blob:none --no-checkout "$url" "$directory"
    fi
    git -C "$directory" sparse-checkout init --cone
    git -C "$directory" sparse-checkout set "$sparse_path"
    git -C "$directory" fetch --depth=1 origin "$revision"
    git -C "$directory" checkout --detach FETCH_HEAD
    [[ $(git -C "$directory" rev-parse HEAD) == "$revision" ]]
}

build_fixed_tuple() {
    if fixed_tuple_is_current; then
        echo "fixed LLVM tuple matches ci/llvm_pin.env; reusing it"
        return
    fi
    if ((DRY_RUN)); then
        echo "DRY_RUN PREREQUISITE=fixed-llvm action=rebuild"
        return
    fi

    # shellcheck disable=SC1091
    source "$REPO_ROOT/ci/llvm_pin.env"
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
    checkout_exact "$llvm_fork" "$LLVM_URL" "$LLVM_SHA"
    checkout_sparse_exact "$compiler" "$CANGJIE_COMPILER_URL" "$CANGJIE_COMPILER_SHA" schema
    checkout_exact "$flatbuffers" "$FLATBUFFERS_URL" "$FLATBUFFERS_SHA"

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
    fixed_tuple_is_current
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
    if command -v sccache >/dev/null; then
        append_env SCCACHE_PATH "$(command -v sccache)"
        sccache --start-server
        sccache --zero-stats
    else
        echo "sccache is absent; build/cli.mjs will leave compiler launchers unset"
    fi
}

step_9() {
    if [[ -f $STATE_ROOT/support-cache-$TARGET.ok ]]; then
        echo "local support-library cache hit"
    else
        echo "local support-library cache miss"
    fi
}

step_10() {
    if [[ -f $STATE_ROOT/support-cache-$TARGET.ok ]]; then
        echo "support libraries already retained locally"
    else
        npx --yes zx@8 "$REPO_ROOT/build/cli.mjs" --target "$TARGET" install-static-libs
    fi
}

step_11() {
    [[ -d $CANGJIE_BUILD_ROOT ]]
    touch "$STATE_ROOT/support-cache-$TARGET.ok"
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

source_fetch_url() {
    local original=$1 mappings=${CJCJ_SRCBUILD_SOURCE_MIRRORS:-} entry source mirror resolved=$1
    local -A seen=()
    local -a entries=()
    IFS=';' read -r -a entries <<< "$mappings"
    for entry in "${entries[@]}"; do
        [[ -n $entry ]] || continue
        [[ $entry == *=* && -n ${entry%%=*} && -n ${entry#*=} ]] || {
            echo "invalid CJCJ_SRCBUILD_SOURCE_MIRRORS entry: $entry" >&2
            return 1
        }
        source=${entry%%=*}
        mirror=${entry#*=}
        [[ -z ${seen[$source]+set} ]] || {
            echo "duplicate CJCJ_SRCBUILD_SOURCE_MIRRORS source: $source" >&2
            return 1
        }
        seen[$source]=1
        if [[ $source == "$original" ]]; then
            resolved=$mirror
        fi
    done
    printf '%s\n' "$resolved"
}

ensure_exact_clone() {
    local directory=$1 url=$2 revision=$3 attempt fetch_url
    [[ -d $directory ]] || return 0
    fetch_url=$(source_fetch_url "$url") || return
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
        if git -C "$directory" -c http.version=HTTP/1.1 fetch --depth 1 "$fetch_url" "$revision"; then
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
    ensure_exact_clone "$CANGJIE_WORKSPACE/cangjie_compiler" "$COMPILER_SRC_URL" "$COMPILER_REF"
    ensure_exact_clone "$CANGJIE_WORKSPACE/cangjie_runtime" "$RUNTIME_SRC_URL" "$RUNTIME_REF"
    ensure_exact_clone "$CANGJIE_WORKSPACE/cangjie_tools" "$TOOLS_SRC_URL" "$TOOLS_REF"
    ensure_exact_clone "$CANGJIE_WORKSPACE/cangjie_stdx" "$STDX_SRC_URL" "$STDX_REF"
    build_cli fetch \
        --repo-url "compiler=$COMPILER_SRC_URL" --repo-tag "compiler=$COMPILER_REF" \
        --repo-url "runtime=$RUNTIME_SRC_URL" --repo-tag "runtime=$RUNTIME_REF" \
        --repo-url "tools=$TOOLS_SRC_URL" --repo-tag "tools=$TOOLS_REF" \
        --repo-url "stdx=$STDX_SRC_URL" --repo-tag "stdx=$STDX_REF"
}

step_14() {
    npx --yes zx@8 "$REPO_ROOT/ci/srcbuild/steps/verify-source-pins.mjs"
}

step_15() {
    # shellcheck disable=SC1091
    source "$REPO_ROOT/ci/llvm_pin.env"
    export LLVM_URL LLVM_REF="$LLVM_SHA"
    npx --yes zx@8 "$REPO_ROOT/ci/srcbuild/steps/pin-compiler-llvm.mjs"
}

step_16() { build_cli build compiler; }

step_17() {
    npx --yes zx@8 "$REPO_ROOT/ci/srcbuild/steps/prepare-source-host-sdk.mjs"
}

step_18() { build_cli build runtime; }
step_19() { build_cli build stdlib; }
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

step_27() {
    fixed_tuple_is_current
    echo "fixed LLVM tuple retained at $CJCJ_FIXED_LLVM_DIR"
}

step_28() {
    npx --yes zx@8 "$REPO_ROOT/ci/srcbuild/steps/activate-source-sdk.mjs"
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
    [15]='Configure compiler LLVM'
    [16]='Build compiler oracle'
    [17]='Prepare source compiler host SDK'
    [18]='Build runtime from source'
    [19]='Build stdlib from source'
    [20]='Build stdx from source'
    [21]='Build SDK tools from source'
    [22]='Prepare source-built cjpm artifact'
    [23]='Upload source-built cjpm artifact'
    [24]='Prepare source-built hle artifact'
    [25]='Upload source-built hle artifact'
    [26]='Verify bootstrap SDK'
    [27]='Download native LLVM tuple'
    [28]='Install source SDK and fixed LLVM tuple'
    [29]='Build compiler shim'
    [30]='Inject selfhost compiler version'
    [31]='Build stage 1 compiler'
    [32]='Build stage 2 compiler'
    [33]='Build stage 3 compiler and final std'
)

validate_stage_step_contracts() {
    if ((FROM_STEP <= 31 && THROUGH_STEP >= 31)); then
        [[ -f $STAGE1_STEP_SCRIPT ]] || {
            echo "dry-run referenced step script is missing: $STAGE1_STEP_SCRIPT" >&2
            return 1
        }
    fi
    if ((FROM_STEP <= 32 && THROUGH_STEP >= 32)); then
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
    if ((FROM_STEP <= 33 && THROUGH_STEP >= 33)); then
        [[ -f $STAGE3_STEP_SCRIPT ]] || {
            echo "dry-run referenced step script is missing: $STAGE3_STEP_SCRIPT" >&2
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
            printf 'DRY_RUN COMMAND=npx --yes zx@8 %q\n' "$STAGE1_STEP_SCRIPT"
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
    for ((step = FROM_STEP; step <= THROUGH_STEP; step++)); do
        print_dry_step "$step" "$dry_run_toolchain"
    done
    printf 'DRY_RUN RESULT=success through_step=%s\n' "$THROUGH_STEP"
    exit 0
fi

load_github_state
printf 'RUN host=%s target=%s jobs=%s cpuset=%s from_step=%s through_step=%s\n' \
    "$host_name" "$TARGET" "$JOBS" "$CPUSET" "$FROM_STEP" "$THROUGH_STEP"

# fixed-llvm is a needs: dependency of srcbuild.yml, so it completes before the
# numbered srcbuild steps rather than being invented as an in-band step 27 build.
run_fixed_tuple_prerequisite

for ((step = FROM_STEP; step <= THROUGH_STEP; step++)); do
    run_step "$step" "${STEP_NAMES[$step]}" "step_$step"
done

printf 'RESULT=success through_step=%s timings=%s\n' "$THROUGH_STEP" "$TIMINGS"
