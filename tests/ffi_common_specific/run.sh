#!/bin/bash
set -u
root=$(cd "$(dirname "$0")/../.." && pwd)
fixtures="$root/tests/ffi_common_specific"
compiler=${1:?compiler path}
out=${2:?output dir}
mkdir -p "$out"
sha256sum "$compiler" | tee "$out/compiler.sha256"
file "$compiler" > "$out/compiler.file"

declare -A expect=(
  [java_mirror_common.cj]="@JavaMirror declaration cannot be declared common or specific"
  [java_impl_specific.cj]="@JavaImpl declaration cannot be declared common or specific"
  [objc_mirror_common.cj]="@ObjCMirror declaration cannot be declared common or specific"
  [objc_impl_specific.cj]="@ObjCImpl declaration cannot be declared common or specific"
  [objc_mirror_func_specific.cj]="@ObjCMirror declaration cannot be declared common or specific"
)
others=(
  "@JavaMirror declaration cannot be declared common or specific"
  "@JavaImpl declaration cannot be declared common or specific"
  "@ObjCMirror declaration cannot be declared common or specific"
  "@ObjCImpl declaration cannot be declared common or specific"
)

fail=0
for src in "${!expect[@]}"; do
  log="$out/${src}.log"
  "$compiler" --output-type=chir --diagnostic-format=noColor "$fixtures/$src" >"$log" 2>&1
  rc=$?
  printf '%s\n' "$rc" > "$out/${src}.rc"
  msg="${expect[$src]}"
  hit=$(/usr/bin/grep -F -c "$msg" "$log" || true)
  printf '%s\n' "$hit" > "$out/${src}.hit"
  extra=0
  for other in "${others[@]}"; do
    if [ "$other" = "$msg" ]; then
      continue
    fi
    n=$(/usr/bin/grep -F -c "$other" "$log" || true)
    extra=$((extra + n))
  done
  printf '%s\n' "$extra" > "$out/${src}.extra"
  if [ "$hit" -lt 1 ] || [ "$extra" -ne 0 ]; then
    echo "FAIL $src rc=$rc hit=$hit extra=$extra"
    fail=1
  else
    echo "PASS $src rc=$rc hit=$hit extra=$extra"
  fi
done
exit "$fail"
