#!/usr/bin/env bash
# Preview a branch pool in order, retaining no refs or worktrees after completion.
set -euo pipefail
[[ $# -gt 0 ]] || { echo "usage: $0 <branch-or-commit> [...]" >&2; exit 2; }
ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"; BASE="${MEGASCAN_BASE:-master}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)_$$"; WT="${MEGASCAN_WORKTREE:-/tmp/megascan_$STAMP}"; TMP_BRANCH="megascan/$STAMP"
MATRIX="$(mktemp /tmp/megascan-matrix.XXXXXX.tsv)"; OVERLAP="$(mktemp /tmp/megascan-overlap.XXXXXX.tsv)"
cleanup() { git -C "$WT" merge --abort >/dev/null 2>&1 || true; git -C "$ROOT" worktree remove --force "$WT" >/dev/null 2>&1 || true; git -C "$ROOT" branch -D "$TMP_BRANCH" >/dev/null 2>&1 || true; rm -f "$MATRIX" "$OVERLAP"; }
trap cleanup EXIT INT TERM
for ref in "$@"; do git -C "$ROOT" rev-parse --verify --quiet "$ref^{commit}" >/dev/null || { echo "unknown ref: $ref" >&2; exit 2; }; done
git -C "$ROOT" worktree add --quiet -b "$TMP_BRANCH" "$WT" "$BASE"
printf 'branch\tstatus\tconflicting_files\n' >"$MATRIX"; printf 'left\tright\toverlapping_files\tfiles\n' >"$OVERLAP"
declare -a refs=("$@") changed=()
for ref in "${refs[@]}"; do changed+=("$(git -C "$ROOT" diff --name-only "$BASE...$ref" | sort)"); done
for ((i=0; i<${#refs[@]}; i++)); do for ((j=i+1; j<${#refs[@]}; j++)); do
    files="$(comm -12 <(printf '%s\n' "${changed[i]}" | sed '/^$/d') <(printf '%s\n' "${changed[j]}" | sed '/^$/d') | paste -sd, -)"
    count=0; [[ -z "$files" ]] || count="$(tr ',' '\n' <<<"$files" | wc -l | tr -d ' ')"
    printf '%s\t%s\t%s\t%s\n' "${refs[i]}" "${refs[j]}" "$count" "$files" >>"$OVERLAP"
done; done
for ref in "${refs[@]}"; do
    if git -C "$WT" merge --no-commit --no-ff "$ref" >/dev/null 2>&1; then
        if git -C "$WT" diff --cached --quiet; then printf '%s\tALREADY-APPLIED\t\n' "$ref" >>"$MATRIX"
        else git -C "$WT" commit --no-gpg-sign -qm "megascan transient merge $ref"; printf '%s\tMERGED\t\n' "$ref" >>"$MATRIX"; fi
    else files="$(git -C "$WT" diff --name-only --diff-filter=U | paste -sd, -)"; printf '%s\tCONFLICT\t%s\n' "$ref" "$files" >>"$MATRIX"; git -C "$WT" merge --abort
    fi
done
echo '=== CONFLICT MATRIX ==='; column -t -s $'\t' "$MATRIX" 2>/dev/null || cat "$MATRIX"
echo '=== OVERLAPPING FILES ==='; column -t -s $'\t' "$OVERLAP" 2>/dev/null || cat "$OVERLAP"
