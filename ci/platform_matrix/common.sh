#!/usr/bin/env bash
# Shared logging and diagnostic-summary support for platform-matrix stages.
set -uo pipefail

stage_begin() {
    STAGE_NAME="${1:?stage name required}"
    PLATFORM_CI_ROOT="${PLATFORM_CI_ROOT:-$PWD/.platform-ci}"
    mkdir -p "$PLATFORM_CI_ROOT/logs"
    STAGE_LOG="$PLATFORM_CI_ROOT/logs/$STAGE_NAME.log"
    : > "$STAGE_LOG"
    exec > >(tee -a "$STAGE_LOG") 2>&1
    trap 'stage_finish "$?"' EXIT
}

stage_finish() {
    local rc="$1" local_summary
    local_summary="$PLATFORM_CI_ROOT/step-summary.md"
    emit_stage_summary() {
        printf '\n### %s — %s\n\n' "$STAGE_NAME" "$([ "$rc" -eq 0 ] && printf PASS || printf FAIL)"
        printf -- '- runner: `%s`\n' "${MATRIX_RUNNER:-local}"
        printf -- '- exit: `%s`\n\n' "$rc"
        printf '```text\n'
        grep -Eai 'fatal|error|failed|failure|undefined|not found|unsupported|segmentation|signal|panic|exception|blocker' \
            "$STAGE_LOG" | tail -n 40 || printf 'no error-pattern lines captured\n'
        printf '```\n'
    }
    emit_stage_summary >> "$local_summary"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        emit_stage_summary >> "$GITHUB_STEP_SUMMARY"
    fi
}

emit_blocked_summary() {
    local reason="${1:?blocked reason required}"
    printf 'BLOCKED: %s\n' "$reason"
    printf '\n- BLOCKED: %s\n' "$reason" >> "$PLATFORM_CI_ROOT/step-summary.md"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        printf '\n- BLOCKED: %s\n' "$reason" >> "$GITHUB_STEP_SUMMARY"
    fi
}

print_common_versions() {
    printf 'runner=%s os=%s arch=%s\n' "${MATRIX_RUNNER:-local}" "$(uname -s)" "$(uname -m)"
    uname -a || true
    git --version || true
    cmake --version | head -n 2 || true
    clang --version | head -n 3 || true
    python3 --version || true
}
