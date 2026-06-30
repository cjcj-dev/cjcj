#!/usr/bin/env bash
# Corpus-driven differential test: selfhost cjc vs reference cjc (cjv latest nightly = 1.2.0).
# For each corpus program: compile+run with BOTH; classify PASS / MISMATCH / SELFHOST-FAIL(reason).
# Samples are independent, so they run in parallel (default: min(16,nproc)); aggregation is deterministic.
# Usage: bash scripts/difftest.sh [corpus_dir] [-j N]
#   internal: bash scripts/difftest.sh --one <file.cj>   (run+classify a single sample, prints one TSV line)
set -u
TC=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
export CANGJIE_HOME=$TC
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$REPO/target/release/bin/cangjie_compiler::cjc"
REF=/root/.cjv/bin/cjc

# ---- single-sample worker: prints exactly one TAB-separated line: STATUS<TAB>name<TAB>detail ----
if [ "${1:-}" = "--one" ]; then
  f="$2"; name=$(basename "$f" .cj)
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  cd "$WORK" || exit 1   # isolate per-worker CWD so concurrent cjc runs don't race on a shared .cached dir
  # reference (timeout-guarded so a runaway compile/binary can't hang the whole gate)
  if timeout 180 "$REF" "$f" -o "$WORK/$name.ref" >/dev/null 2>&1; then
    rout=$(timeout 30 "$WORK/$name.ref" 2>/dev/null); rexit=$?
  else rout="<REF-COMPILE-FAIL>"; rexit=-1; fi
  # selfhost (capture compile exit; 124 = timeout, e.g. non-terminating instantiation)
  slog="$WORK/$name.slog"
  timeout 180 "$SELF" "$f" -o "$WORK/$name.self" --set-runtime-rpath >"$slog" 2>&1; cexit=$?
  if [ "$cexit" = 0 ]; then
    sout=$(timeout 30 "$WORK/$name.self" 2>/dev/null); sexit=$?
    if [ "$sout" = "$rout" ] && [ "$sexit" = "$rexit" ]; then
      printf 'PASS\t%s\texit=%s\n' "$name" "$sexit"
    else
      printf 'MISMATCH\t%s\tself(exit=%s out=%q) ref(exit=%s out=%q)\n' "$name" "$sexit" "${sout:0:30}" "$rexit" "${rout:0:30}"
    fi
  elif [ "$cexit" = 124 ]; then
    printf 'FAIL\t%s\t%s\n' "$name" "<COMPILE-TIMEOUT-180s>"
  else
    r=$(grep -hoiE "not yet ported[^\"]*|globalCache miss|unsupported AST type kind[^\"]*|unsupported construct[^\"]*|should have result|Out of memory|does not match pointee|IllegalState[A-Za-z]*|IllegalArgument[A-Za-z]*|no Sema target|no resolvedFunction|you should set a return value" "$slog" 2>/dev/null | head -1)
    [ -z "$r" ] && r=$(grep -iE "error|exception" "$slog" 2>/dev/null | head -1 | cut -c1-60)
    [ -z "$r" ] && r="<unknown>"
    printf 'FAIL\t%s\t%s\n' "$name" "$r"
  fi
  exit 0
fi

# ---- main: parse args, fan out across samples, aggregate deterministically ----
CORPUS=""; JOBS=$(( $(nproc) < 16 ? $(nproc) : 16 ))
while [ $# -gt 0 ]; do
  case "$1" in
    -j|--jobs) JOBS="$2"; shift 2 ;;
    *) CORPUS="$1"; shift ;;
  esac
done
[ -z "$CORPUS" ] && CORPUS="$REPO/scripts/difftest_corpus"

RESULTS=$(mktemp)
trap 'rm -f "$RESULTS"' EXIT
# Run each sample through the --one worker, up to JOBS in parallel.
find "$CORPUS" -maxdepth 1 -name '*.cj' -print0 \
  | xargs -0 -P "$JOBS" -I{} bash "$0" --one {} >"$RESULTS"

sort -o "$RESULTS" "$RESULTS"
pass=$(grep -c '^PASS'$'\t' "$RESULTS"); mismatch=$(grep -c '^MISMATCH'$'\t' "$RESULTS"); fail=$(grep -c '^FAIL'$'\t' "$RESULTS")
total=$(( pass + mismatch + fail ))
# Per-sample lines (readable, sorted)
awk -F'\t' '{printf "%-8s %-22s %s\n", $1, $2, $3}' "$RESULTS"
echo "================================================================"
echo "TOTAL=$total  PASS=$pass  MISMATCH=$mismatch  FAIL=$fail"
echo "---- gap tally (selfhost faithful-pipeline failures, ranked) ----"
grep '^FAIL'$'\t' "$RESULTS" | cut -f3- | sort | uniq -c | sort -rn
