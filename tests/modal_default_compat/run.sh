#!/usr/bin/env bash
# Usage: run.sh /absolute/cjc /fresh/output-dir
# Default-mode compatibility of an SDK whose std is built with --local-mode-api: ordinary programs compiled
# WITHOUT --enable-local-mode (at -O0, at -O2, and with --experimental alone) must compile, run rc=0 and print
# exactly the expected line. A std interface such as NotEqual<T> declares `!=`, `!=(this @local!)` and
# `!=(this @local?)`; if the receiver mode is dropped the three share one vtable slot key and CHIR throws
# "virtual method offset is not available name=!=" (even for println("hi")).
# Negative control: `@local!` in user code is still rejected (a diagnostic, not a compiler exception).
set -u
cjc=$1; out=$2; here=$(cd "$(dirname "$0")" && pwd); mkdir "$out" || exit 2
fail=0; pass=0; total=0
note() { echo "$*" | tee -a "$out/summary.txt"; }
crashed() { grep -q -e "An exception has occurred" -e "IllegalStateException" -e "Segmentation fault" "$1"; }
run_case() { # name arm expected-stdout cjc-flags...
  local name=$1 arm=$2 want=$3; shift 3
  local tag="${name}_${arm}" rc=0 r=0 ok=1 got=""
  total=$((total + 1))
  (cd "$out" && "$cjc" "$@" "$here/$name.cj" -o "$out/$tag" > "$out/$tag.log" 2>&1) || rc=$?
  [ "$rc" = 0 ] || ok=0
  crashed "$out/$tag.log" && ok=0
  if [ "$rc" = 0 ]; then
    (cd "$out" && "./$tag") > "$out/$tag.run.log" 2>&1 || r=$?
    got=$(cat "$out/$tag.run.log")
    [ "$r" = 0 ] || ok=0
    [ "$got" = "$want" ] || ok=0
  else
    r=NA
  fi
  if [ $ok = 1 ]; then pass=$((pass + 1)); else fail=1; fi
  note "$tag compile rc=$rc run rc=$r stdout=[$got] want=[$want] $([ $ok = 1 ] && echo PASS || echo FAIL)"
  if [ "$rc" != 0 ]; then head -3 "$out/$tag.log" | sed 's/^/    /' | tee -a "$out/summary.txt"; fi
}
neg_case() { # name arm cjc-flags...
  local name=$1 arm=$2; shift 2
  local tag="${name}_${arm}" rc=0 ok=1
  total=$((total + 1))
  (cd "$out" && "$cjc" "$@" "$here/$name.cj" -o "$out/$tag" > "$out/$tag.log" 2>&1) || rc=$?
  [ "$rc" = 1 ] || ok=0
  grep -q "local mode is disabled" "$out/$tag.log" || ok=0
  crashed "$out/$tag.log" && ok=0
  [ -e "$out/$tag" ] && ok=0
  if [ $ok = 1 ]; then pass=$((pass + 1)); else fail=1; fi
  note "$tag compile rc=$rc want=1 diag='local mode is disabled' $([ $ok = 1 ] && echo PASS || echo FAIL)"
}
for arm in O0 O2 exp; do
  case $arm in O0) flags=(-O0);; O2) flags=(-O2);; exp) flags=(--experimental);; esac
  run_case hello $arm "hi" "${flags[@]}"
  run_case only_eq $arm "false true true true true false false" "${flags[@]}"
  run_case default_interp $arm "Q 41" "${flags[@]}"
  run_case default_map $arm "a=1;" "${flags[@]}"
  run_case default_std_smoke $arm "13 7 Sq(2),Sq(3) 2 false" "${flags[@]}"
  run_case default_std_wide $arm "5 [2, 8, 18] io b.txt true 2" "${flags[@]}"
done
neg_case neg_local_syntax plain
neg_case neg_local_syntax exp --experimental
note "TOTAL $pass/$total $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
