#!/usr/bin/env bash
# Usage: run.sh /absolute/cjc /fresh/output-dir
# Mode binding before overload selection (std.collection shapes): for-in elements of a @local!
# collection, values bound from calls through function-typed parameters, and setter values of a
# @local! property (also when matched, as in hash_map.cj:529) select the @local! overload; the same
# values still cannot reach non-local slots.
set -u
cjc=$1; out=$2; here=$(cd "$(dirname "$0")" && pwd); mkdir "$out" || exit 2
fail=0
check() { # name expected-rc diag-ERE-or-empty
  local name=$1 want=$2 diag=$3 rc=0
  (cd "$out" && "$cjc" --experimental --enable-local-mode "$here/$name.cj" -o "$out/$name" > "$out/$name.log" 2>&1) || rc=$?
  local ok=1
  [ "$rc" = "$want" ] || ok=0
  if [ -n "$diag" ]; then grep -Eq "$diag" "$out/$name.log" || ok=0; else
    if [ $ok = 1 ]; then (cd "$out" && "./$name") > "$out/$name.run.log" 2>&1; local r=$?; [ $r = 0 ] || ok=0; echo "$name run rc=$r" >> "$out/summary.txt"; fi
  fi
  echo "$name compile rc=$rc want=$want $([ $ok = 1 ] && echo PASS || echo FAIL)" | tee -a "$out/summary.txt"
  [ $ok = 1 ] || fail=1
}
check forin_local_elements 0 ""
check match_fn_result 0 ""
check setter_local_param 0 ""
check setter_match_add 0 ""
check neg_forin_plain_only 1 "mismatched types|no matching function"
check neg_setter_plain_only 1 "mismatched types|no matching function"
exit $fail
