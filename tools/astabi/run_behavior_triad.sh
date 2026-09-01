#!/usr/bin/env bash
set -uo pipefail

root=${1:?evidence root}
project=/root/impl_astabi-behavior/r4-project
candidate_archive=/root/impl_astabi-behavior/candidate_bundle.a
official_elf=/root/impl_astabi-behavior/target-official-current/release/bin/main
runtime_lib=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458/runtime/lib/linux_x86_64_cjnative
llvm_lib=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458/third_party/llvm/lib
mkdir -p "$root" "$root/baseline" "$root/perturbed" "$root/restored"
rm -rf "$project"
mkdir -p "$project/src"
cp /root/impl_astabi-behavior/candidate-r2/cjpm.toml "$project/cjpm.toml"
cp /root/impl_astabi-behavior/candidate-current/cjpm.lock "$project/cjpm.lock"
cp /root/impl_astabi-behavior/candidate-current/src/main.cj "$project/src/main.cj"
base_source=$project/src/main.cj
cp "$base_source" "$root/driver-baseline.cj"
cp "$base_source" "$root/driver-restored.cj"
cp "$base_source" "$root/driver-perturbed.cj"

cat > "$root/fault_override.cpp" <<'EOF'
#include <cstdint>
extern "C" void __real_CJ_CheckAddSpace(unsigned char *, bool *);
extern "C" void __wrap_CJ_CheckAddSpace(unsigned char *tokens, bool *flags) {
  __real_CJ_CheckAddSpace(tokens, flags);
  if (tokens && flags) {
    const std::uint32_t count = static_cast<std::uint32_t>(tokens[0]) |
      (static_cast<std::uint32_t>(tokens[1]) << 8) |
      (static_cast<std::uint32_t>(tokens[2]) << 16) |
      (static_cast<std::uint32_t>(tokens[3]) << 24);
    if (count == 1u) flags[0] = !flags[0];
  }
}
EOF
g++ -std=c++17 -fPIC -c "$root/fault_override.cpp" -o "$root/fault_override.o" > "$root/fault-compile.log" 2>&1
fault_compile_rc=$?
printf '%s\n' "$fault_compile_rc" > "$root/fault-compile.rc"
export LD_LIBRARY_PATH=$runtime_lib:$llvm_lib

run_arm() {
  local arm=$1 source_file=$2 fault=$3 arm_dir=$root/$1
  cp "$source_file" "$project/src/main.cj"
  if test "$fault" = 1; then
    cp "$project/cjpm.toml" "$arm_dir/cjpm.toml.before"
    sed -i "s# -lstdc++# $root/fault_override.o --wrap=CJ_CheckAddSpace -lstdc++#" "$project/cjpm.toml"
    cp "$project/cjpm.toml" "$arm_dir/cjpm.toml.fault"
  fi
  date -u +%s%N > "$arm_dir/build.start.ns"
  (cd "$project" && /root/.cjv/bin/cjpm build --target-dir "$arm_dir/target" -o main > "$arm_dir/build.log" 2>&1)
  local build_rc=$?
  printf '%s\n' "$build_rc" > "$arm_dir/build.rc"
  date -u +%s%N > "$arm_dir/build.end.ns"
  local elf
  elf=$(find "$arm_dir/target" -type f -name main -perm -111 -print -quit)
  if test "$build_rc" -eq 0 && test -n "$elf"; then
    sha256sum "$project/src/main.cj" > "$arm_dir/source.sha256"
    candidate_archive=$(find "$arm_dir/target" -type f -name 'libmacro_pkg@cjcj.a' -print -quit)
    sha256sum "$candidate_archive" > "$arm_dir/archive.sha256"
    sha256sum "$elf" > "$arm_dir/elf.sha256"
    cp "$elf" "$arm_dir/main"
    sha256sum "$arm_dir/main" > "$arm_dir/retained-elf.sha256"
    date -u +%s%N > "$arm_dir/run.start.ns"
    "$arm_dir/main" > "$arm_dir/output.tsv" 2> "$arm_dir/stderr.log"
    printf '%s\n' "$?" > "$arm_dir/run.rc"
    date -u +%s%N > "$arm_dir/run.end.ns"
  fi
  rm -rf "$arm_dir/target"
  if test "$fault" = 1; then cp "$arm_dir/cjpm.toml.before" "$project/cjpm.toml"; fi
}

