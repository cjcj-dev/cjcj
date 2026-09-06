#!/usr/bin/env bash
set -euo pipefail

ROOT=${1:-/root/impl_cjcj_zero_layout_copy_noop}
SDK=$ROOT/work/sdk-target-stdlib
CANDIDATE=$SDK/bin/cjc
CANDIDATE_ELF=$SDK/bin/cjcj-stage1
CUT_COMPILER=${CUT_COMPILER:-/root/impl_canonical_rebuild_r2/work/bootstrap/cjcj-stage1}
SOURCE=$ROOT/source/stdlib/libs/std/unittest/common
MODULES=$ROOT/source/stdlib/build/build/modules/linux_x86_64_cjnative
LIBS=$ROOT/source/stdlib/build/build/lib
GATE=$ROOT/source/cjcj/scripts/cjcjcg_zero_layout_copy_gate.py
OUT=$ROOT/evidence/validation
PACKAGE_SOURCE=$OUT/package-source
CUT_WRAPPER=$OUT/cut-cjc
CORES=${CORES:-0-15}
PLATFORM=linux_x86_64_cjnative
TARGET_LD="$SDK/runtime/lib/$PLATFORM:$SDK/lib/$PLATFORM:$SDK/third_party/llvm/lib:$SDK/tools/lib:/usr/lib/x86_64-linux-gnu"

mkdir -p "$OUT" "$ROOT/tmp-private"
rm -rf "$PACKAGE_SOURCE"
mkdir -p "$PACKAGE_SOURCE"
cp -a "$SOURCE/." "$PACKAGE_SOURCE/"
ulimit -c 0
ulimit -s unlimited
cp "$CANDIDATE" "$CUT_WRAPPER"
sed -i "s#^exec .*#exec $CUT_COMPILER \"\$@\"#" "$CUT_WRAPPER"
chmod +x "$CUT_WRAPPER"

compile_package() {
    local compiler=$1
    local arm=$2
    local arm_out=$OUT/$arm/out
    mkdir -p "$arm_out/temps"
    set +e
    taskset -c "$CORES" env -i HOME=/root TMPDIR="$ROOT/tmp-private" CANGJIE_HOME="$SDK" \
        LD_LIBRARY_PATH="$TARGET_LD" CANGJIE_PATH="$MODULES" LIBRARY_PATH="$LIBS" \
        PATH="$SDK/bin:$SDK/tools/bin:$SDK/third_party/llvm/bin:/usr/bin:/bin" \
        cjHeapSize=24GB cjStackSize=1GB "$compiler" --no-sub-pkg -g --apc=1 \
        --output-type=staticlib -p "$PACKAGE_SOURCE" --output "$arm_out/std.unittest.common.a" \
        -j1 --save-temps="$arm_out/temps" -O2 >"$arm_out/compile.stdout" 2>"$arm_out/compile.stderr"
    local rc=$?
    set -e
    printf '%s\n' "$rc" >"$arm_out/compile.rc"
    if test -f "$arm_out/std.unittest.common.a"; then
        sha256sum "$arm_out/std.unittest.common.a" >"$arm_out/archive.sha256"
    fi
}

date -Ins >"$OUT/uptime.before"
uptime >>"$OUT/uptime.before"
printf 'CORES=%s\n' "$CORES" >"$OUT/recipe.txt"
printf 'CANDIDATE=%s\nCUT_COMPILER=%s\nSDK=%s\n' "$CANDIDATE" "$CUT_COMPILER" "$SDK" >>"$OUT/recipe.txt"
sha256sum "$CANDIDATE" "$CANDIDATE_ELF" "$CUT_WRAPPER" "$CUT_COMPILER" \
    "$SDK/runtime/lib/$PLATFORM/libcangjie-runtime.so" \
    "$SDK/runtime/lib/$PLATFORM/libboundscheck.so" \
    "$ROOT/source/cjcj/runtime_shim/cjselfhost_llvmshim.cpp" >"$OUT/identities.sha256"

compile_package "$CANDIDATE" candidate
compile_package "$CUT_WRAPPER" cut
compile_package "$CANDIDATE" restored

set +e
taskset -c "$CORES" env -i HOME=/root TMPDIR="$ROOT/tmp-private" CANGJIE_HOME="$SDK" \
    LD_LIBRARY_PATH="$TARGET_LD" PATH="$SDK/bin:$SDK/tools/bin:$SDK/third_party/llvm/bin:/usr/bin:/bin" \
    python3 "$GATE" --compiler "$CANDIDATE" --source-root "$ROOT/source/cjcj" \
    --invalid-rc "$OUT/cut/out/compile.rc" --invalid-log "$OUT/cut/out/compile.stderr" \
    --out "$OUT/fixtures" >"$OUT/gate.log" 2>&1
gate_rc=$?
set -e
printf '%s\n' "$gate_rc" >"$OUT/gate.rc"

candidate_rc=$(cat "$OUT/candidate/out/compile.rc")
cut_rc=$(cat "$OUT/cut/out/compile.rc")
restored_rc=$(cat "$OUT/restored/out/compile.rc")
test "$candidate_rc" = 0
test "$cut_rc" != 0
test "$restored_rc" = 0
test -f "$OUT/candidate/out/std.unittest.common.a"
test -f "$OUT/restored/out/std.unittest.common.a"
/usr/bin/grep -Fq 'llvm.cj.copy.no.ref.struct size must be a nonzero constant' \
    "$OUT/cut/out/compile.stderr"
test "$gate_rc" = 0

date -Ins >"$OUT/uptime.after"
uptime >>"$OUT/uptime.after"
printf 'ZERO_LAYOUT_VALIDATION_OK candidate=%s cut=%s restored=%s gate=%s\n' \
    "$candidate_rc" "$cut_rc" "$restored_rc" "$gate_rc"
