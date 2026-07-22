#!/usr/bin/env bash
# Always expose the terminal tuple failure, especially for the experimental
# Windows/MSYS2 source build, without weakening the job result.
set -euo pipefail

root="${TUPLE_ROOT:?TUPLE_ROOT is required}"
build_log="$root/logs/tuple-build.log"
source_log="$root/logs/source-fetch.log"
build_outcome="${BUILD_OUTCOME:-skipped}"
if [ "${WINDOWS_BUILD_OUTCOME:-skipped}" != skipped ]; then
    build_outcome="$WINDOWS_BUILD_OUTCOME"
fi
source_outcome="${SOURCE_OUTCOME:-skipped}"
if [ "${WINDOWS_SOURCE_OUTCOME:-skipped}" != skipped ]; then
    source_outcome="$WINDOWS_SOURCE_OUTCOME"
fi
last_reason="no error-pattern line captured"
logs=()
if [ -f "$source_log" ]; then logs+=("$source_log"); fi
if [ -f "$build_log" ]; then logs+=("$build_log"); fi
if [ "${#logs[@]}" -gt 0 ]; then
    captured="$(grep -Eai 'fatal|error|failed|failure|undefined|not found|unsupported|segmentation|signal|exception' "${logs[@]}" | tail -n 12 || true)"
    if [ -n "$captured" ]; then last_reason="$captured"; fi
fi

{
    printf '### fixed LLVM tuple `%s`\n\n' "${TUPLE_PLATFORM:-unknown}"
    printf -- '- LLVM pin: `%s`\n' "${LLVM_SHA:-unknown}"
    printf -- '- runner: `%s` (`%s` / `%s`)\n' "${RUNNER_NAME:-unknown}" "${RUNNER_OS:-unknown}" "${RUNNER_ARCH:-unknown}"
    printf -- '- dependency setup: msys2=`%s`, linux=`%s`, macOS=`%s`\n' \
        "${MSYS2_OUTCOME:-skipped}" "${LINUX_DEPS_OUTCOME:-skipped}" "${MACOS_DEPS_OUTCOME:-skipped}"
    printf -- '- shallow source fetch: `%s`\n' "$source_outcome"
    printf -- '- LLVM cache step: `%s`\n' "${CACHE_OUTCOME:-unknown}"
    printf -- '- tuple build: `%s`\n' "$build_outcome"
    if [ "${TUPLE_PLATFORM:-}" = windows_x86_64 ]; then
        printf -- '- Windows note: MSYS2/MinGW is the highest-risk tuple; failures remain red.\n'
    fi
    if [ "${TUPLE_PLATFORM:-}" = darwin_aarch64 ] || [ "${TUPLE_PLATFORM:-}" = darwin_x86_64 ]; then
        printf -- '- reuse: macOS 26 consumes this macOS 15 artifact for the same architecture/target.\n'
    fi
    printf '\n```text\n%s\n```\n' "$last_reason"
} >> "${GITHUB_STEP_SUMMARY:?GITHUB_STEP_SUMMARY is required}"
