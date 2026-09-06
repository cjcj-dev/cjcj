#!/usr/bin/env bash
set -u
set -o pipefail

arm=${1:?arm required}
core_domain=${CORE_DOMAIN:?set CORE_DOMAIN to a current cjops windows result}
lane_root=/root/impl_cjcj_primitive_array_copy_dispatch
compiler="$lane_root/work/cjcj-$arm"
stage_sdk="$lane_root/work/sdk-stage0"
coloured_sdk="$lane_root/work/sdk-stage0-coloured"
test_root="$lane_root/tests"
evidence="$lane_root/evidence/tests-$arm"
so_root=/root/sodepot/751210efa9494b0877ee82e68af65171a0ecb85e
compiler_libs="$stage_sdk/runtime/lib/linux_x86_64_cjnative:$stage_sdk/lib/linux_x86_64_cjnative:$stage_sdk/third_party/llvm/lib:$stage_sdk/tools/lib:/usr/lib/x86_64-linux-gnu"

rm -rf "$evidence"
mkdir -p "$evidence"
date -Ins > "$evidence/start.txt"
uptime > "$evidence/uptime-before.txt"
printf '%s\n' "$core_domain" > "$evidence/core-domain.txt"
printf '%s\n' "$arm" > "$evidence/arm.txt"
sha256sum "$0" > "$evidence/test-recipe.sha256"
sha256sum "$compiler" > "$evidence/compiler.sha256"
stat -c '%y %n' "$compiler" > "$evidence/compiler.stat"
sha256sum "$test_root"/*.cj "$test_root/check_array_copy_ir.py" > "$evidence/test-inputs.sha256"
sha256sum "$so_root/libcangjie-runtime.so" "$so_root/libboundscheck.so" > "$evidence/so-lineage.sha256"
sha256sum "$stage_sdk/third_party/llvm/bin/opt" "$stage_sdk/third_party/llvm/bin/llc" \
  "$coloured_sdk/third_party/llvm/bin/opt" "$coloured_sdk/third_party/llvm/bin/llc" \
  > "$evidence/backend-tools.sha256"

overall=0
for name in primitive noref_struct ref_elements zero_layout; do
  case_dir="$evidence/$name"
  mkdir -p "$case_dir"
  case_sdk="$stage_sdk"
  if test "$name" = noref_struct; then
    case_sdk="$coloured_sdk"
  fi
  case_libs="$case_sdk/runtime/lib/linux_x86_64_cjnative:$case_sdk/lib/linux_x86_64_cjnative:$case_sdk/third_party/llvm/lib:$case_sdk/tools/lib:/usr/lib/x86_64-linux-gnu"
  run_libs="$so_root:$case_libs"
  printf '%s\n' "$case_sdk" > "$case_dir/sdk.txt"
  env -i HOME=/root USER=root TMPDIR="$lane_root/tmp" CANGJIE_HOME="$case_sdk" \
    PATH="$case_sdk/bin:$case_sdk/tools/bin:$case_sdk/third_party/llvm/bin:/usr/bin:/bin" \
    LD_LIBRARY_PATH="$compiler_libs" cjHeapSize=4GB \
    bash -c 'ulimit -c 0; exec taskset -c "$1" "$2" -O2 -g --dump-ir --dump-to-screen --set-runtime-rpath -o "$3" "$4"' \
      bash "$core_domain" "$compiler" "$case_dir/$name" "$test_root/$name.cj" \
      > "$case_dir/compile.log" 2>&1
  compile_rc=$?
  printf '%s\n' "$compile_rc" > "$case_dir/compile.rc"
  if test "$compile_rc" -ne 0; then
    overall=1
    printf '%s\n' 'NOT_RUN' > "$case_dir/run.rc"
    printf '%s\n' 'FAIL compile' > "$case_dir/judgement.txt"
    continue
  fi
  sha256sum "$case_dir/$name" > "$case_dir/elf.sha256"
  stat -c '%y %n' "$case_dir/$name" > "$case_dir/elf.stat"
  env LD_LIBRARY_PATH="$run_libs" ldd "$case_dir/$name" > "$case_dir/ldd.txt" 2>&1
  (
    ulimit -c 0
    env LD_LIBRARY_PATH="$run_libs" taskset -c "$core_domain" "$case_dir/$name"
  ) > "$case_dir/run.log" 2>&1
  run_rc=$?
  printf '%s\n' "$run_rc" > "$case_dir/run.rc"

  expected=''
  case "$name" in
    primitive) expected='PRIMITIVE_OK 200:48:57' ;;
    noref_struct) expected='NOREF_STRUCT_OK 10' ;;
    ref_elements) expected='REF_ELEMENTS_OK 15:ab' ;;
    zero_layout) expected='ZERO_LAYOUT_OK 2' ;;
  esac
  printf '%s\n' "$expected" > "$case_dir/expected.txt"

  if test "$run_rc" -ne 0 || ! /usr/bin/grep -Fqx "$expected" "$case_dir/run.log"; then
    overall=1
    printf '%s\n' "FAIL expected rc=0 stdout=$expected" > "$case_dir/judgement.txt"
  else
    printf '%s\n' 'PASS runtime behavior' > "$case_dir/judgement.txt"
  fi
done

python3 "$test_root/check_array_copy_ir.py" --arm "$arm" --dir "$evidence" \
  > "$evidence/ir-gate.log" 2>&1
ir_rc=$?
printf '%s\n' "$ir_rc" > "$evidence/ir-gate.rc"
if test "$ir_rc" -ne 0; then
  overall=1
fi

for name in primitive noref_struct ref_elements zero_layout; do
  printf '%s compile=%s run=%s judgement=%s\n' "$name" \
    "$(tr -d '\n' < "$evidence/$name/compile.rc")" \
    "$(tr -d '\n' < "$evidence/$name/run.rc")" \
    "$(tr -d '\n' < "$evidence/$name/judgement.txt" 2>/dev/null || printf missing)"
done > "$evidence/summary.txt"
printf 'ir_gate=%s overall=%s\n' "$ir_rc" "$overall" >> "$evidence/summary.txt"
uptime > "$evidence/uptime-after.txt"
date -Ins > "$evidence/end.txt"
printf '%s\n' "$overall" > "$evidence/test-suite.rc"
exit "$overall"
