#!/bin/bash
# Compile lambda-alias fixtures with a real cjc. Prints one CASE line per input.
# arm=candidate|cut-producer|cut-consumer
set -u
ARM=${1:-candidate}
CJC=${2:-cjc}
SRC=${3:-$(dirname "$0")}
OUT=${4:-/tmp/lambda_alias_cache}
mkdir -p "$OUT"
fail=0
run_case() {
  local name="$1" kind="$2"
  local log="$OUT/${name}.log"
  local bin="$OUT/${name}.out"
  "$CJC" "$SRC/${name}.cj" -o "$bin" -Woff unused >"$log" 2>&1
  local rc=$?
  local miss
  miss=$(sed 's/\x1b\[[0-9;]*m//g' "$log" | /usr/bin/grep -c 'mismatched number of parameters' || true)
  local result=PASS
  case "$kind" in
    target)
      if [ "$ARM" = candidate ]; then
        [ "$rc" -eq 0 ] && [ "$miss" -eq 0 ] || result=FAIL
      else
        [ "$rc" -ne 0 ] && [ "$miss" -ge 1 ] || result=FAIL
      fi
      ;;
    sibling)
      if [ "$ARM" = cut-consumer ]; then
        [ "$rc" -ne 0 ] && [ "$miss" -ge 1 ] || result=FAIL
      else
        [ "$rc" -eq 0 ] && [ "$miss" -eq 0 ] || result=FAIL
      fi
      ;;
    control)
      [ "$rc" -eq 0 ] && [ "$miss" -eq 0 ] || result=FAIL
      ;;
    negative)
      [ "$rc" -ne 0 ] && [ "$miss" -ge 1 ] || result=FAIL
      ;;
  esac
  [ "$result" = PASS ] || fail=1
  echo "CASE name=$name kind=$kind arm=$ARM rc=$rc miss=$miss result=$result"
}
run_case tuple target
run_case iflet target
run_case forin target
run_case whilelet target
run_case compound target
run_case sibling sibling
run_case explicit control
run_case true_mismatch negative
echo "SUMMARY arm=$ARM fail=$fail"
exit "$fail"
