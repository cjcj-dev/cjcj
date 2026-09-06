#!/usr/bin/env bash
set -u
set -o pipefail

lane_root=/root/impl_cjcj_primitive_array_copy_dispatch
core_domain=${CORE_DOMAIN:?set CORE_DOMAIN to a current cjops windows result}
source_tree="$lane_root/candidate-src"
host_sdk=/root/.cjv/toolchains/nightly-1.3.0-alpha.20260904010027
compiler_cpp=/root/impl_fam_erased_dynpayload/build-copy/compiler
ast_support="$compiler_cpp/build/build/lib/libcangjie-ast-support.a"
work="$lane_root/work"
stage_sdk="$work/sdk-stage0"
evidence="$lane_root/evidence/candidate-build"
lane_tmp="$lane_root/tmp"

mkdir -p "$evidence" "$work" "$lane_tmp"
date -Ins > "$evidence/start.txt"
uptime > "$evidence/uptime-before.txt"
df -h /root > "$evidence/df-before.txt"
printf '%s\n' "$core_domain" > "$evidence/core-domain.txt"
git -C "$source_tree" rev-parse HEAD > "$evidence/source-head.txt"
git -C "$source_tree" status --short > "$evidence/source-status-before.txt"
git -C "$source_tree" diff -- packages/codegen/src/IRBuilder.cj > "$evidence/product.diff"
sha256sum "$source_tree/packages/codegen/src/IRBuilder.cj" > "$evidence/product-source.sha256"
sha256sum "$host_sdk/bin/cjc" "$ast_support" > "$evidence/build-inputs.sha256"

rm -f "$source_tree/runtime_shim/cjselfhost_llvmshim.o" \
  "$source_tree/runtime_shim/cjc_runtime_config.o"
(
  cd "$source_tree" || exit 1
  env CANGJIE_CPP_SRC="$compiler_cpp" CJCJ_COMMIT=9b5fe2f1244580c76a6e9ebf445663f9848601d4-dirty \
    npx --yes zx@8 runtime_shim/build_shim.mjs
) > "$evidence/shim-build.log" 2>&1
shim_rc=$?
printf '%s\n' "$shim_rc" > "$evidence/shim-build.rc"
if test "$shim_rc" -ne 0; then
  exit "$shim_rc"
fi
sha256sum "$source_tree/runtime_shim/cjselfhost_llvmshim.o" \
  "$source_tree/runtime_shim/cjc_runtime_config.o" > "$evidence/shim.sha256"

rm -rf "$stage_sdk"
mkdir -p "$stage_sdk"
cp -a "$host_sdk/." "$stage_sdk/"
install -Dm644 "$ast_support" "$stage_sdk/lib/linux_x86_64_cjnative/libcangjie-ast-support.a"
sha256sum "$stage_sdk/bin/cjc" \
  "$stage_sdk/lib/linux_x86_64_cjnative/libcangjie-ast-support.a" > "$evidence/sdk-stage0.sha256"

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
  install -m0755 "$product" "$work/cjcj-candidate"
  sha256sum "$work/cjcj-candidate" > "$evidence/cjcj-candidate.sha256"
  file "$work/cjcj-candidate" > "$evidence/cjcj-candidate.file"
  ldd "$work/cjcj-candidate" > "$evidence/cjcj-candidate.ldd" 2>&1
  stat -c '%y %n' "$work/cjcj-candidate" > "$evidence/cjcj-candidate.stat"
fi
git -C "$source_tree" status --short > "$evidence/source-status-after.txt"
uptime > "$evidence/uptime-after.txt"
df -h /root > "$evidence/df-after.txt"
date -Ins > "$evidence/end.txt"
exit "$build_rc"