date -u +%s%N > "$root/start.ns"
uptime > "$root/uptime.before"
sha256sum /root/impl_astabi-behavior/candidate_bundle.a > "$root/archive-before.sha256"
if test -x "$official_elf"; then
  sha256sum "$official_elf" > "$root/official-elf.sha256"
  "$official_elf" > "$root/official.tsv" 2> "$root/official.stderr"
  printf '%s\n' "$?" > "$root/official.rc"
fi
run_arm baseline "$root/driver-baseline.cj" 0
run_arm perturbed "$root/driver-perturbed.cj" 1
run_arm restored "$root/driver-restored.cj" 0
for arm in baseline perturbed restored; do LC_ALL=C sort "$root/$arm/output.tsv" > "$root/$arm/output.sorted"; done
diff -u "$root/baseline/output.tsv" "$root/restored/output.tsv" > "$root/baseline-restored.diff"
printf '%s\n' "$?" > "$root/baseline-restored.diff.rc"
diff -u "$root/baseline/output.tsv" "$root/perturbed/output.tsv" > "$root/baseline-perturbed.diff"
printf '%s\n' "$?" > "$root/baseline-perturbed.diff.rc"
comm -13 "$root/baseline/output.sorted" "$root/perturbed/output.sorted" > "$root/perturbed.added"
comm -23 "$root/baseline/output.sorted" "$root/perturbed/output.sorted" > "$root/perturbed.removed"
diff -u "$root/official.tsv" "$root/baseline/output.tsv" > "$root/official-baseline.diff"
printf '%s\n' "$?" > "$root/official-baseline.diff.rc"
diff -u "$root/official.tsv" "$root/restored/output.tsv" > "$root/official-restored.diff"
printf '%s\n' "$?" > "$root/official-restored.diff.rc"
date -u +%s%N > "$root/end.ns"
uptime > "$root/uptime.after"

same_hash() {
  local left=$1 right=$2 left_hash right_hash
  left_hash=$(awk 'NR == 1 { print $1 }' "$left")
  right_hash=$(awk 'NR == 1 { print $1 }' "$right")
  test -n "$left_hash" && test "$left_hash" = "$right_hash"
}

single_space_n1() {
  local delta=$1
  test "$(/usr/bin/wc -l < "$delta")" -eq 1 &&
    test "$(awk -F '\t' 'NR == 1 { print $1 }' "$delta")" = space_n1
}

fail=0
check() {
  local label=$1 rc
  shift
  if "$@"; then
    printf 'PASS\t%s\n' "$label" >> "$root/assertions.log"
  else
    rc=$?
    printf 'FAIL\t%s\trc=%s\n' "$label" "$rc" >> "$root/assertions.log"
    fail=1
  fi
}

: > "$root/assertions.log"
check fault-compile test "$fault_compile_rc" -eq 0
check baseline-build test "$(cat "$root/baseline/build.rc")" -eq 0
check perturbed-build test "$(cat "$root/perturbed/build.rc")" -eq 0
check restored-build test "$(cat "$root/restored/build.rc")" -eq 0
check baseline-run test "$(cat "$root/baseline/run.rc")" -eq 0
check perturbed-run test "$(cat "$root/perturbed/run.rc")" -eq 0
check restored-run test "$(cat "$root/restored/run.rc")" -eq 0
check baseline-restored-equal test "$(cat "$root/baseline-restored.diff.rc")" -eq 0
check baseline-perturbed-different test "$(cat "$root/baseline-perturbed.diff.rc")" -ne 0
check perturbed-added-single-space-n1 single_space_n1 "$root/perturbed.added"
check perturbed-removed-single-space-n1 single_space_n1 "$root/perturbed.removed"
check official-baseline-equal test "$(cat "$root/official-baseline.diff.rc")" -eq 0
check official-restored-equal test "$(cat "$root/official-restored.diff.rc")" -eq 0
check baseline-restored-archive-hash-equal same_hash "$root/baseline/archive.sha256" "$root/restored/archive.sha256"
check baseline-restored-elf-hash-equal same_hash "$root/baseline/elf.sha256" "$root/restored/elf.sha256"
printf '%s\n' "$fail" > "$root/runner.rc"
exit "$fail"
