#!/usr/bin/env bash
# Usage: run.sh /absolute/cjc /fresh/output-dir
# Mode binding before overload selection (std.collection shapes): for-in elements of a @local!
# collection, values bound from calls through function-typed parameters, and setter values of a
# @local! property (also when matched, as in hash_map.cj:529) select the @local! overload; the same
# values still cannot reach non-local slots. A value bound by `opt ?? throw` keeps plain properties
# (arg_opt.cj:676) and exclave HashMap.mapValues with a concrete key lowers (hash_map.cj:1686).
# The plain and the exclave std.core acquireArrayRawData<Byte> lower side by side in one package (file.cj:770).
# A value bound from a trailing-closure call, a `|>` pipeline or `quote(...)` keeps plain properties
# (std.unittest entry_main.cj:60, testmacro instrumentation.cj:697, macro_state.cj:37); a @local! pipeline
# result still cannot read a plain-receiver property.
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
check none_return_local 0 ""
check forin_tuple_local 0 ""
check neg_none_call_plain 1 "mismatched types|no matching function"
check neg_forin_tuple_plain 1 "mismatched types|no matching function"
check coalesce_enum_prop 0 ""
check exclave_map_values_add 0 ""
check interp_local_struct 0 ""
check exclave_raw_data_imported 0 ""
check lowered_receiver_prop 0 ""
check neg_lowered_receiver_plain 1 "'details' is not a member of class 'Box'"
exit $fail
