#!/usr/bin/env bash
# Usage: run.sh /absolute/cjc /fresh/output-dir
# Inheritance of modal interface defaults with an SDK whose std is built with --local-mode-api.
# std Equatable<T> declares `!=`, `!=(this @local!)` and `!=(this @local?)` defaults; a type listing both
# Comparable<T> and Equatable<T> reaches each of them twice. A modal default that is the same declaration on
# both paths must not be reported as "interface function '!=' must be implemented" (default mode cannot even
# spell the override); neither may a modal default that overrides another along an interface chain (Comparable<T>'s
# `==(this @local?)` over Equal<T>'s). Such an accepted override must also be the implementation that runs, in either
# supertype order, through extends and generic interfaces (local_*_dispatch, std_local_dispatch). Negative controls: the plain-member
# rule, unrelated modal defaults, and truly missing abstract members are still diagnosed, each with exactly one error.
set -u
cjc=$1; out=$2; here=$(cd "$(dirname "$0")" && pwd); mkdir "$out" || exit 2
fail=0; pass=0; total=0
local_flags=(--experimental --enable-local-mode)
note() { echo "$*" | tee -a "$out/summary.txt"; }
plain() { sed 's/\x1b\[[0-9;]*m//g' "$1"; }
crashed() { grep -q -e "An exception has occurred" -e "IllegalStateException" -e "Segmentation fault" "$1"; }
pos() { # name arm expected-stdout cjc-flags...
  local name=$1 arm=$2 want=$3; shift 3
  local tag="${name}_${arm}" rc=0 r=NA ok=1 got=""
  total=$((total + 1))
  (cd "$out" && "$cjc" "$@" "$here/$name.cj" -o "$out/$tag" > "$out/$tag.log" 2>&1) || rc=$?
  [ "$rc" = 0 ] || ok=0
  crashed "$out/$tag.log" && ok=0
  if [ "$rc" = 0 ]; then
    r=0; (cd "$out" && "./$tag") > "$out/$tag.run.log" 2>&1 || r=$?
    got=$(cat "$out/$tag.run.log"); [ "$r" = 0 ] || ok=0; [ "$got" = "$want" ] || ok=0
  fi
  if [ $ok = 1 ]; then pass=$((pass + 1)); else fail=1; fi
  note "$tag compile rc=$rc run rc=$r stdout=[$got] want=[$want] $([ $ok = 1 ] && echo PASS || echo FAIL)"
  [ "$rc" = 0 ] || plain "$out/$tag.log" | grep "error" | head -3 | sed 's/^/    /' | tee -a "$out/summary.txt"
}
neg() { # name arm exact-diagnostic cjc-flags...
  local name=$1 arm=$2 diag=$3; shift 3
  local tag="${name}_${arm}" rc=0 ok=1
  total=$((total + 1))
  (cd "$out" && "$cjc" "$@" "$here/$name.cj" -o "$out/$tag" > "$out/$tag.log" 2>&1) || rc=$?
  [ "$rc" = 1 ] || ok=0
  plain "$out/$tag.log" | grep -qxF "error: $diag" || ok=0
  plain "$out/$tag.log" | grep -qxF "1 error generated, 1 error printed." || ok=0
  crashed "$out/$tag.log" && ok=0
  [ -e "$out/$tag" ] && ok=0
  if [ $ok = 1 ]; then pass=$((pass + 1)); else fail=1; fi
  note "$tag compile rc=$rc want=1 diag=[$diag] $([ $ok = 1 ] && echo PASS || echo FAIL)"
  [ $ok = 1 ] || plain "$out/$tag.log" | grep "error" | head -4 | sed 's/^/    /' | tee -a "$out/summary.txt"
}
pos unicode_shape default "true true true true"
pos unicode_shape local "true true true true" "${local_flags[@]}"
pos swapped_order default "false true true"
pos swapped_order local "false true true" "${local_flags[@]}"
pos comparable_and_equal default "true true true"
pos std_chains default "4 true 3"
pos local_same_modal_default local "2 7" "${local_flags[@]}"
pos local_chain_override local "2 8 2 8" "${local_flags[@]}"
pos local_chain_dispatch local "11 11 11 11 11 3 4" "${local_flags[@]}"
pos std_local_dispatch local "cmp cmp eq eq true true true" "${local_flags[@]}"
pos local_extend_dispatch local "11 11 11 5 6 7" "${local_flags[@]}"
pos local_generic_dispatch local "21 21 21 3 1 2" "${local_flags[@]}"
neg neg_plain_diamond default "interface function '!=' must be implemented in 'P'"
neg neg_missing_abstract default "implementation of function or property is needed in 'M'"
neg neg_missing_eq default "implementation of function or property is needed in 'E'"
neg neg_plain_chain_override default "interface function 'foo' must be implemented in 'S'"
neg neg_local_unrelated local "interface function 'foo' must be implemented in 'S'" "${local_flags[@]}"
neg neg_local_missing_abstract local "implementation of function or property is needed in 'S'" "${local_flags[@]}"
note "TOTAL $pass/$total $([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
