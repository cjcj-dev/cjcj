#!/bin/bash
set -u
set -o pipefail
r=/root/sym_cjcj_177_implement_r5836836450
arm=${1:?arm}
cd "$r/$arm" || exit 1
export CANGJIE_HOME="$r/sdk-host"
export LD_LIBRARY_PATH="$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/lib/linux_x86_64_cjnative:$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/tools/lib:/usr/lib/x86_64-linux-gnu"
export PATH="$CANGJIE_HOME/bin:$CANGJIE_HOME/tools/bin:$CANGJIE_HOME/third_party/llvm/bin:/usr/bin:/bin"
export cjHeapSize=24GB
export TMPDIR="$r/tmp"
mkdir -p "$r/evidence" "$r/tmp" "$r/products"
uptime > "$r/evidence/$arm-uptime-before"
nproc > "$r/evidence/$arm-jobs"
taskset -pc $$ > "$r/evidence/$arm-cpuset" || true
sha256sum "$CANGJIE_HOME/bin/cjc" "$CANGJIE_HOME/third_party/llvm/bin/llc" "$CANGJIE_HOME/third_party/llvm/lib/libLLVM-15.so" > "$r/evidence/$arm-input.sha256"
/usr/bin/grep -n 'compile-option' cjpm.toml > "$r/evidence/$arm-compile-option.txt"
/usr/bin/time -f 'wall=%e' cjpm build -j"$(nproc)" > "$r/evidence/$arm-build.log" 2>&1
rc=$?
echo "$rc" > "$r/evidence/$arm-build.rc"
uptime > "$r/evidence/$arm-uptime-after"
if [ "$rc" = 0 ]; then
  mkdir -p "$r/products/$arm"
  cp -a target/release/bin/cjcj::cjc "$r/products/$arm/cjcj-stage1"
  sha256sum "$r/products/$arm/cjcj-stage1" target/release/lib/cjcj::sema/libsema.so > "$r/evidence/$arm-products.sha256" || \
    sha256sum "$r/products/$arm/cjcj-stage1" > "$r/evidence/$arm-products.sha256"
fi
echo "BUILD arm=$arm rc=$rc"
tail -30 "$r/evidence/$arm-build.log"
exit "$rc"
