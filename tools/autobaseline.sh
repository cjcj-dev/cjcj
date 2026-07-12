#!/usr/bin/env bash
# Rebuild a commit in a reusable measurement worktree and append a 15-package SC baseline.
set -euo pipefail
[[ $# -eq 1 ]] || { echo "usage: $0 <commit>" >&2; exit 2; }
ROOT="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"; COMMIT="$(git -C "$ROOT" rev-parse --verify "$1^{commit}")"; SHORT="$(git -C "$ROOT" rev-parse --short "$COMMIT")"
# sc_bcgate.py derives the selfhost module name from a worktree path containing "cjcj".
WT="${AUTOBASELINE_WORKTREE:-/mnt/ramwt/cjcj_autobaseline}"; BRANCH="autobaseline/cjcj-work"; REPORTS_ROOT="${REPORTS_ROOT:-/root/cj_build/reports}"; TREND="$REPORTS_ROOT/BASELINE_TREND.tsv"
PKGS=(option conditional_compilation mangle frontend_tool incremental_compilation modules driver meta_transformation lex ast frontend cjc basic codegen macro); LOG="${AUTOBASELINE_LOG:-/tmp/autobaseline-${SHORT}.log}"
if [[ -d "$WT/.git" || -f "$WT/.git" ]]; then git -C "$WT" merge --abort >/dev/null 2>&1 || true; git -C "$WT" reset --hard -q "$COMMIT"; git -C "$WT" clean -fdq
else git -C "$ROOT" worktree add --quiet -B "$BRANCH" "$WT" "$COMMIT"; fi
copy_shims() {
    local source shim path rev
    for source in "$ROOT/runtime_shim" "${AUTOBASELINE_SHIM_SOURCE:-}"; do
        [[ -n "$source" && -d "$source" ]] || continue
        for shim in "$source"/*.o; do [[ -e "$shim" ]] && cp -f "$shim" "$WT/runtime_shim/"; done
    done
    while IFS= read -r path; do
        [[ "$path" == "$WT" ]] && continue
        rev="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
        [[ "$rev" == "$COMMIT" ]] || continue
        for shim in "$path"/runtime_shim/*.o; do [[ -e "$shim" ]] && cp -f "$shim" "$WT/runtime_shim/"; done
    done < <(git -C "$ROOT" worktree list --porcelain | sed -n 's/^worktree //p')
}
copy_shims
if [[ ! -f "$WT/runtime_shim/cjselfhost_llvmshim.o" || ! -f "$WT/runtime_shim/binsecinfo_llvmshim.o" ]]; then
    (cd "$WT" && bash runtime_shim/build_shim.sh) >>"$LOG" 2>&1 || { tail -40 "$LOG" >&2; exit 1; }
fi
export PATH="/root/.cjv/bin:$PATH"; export CANGJIE_HOME="${CANGJIE_HOME:-/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029}"
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"; export cjHeapSize="${cjHeapSize:-12GB}"
(cd "$WT" && cjpm build -j "${AUTOBASELINE_JOBS:-48}") >>"$LOG" 2>&1 || { echo "BUILD-FAIL log=$LOG" >&2; tail -60 "$LOG" >&2; exit 1; }
(cd "$WT" && python3 scripts/sc_bcgate.py "${PKGS[@]}") | tee -a "$LOG"
total_line="$(grep '^TOTAL:' "$LOG" | tail -1)"; [[ -n "$total_line" ]] || { echo "missing sc_bcgate TOTAL" >&2; exit 1; }
read -r total identical pct < <(sed -n 's/^TOTAL: shared=\([0-9]*\) byte-identical=\([0-9]*\) (\([0-9.]*%\)) differing=.*/\1 \2 \3/p' <<<"$total_line")
[[ -n "$total" && -n "$identical" && -n "$pct" ]] || { echo "unparseable: $total_line" >&2; exit 1; }
top5="$(grep -E '^[a-z_]+: shared=[0-9]+' "$LOG" | sed -n 's/^\([^:]*\): shared=[0-9]* byte-identical=[0-9]* ([0-9.]*%) differing=\([0-9]*\).*/\2 \1/p' | sort -rn | head -5 | awk '{printf "%s%s=%s", (NR==1 ? "" : ","), $2, $1}')"
mkdir -p "$REPORTS_ROOT"; [[ -f "$TREND" ]] || printf 'date\tcommit\ttotal\tidentical\tpct\ttop5_package_differing\n' >"$TREND"
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%F)" "$COMMIT" "$total" "$identical" "$pct" "$top5" >>"$TREND"
echo "BASELINE date=$(date -u +%F) commit=$COMMIT total=$total identical=$identical pct=$pct top5=$top5"
