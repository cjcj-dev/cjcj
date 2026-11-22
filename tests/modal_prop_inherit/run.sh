#!/usr/bin/env bash
# Usage: run.sh /absolute/cjc /fresh/output-dir
# Modal property overloads (plain + @local! receiver) inherited from one interface must not be
# reported as "inherited members have inconsistent decl types"; a property/function clash still must.
# A generic @local! receiver picks the @local! property through its upper bounds; a plain-only property still rejects it.
set -u
cjc=$1; out=$2; here=$(cd "$(dirname "$0")" && pwd); mkdir "$out" || exit 2
fail=0
check() { # name expected-rc diag-regex-or-empty
  local name=$1 want=$2 diag=$3 rc=0
  (cd "$out" && "$cjc" --experimental --enable-local-mode "$here/$name.cj" -o "$out/$name" > "$out/$name.log" 2>&1) || rc=$?
  local ok=1
  [ "$rc" = "$want" ] || ok=0
  if [ -n "$diag" ]; then grep -q "$diag" "$out/$name.log" || ok=0; else
    grep -q "inconsistent decl types" "$out/$name.log" && ok=0
    if [ $ok = 1 ]; then (cd "$out" && "./$name") > "$out/$name.run.log" 2>&1; local r=$?; [ $r = 0 ] || ok=0; echo "$name run rc=$r" >> "$out/summary.txt"; fi
  fi
  echo "$name compile rc=$rc want=$want $([ $ok = 1 ] && echo PASS || echo FAIL)" | tee -a "$out/summary.txt"
  [ $ok = 1 ] || fail=1
}
check inherit_both 0 ""
check extend_override 0 ""
check prop_func_clash 1 "inherited members 'length' have inconsistent decl types"
check generic_local_receiver 0 ""
check generic_local_receiver_plain_only 1 "'size' is not found for generic type 'T' in its upper bounds"
exit $fail
