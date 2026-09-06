#!/usr/bin/env bash
set -u
set -o pipefail

arm=${1:?arm required}
core_domain=${CORE_DOMAIN:?set CORE_DOMAIN to a current cjops windows result}
lane_root=/root/impl_cjcj_primitive_array_copy_dispatch
source_tree="$lane_root/candidate-src"
stage_sdk="$lane_root/work/sdk-stage0"
lane_tmp="$lane_root/tmp"
evidence="$lane_root/evidence/build-$arm"

rm -rf "$evidence"
mkdir -p "$evidence"
date -Ins > "$evidence/start.txt"
uptime > "$evidence/uptime-before.txt"
df -h /root > "$evidence/df-before.txt"
printf '%s\n' "$core_domain" > "$evidence/core-domain.txt"
git -C "$source_tree" rev-parse HEAD > "$evidence/source-head.txt"
git -C "$source_tree" status --short > "$evidence/source-status-before.txt"
git -C "$source_tree" diff -- packages/codegen/src/IRBuilder.cj > "$evidence/product.diff"
sha256sum "$source_tree/packages/codegen/src/IRBuilder.cj" > "$evidence/product-source.sha256"
stat -c '%y %n' "$source_tree/packages/codegen/src/IRBuilder.cj" > "$evidence/product-source.stat"
sha256sum "$0" > "$evidence/build-recipe.sha256"
sha256sum "$stage_sdk/bin/cjc" \
  "$stage_sdk/lib/linux_x86_64_cjnative/libcangjie-ast-support.a" \
  "$source_tree/runtime_shim/cjselfhost_llvmshim.o" \
  "$source_tree/runtime_shim/cjc_runtime_config.o" > "$evidence/build-inputs.sha256"

rm -rf "$source_tree/target"
cp -a "$source_tree/cjpm.toml" "$source_tree/cjpm.toml.O2bak"
sed -i 's/compile-option = "-O2"/compile-option = "-O1"/' "$source_tree/cjpm.toml"
library_path="$stage_sdk/runtime/lib/linux_x86_64_cjnative:$stage_sdk/lib/linux_x86_64_cjnative:$stage_sdk/third_party/llvm/lib:$stage_sdk/tools/lib:/usr/lib/x86_64-linux-gnu"
env -i HOME=/root USER=root TMPDIR="$lane_tmp" CANGJIE_HOME="$stage_sdk" \
  PATH="$stage_sdk/bin:$stage_sdk/tools/bin:$stage_sdk/third_party/llvm/bin:/usr/bin:/bin" \
  LD_LIBRARY_PATH="$library_path" cjHeapSize=24GB \
  taskset -c "$core_domain" bash -c 'cd "$1" && exec cjpm build' bash "$source_tree" \
  > "$evidence/build.log" 2>&1
build_rc=$?
printf '%s\n' "$build_rc" > "$evidence/build.rc"
mv -f "$source_tree/cjpm.toml.O2bak" "$source_tree/cjpm.toml"

product=""
for candidate in "$source_tree/target/release/bin/cjcj::cjc" \
  "$source_tree/target/release/bin/cjc" "$source_tree/target/release/bin/cjcj"; do
  if test -x "$candidate"; then
    product="$candidate"
    break
  fi
done
ls -l "$source_tree/target/release/bin" > "$evidence/bin-dir.txt" 2>&1 || true
if test -n "$product"; then
  install -m0755 "$product" "$lane_root/work/cjcj-$arm"
  sha256sum "$lane_root/work/cjcj-$arm" > "$evidence/cjcj-$arm.sha256"
  file "$lane_root/work/cjcj-$arm" > "$evidence/cjcj-$arm.file"
  ldd "$lane_root/work/cjcj-$arm" > "$evidence/cjcj-$arm.ldd" 2>&1
  stat -c '%y %n' "$lane_root/work/cjcj-$arm" > "$evidence/cjcj-$arm.stat"
fi
git -C "$source_tree" status --short > "$evidence/source-status-after.txt"
uptime > "$evidence/uptime-after.txt"
df -h /root > "$evidence/df-after.txt"
date -Ins > "$evidence/end.txt"
exit "$build_rc"
