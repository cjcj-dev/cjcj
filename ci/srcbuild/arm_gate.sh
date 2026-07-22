#!/usr/bin/env bash
# Fail-closed native-aarch64 gate for the final packaged cjcj SDK.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SDK="${1:?usage: arm_gate.sh <packaged-sdk-dir>}"
SELF="$SDK/bin/cjcj"
WORK="${RUNNER_TEMP:-/tmp}/cjcj-arm-gate"
STRESS="$WORK/stress"
SMOKE="$WORK/smoke"
SUMMARY="$WORK/stress-summary.tsv"
PLATFORM_DIR="linux_aarch64_cjnative"
status=0

test "$(uname -m)" = aarch64
test -x "$SELF"
rm -rf "$WORK"
mkdir -p "$STRESS" "$SMOKE"

export CANGJIE_HOME="$SDK"
export PATH="$SDK/bin:$SDK/tools/bin:$PATH"
export LD_LIBRARY_PATH="$SDK/third_party/llvm/lib:$SDK/runtime/lib/$PLATFORM_DIR:$SDK/tools/lib:${LD_LIBRARY_PATH:-}"

find "$SDK" -type f -exec file {} + > "$WORK/sdk-file-manifest.log"
for native_file in \
    "$SDK/bin/cjc" \
    "$SDK/bin/cjcj" \
    "$SDK/third_party/llvm/bin/llc" \
    "$SDK/tools/bin/cjpm"; do
    test -f "$native_file"
    file "$native_file" | tee -a "$WORK/native-proof.log"
    file "$native_file" | grep -Fq 'ARM aarch64'
done
if grep -Eq 'ELF .* (x86-64|Intel 80386)' "$WORK/sdk-file-manifest.log"; then
    echo "FATAL: packaged ARM SDK contains an x86 ELF artifact" >&2
    grep -E 'ELF .* (x86-64|Intel 80386)' "$WORK/sdk-file-manifest.log" >&2
    exit 1
fi

printf 'heap_gb\tround\trc\tsha256\n' > "$SUMMARY"
for heap_gb in 8 12; do
    export cjHeapSize="${heap_gb}GB"
    for round in $(seq 1 10); do
        tag="heap${heap_gb}-round$(printf '%02d' "$round")"
        round_dir="$STRESS/$tag"
        mkdir -p "$round_dir"
        stdout="$round_dir/stdout.log"
        stderr="$round_dir/stderr.log"
        rc_file="$round_dir/rc"
        hash_file="$round_dir/output.sha256"
        output="$round_dir/incremental.a"

        set +e
        (
            cd "$round_dir"
            timeout 900 "$SELF" \
                --package "$ROOT/packages/incremental_compilation/src" \
                --module-name cjcj \
                --import-path "$ROOT/target/release" \
                --output-type=staticlib \
                -o "$output"
        ) >"$stdout" 2>"$stderr"
        rc=$?
        set -e
        printf '%s\n' "$rc" > "$rc_file"

        if [ -s "$output" ]; then
            sha256sum "$output" > "$hash_file"
            hash="$(cut -d' ' -f1 "$hash_file")"
        else
            printf 'MISSING  %s\n' "$output" > "$hash_file"
            hash=MISSING
            status=1
        fi
        printf '%s\t%s\t%s\t%s\n' "$heap_gb" "$round" "$rc" "$hash" >> "$SUMMARY"

        for required in "$stdout" "$stderr" "$rc_file" "$hash_file"; do
            if [ ! -f "$required" ]; then
                echo "FATAL: missing stress evidence: $required" >&2
                status=1
            fi
        done
        if [ "$rc" -ne 0 ]; then
            echo "FATAL: $tag failed with rc=$rc" >&2
            status=1
        fi
    done
done

stress_ok="$(awk -F '\t' 'NR > 1 && $3 == 0 && $4 != "MISSING" { count++ } END { print count+0 }' "$SUMMARY")"
if [ "$stress_ok" -ne 20 ] || [ "$(($(wc -l < "$SUMMARY") - 1))" -ne 20 ]; then
    echo "FATAL: stress result is $stress_ok/20, or summary is incomplete" >&2
    status=1
fi

export cjHeapSize=12GB
set +e
timeout 900 bash "$ROOT/ci/smoke/run_smoke.sh" "$SELF" "$SMOKE/work" \
    >"$SMOKE/stdout.log" 2>"$SMOKE/stderr.log"
smoke_rc=$?
set -e
printf '%s\n' "$smoke_rc" > "$SMOKE/rc"
if [ "$smoke_rc" -ne 0 ] || ! grep -Fq 'smoke summary: pass=6 fail=0' "$SMOKE/stdout.log"; then
    echo "FATAL: packaged smoke did not pass 6/6 (rc=$smoke_rc)" >&2
    status=1
fi
smoke_logs=(
    01_hello.build.log 01_hello.run.log
    02_generics.build.log 02_generics.run.log
    03_closures.build.log 03_closures.run.log
    04_iface_enum.build.log 04_iface_enum.run.log
    05_ffi.build.log 05_ffi.run.log
    macro.build.log macro.app.log macro.run.log
)
for log in "${smoke_logs[@]}"; do
    if [ ! -f "$SMOKE/work/$log" ]; then
        echo "FATAL: missing smoke evidence: $SMOKE/work/$log" >&2
        status=1
    fi
done

scan_logs=()
while IFS= read -r -d '' log; do scan_logs+=("$log"); done \
    < <(find "$STRESS" "$SMOKE" -type f \( -name '*.log' -o -name 'stdout.log' -o -name 'stderr.log' \) -print0)
if [ "${#scan_logs[@]}" -eq 0 ]; then
    echo 'FATAL: no gate logs found for diagnostic scan' >&2
    status=1
else
    if grep -EHi 'Wait mutator list lock timeout|signal([ :]|$)|SIGABRT|timed out|timeout' "${scan_logs[@]}"; then
        echo 'FATAL: timeout or signal diagnostic found' >&2
        status=1
    fi
    if grep -EHi 'toRegion2Idx.*(CHECK|verifier)|(CHECK|verifier).*toRegion2Idx' "${scan_logs[@]}"; then
        echo 'FATAL: toRegion2Idx CHECK/verifier diagnostic found' >&2
        status=1
    fi
fi

if [ "$status" -ne 0 ]; then
    echo 'native aarch64 packaged gate: FAIL' >&2
    exit 1
fi
echo 'native aarch64 packaged gate: PASS (stress=20/20 smoke=6/6 diagnostics=0)'
