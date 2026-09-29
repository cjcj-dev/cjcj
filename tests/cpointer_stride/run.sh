#!/usr/bin/env bash
# SDK must contain std.core rebuilt by the compiler being tested.
set -uo pipefail
ulimit -c 0
sdk=$1
runtime=$2
out=$3
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$out"
sdk=$(realpath "$sdk")
out=$(realpath "$out")
export CANGJIE_HOME=$sdk
uptime > "$out/uptime-before.txt"
start=$SECONDS
sha256sum "$here/main.cj" "$here/run.sh" \
  "$sdk/lib/linux_x86_64_cjnative/libcangjie-std-core.a" \
  "$runtime/libcangjie-runtime.so" "$runtime/libboundscheck.so" > "$out/inputs.sha256"
"$sdk/bin/cjc" "$here/main.cj" -O0 -o "$out/stride" > "$out/build.log" 2>&1
rc=$?
printf '%s\n' "$rc" > "$out/build.rc"
if [ "$rc" != 0 ]; then exit "$rc"; fi
sha256sum "$out/stride" > "$out/elf.sha256"
LD_LIBRARY_PATH="$runtime:$sdk/lib/linux_x86_64_cjnative:$sdk/tools/lib:$sdk/third_party/llvm/lib" \
  "$out/stride" > "$out/run.log" 2>&1
rc=$?
printf '%s\n' "$rc" > "$out/run.rc"
printf 'rc=%s wall=%s\n' "$rc" "$((SECONDS-start))" > "$out/result.txt"
uptime > "$out/uptime-after.txt"
cat "$out/run.log" "$out/result.txt"
exit "$rc"
