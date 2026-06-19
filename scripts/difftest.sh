#!/usr/bin/env bash
# Corpus-driven differential test: selfhost cjc vs reference cjc (cjv latest nightly = 1.2.0).
# For each corpus program: compile+run with BOTH; classify PASS / MISMATCH / SELFHOST-FAIL(reason).
# Usage: bash scripts/difftest.sh [corpus_dir]
set -u
TC=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260619020029
export CANGJIE_HOME=$TC
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$REPO/target/release/bin/cangjie_compiler::cjc"
REF=/root/.cjv/bin/cjc
CORPUS="${1:-$REPO/scripts/difftest_corpus}"
WORK=$(mktemp -d)
pass=0; mismatch=0; fail=0; total=0
declare -A reasons
runone() {
  local f="$1" name; name=$(basename "$f" .cj)
  total=$((total+1))
  # reference
  local rexit rout
  if "$REF" "$f" -o "$WORK/$name.ref" >/dev/null 2>&1; then
    rout=$("$WORK/$name.ref" 2>/dev/null); rexit=$?
  else rout="<REF-COMPILE-FAIL>"; rexit=-1; fi
  # selfhost
  local sexit sout slog="$WORK/$name.slog"
  if "$SELF" "$f" -o "$WORK/$name.self" --set-runtime-rpath >"$slog" 2>&1; then
    sout=$("$WORK/$name.self" 2>/dev/null); sexit=$?
    if [ "$sout" = "$rout" ] && [ "$sexit" = "$rexit" ]; then
      pass=$((pass+1)); printf "PASS    %-22s -> exit=%s\n" "$name" "$sexit"
    else
      mismatch=$((mismatch+1)); printf "MISMATCH %-21s self(exit=%s out='%s') ref(exit=%s out='%s')\n" "$name" "$sexit" "${sout:0:30}" "$rexit" "${rout:0:30}"
    fi
  else
    fail=$((fail+1))
    local r
    r=$(grep -hoiE "not yet ported[^\"]*|globalCache miss|unsupported AST type kind[^\"]*|unsupported construct[^\"]*|should have result|Out of memory|does not match pointee|IllegalState[A-Za-z]*|IllegalArgument[A-Za-z]*|no Sema target|no resolvedFunction|you should set a return value" "$slog" 2>/dev/null | head -1)
    [ -z "$r" ] && r=$(grep -iE "error|exception" "$slog" 2>/dev/null | head -1 | cut -c1-60)
    [ -z "$r" ] && r="<unknown>"
    reasons["$r"]=$(( ${reasons["$r"]:-0} + 1 ))
    printf "FAIL    %-22s %s\n" "$name" "$r"
  fi
}
for f in "$CORPUS"/*.cj; do [ -e "$f" ] && runone "$f"; done
echo "================================================================"
echo "TOTAL=$total  PASS=$pass  MISMATCH=$mismatch  FAIL=$fail"
echo "---- gap tally (selfhost faithful-pipeline failures, ranked) ----"
for k in "${!reasons[@]}"; do printf "%3d  %s\n" "${reasons[$k]}" "$k"; done | sort -rn
rm -rf "$WORK"
