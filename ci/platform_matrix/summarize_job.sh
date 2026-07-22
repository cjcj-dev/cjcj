#!/usr/bin/env bash
# Append one compact terminal error line after all executable job stages.
set -euo pipefail

PLATFORM_CI_ROOT="${PLATFORM_CI_ROOT:-$PWD/.platform-ci}"
summary_file="$PLATFORM_CI_ROOT/step-summary.md"
mkdir -p "$PLATFORM_CI_ROOT"

last_error="$({
    for stage in runtime cjcj test; do
        log="$PLATFORM_CI_ROOT/logs/$stage.log"
        [ ! -f "$log" ] || grep -Eai '(^|[^[:alpha:]])error:' "$log" || true
    done
} | tail -n 1 | sed $'s/\033\\[[0-9;]*[[:alpha:]]//g')"
if [ -z "$last_error" ]; then
    last_error='no error: line captured'
fi

emit_final_error() {
    printf '\n### Final key error\n\n'
    printf -- '- runner: `%s`\n' "${MATRIX_RUNNER:-local}"
    printf -- '- last `error:` line: `%s`\n' "${last_error//\`/\'}"
}
emit_final_error >> "$summary_file"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    emit_final_error >> "$GITHUB_STEP_SUMMARY"
fi
printf 'final_error=%s\n' "$last_error"
