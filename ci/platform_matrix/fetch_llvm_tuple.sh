#!/usr/bin/env bash
# Download the newest successful native tuple job for this runner. A workflow run
# may be red solely because the independent Windows tuple failed, so success is
# checked on the matching matrix job rather than on the aggregate run conclusion.
# Linux x64 keeps consuming the already-proven immutable source-build run.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=ci/platform_matrix/common.sh
source "$HERE/common.sh"

PLATFORM_CI_ROOT="${PLATFORM_CI_ROOT:-$PWD/.platform-ci}"
mkdir -p "$PLATFORM_CI_ROOT/fixed-toolchain"
repo="${SHIM_ARTIFACT_REPOSITORY:-cjcj-dev/cjcj}"
workflow="${TUPLE_WORKFLOW:-platform-tuples.yml}"
branch="${TUPLE_BRANCH:-ci/platform-matrix}"

case "$(uname -s)/$(uname -m)" in
    Linux/x86_64|Linux/amd64) platform=linux_x86_64 ;;
    Linux/aarch64|Linux/arm64) platform=linux_aarch64 ;;
    Darwin/arm64|Darwin/aarch64) platform=darwin_aarch64 ;;
    Darwin/x86_64|Darwin/amd64) platform=darwin_x86_64 ;;
    MINGW*/x86_64|MSYS*/x86_64) platform=windows_x86_64 ;;
    *)
        emit_blocked_summary "unsupported tuple host $(uname -s)/$(uname -m)"
        exit 0
        ;;
esac
artifact_name="fixed-llvm-tools-$platform"

command -v gh >/dev/null || {
    emit_blocked_summary 'gh is unavailable; cannot query source-built LLVM tuples'
    exit 0
}
command -v unzip >/dev/null || {
    emit_blocked_summary 'unzip is unavailable; cannot unpack source-built LLVM tuple'
    exit 0
}

run_id=""
artifact_id=""
if [ "$platform" = linux_x86_64 ]; then
    # Known-good x64 sample produced by the existing source-build workflow.
    run_id="${LINUX_X64_TUPLE_RUN:-29840652402}"
    artifact_id="$(gh api "/repos/$repo/actions/runs/$run_id/artifacts" \
        --jq ".artifacts[] | select(.name == \"$artifact_name\" and .expired == false) | .id" \
        | head -n 1)"
else
    run_ids="$(gh api "/repos/$repo/actions/workflows/$workflow/runs?branch=$branch&status=completed&per_page=30" \
        --jq '.workflow_runs[].id')"
    for candidate_run in $run_ids; do
        successful_job="$(gh api "/repos/$repo/actions/runs/$candidate_run/jobs?filter=latest&per_page=100" \
            --jq ".jobs[] | select(.name | contains(\"$platform\")) | select(.conclusion == \"success\") | .id" \
            | head -n 1)"
        if [ -z "$successful_job" ]; then continue; fi
        candidate_artifact="$(gh api "/repos/$repo/actions/runs/$candidate_run/artifacts" \
            --jq ".artifacts[] | select(.name == \"$artifact_name\" and .expired == false) | .id" \
            | head -n 1)"
        if [ -n "$candidate_artifact" ]; then
            run_id="$candidate_run"
            artifact_id="$candidate_artifact"
            break
        fi
    done
fi

if [ -z "$artifact_id" ]; then
    emit_blocked_summary "no active $artifact_name artifact from a recent successful tuple job"
    exit 0
fi

scratch="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/platform-ci-$platform-tuple"
mkdir -p "$scratch"
archive="$scratch/artifact.zip"
gh api "/repos/$repo/actions/artifacts/$artifact_id/zip" > "$archive"
llc_entry="$(unzip -Z1 "$archive" | grep -E '(^|/)llc\.gz$' | head -n 1)"
shim_entry="$(unzip -Z1 "$archive" | grep -E '(^|/)cjselfhost_llvmshim\.o$' | head -n 1)"
if [ -z "$llc_entry" ] || [ -z "$shim_entry" ]; then
    emit_blocked_summary "$artifact_name is incomplete (requires llc.gz + cjselfhost_llvmshim.o)"
    exit 0
fi

dest="$PLATFORM_CI_ROOT/fixed-toolchain/$platform"
mkdir -p "$dest"
unzip -p "$archive" "$llc_entry" > "$dest/llc.gz"
unzip -p "$archive" "$shim_entry" > "$dest/cjselfhost_llvmshim.o"
test -s "$dest/llc.gz"
test -s "$dest/cjselfhost_llvmshim.o"

case "$platform" in
    linux_x86_64)
        expected_llc=084b0e437e879a20b72892464aed387955c7f0fe8e2d2b3bbb00f022af036e23
        expected_shim=bb05dfd1fa584aa8456356064c3dd392c3588a13708327a6f899d9a09ec4fd47
        test "$(sha256sum "$dest/llc.gz" | awk '{print $1}')" = "$expected_llc"
        test "$(sha256sum "$dest/cjselfhost_llvmshim.o" | awk '{print $1}')" = "$expected_shim"
        ;;
    linux_aarch64) file "$dest/cjselfhost_llvmshim.o" | grep -Eiq 'ELF 64-bit.*(aarch64|ARM)' ;;
    darwin_aarch64) file "$dest/cjselfhost_llvmshim.o" | grep -Eiq 'Mach-O 64-bit.*(arm64|aarch64)' ;;
    darwin_x86_64) file "$dest/cjselfhost_llvmshim.o" | grep -Eiq 'Mach-O 64-bit.*x86_64' ;;
    windows_x86_64) file "$dest/cjselfhost_llvmshim.o" | grep -Eiq '(COFF|Intel amd64|x86-64)' ;;
esac

cp "$dest/cjselfhost_llvmshim.o" runtime_shim/cjselfhost_llvmshim.o
case "$dest" in
    /*) dest_abs="$dest" ;;
    *)  dest_abs="$PWD/$dest" ;;
esac
{
    echo "FIXED_LLC_GZ=$dest_abs/llc.gz"
    echo "CJCJ_LLVM_SHIM_O=$dest_abs/cjselfhost_llvmshim.o"
    echo "PLATFORM_TUPLE=$platform"
} >> "${GITHUB_ENV:?GITHUB_ENV is required}"
printf 'tuple_run=%s\ntuple_artifact=%s\ntuple_platform=%s\n' "$run_id" "$artifact_id" "$platform"
sha256sum "$dest/llc.gz" "$dest/cjselfhost_llvmshim.o"
