#!/usr/bin/env bash
# Purpose: exercise bootstrap contract and fault arms; caller: test_bootstrap.sh:2
# Focused contract and fault-arm tests for bootstrap.sh.
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PRODUCT="${BOOTSTRAP_PRODUCT:-$ROOT/bootstrap.sh}"
SDK_PRODUCT="${SDK_BUILD_PRODUCT:-$ROOT/sdk_build.sh}"
TMP=

fail() {
  echo "TEST-FAIL [$1] $2" >&2
  exit 1
}

cleanup() {
  [ -n "$TMP" ] && [ -d "$TMP" ] && rm -rf "$TMP"
}
trap cleanup EXIT

new_tmp() {
  TMP=$(mktemp -d)
}

refresh_tuple_sums() {
  (
    cd "$TMP/colour-tuple" || exit 1
    find . -type f ! -name SHA256SUMS -print | sort | xargs sha256sum > SHA256SUMS
  )
}

make_colour_tuple() {
  mkdir -p "$TMP/colour-tuple/bin" "$TMP/colour-tuple/lib" "$TMP/colour-tuple/fixed-llc"
  cp /bin/true "$TMP/colour-tuple/bin/opt"
  cp /bin/true "$TMP/colour-tuple/bin/llc"
  printf 'CJLLVM-COMMIT:1111111111111111111111111111111111111111\n' >> "$TMP/colour-tuple/bin/opt"
  printf 'shim\n' > "$TMP/colour-tuple/fixed-llc/cjselfhost_llvmshim.o"
  printf 'llc gzip fixture\n' > "$TMP/colour-tuple/fixed-llc/llc.gz"
  printf 'opt gzip fixture\n' > "$TMP/colour-tuple/fixed-llc/opt.gz"
  printf 'fixed llc\n' > "$TMP/colour-tuple/fixed-llc/llvm-tools.manifest"
  printf 'static LLVM tuple\n' > "$TMP/colour-tuple/lib/STATIC_LLVM.txt"
  printf 'LLVM_SHA=1111111111111111111111111111111111111111\n' > "$TMP/colour-tuple/MANIFEST"
  printf '%s\n' \
    'namespace llvm {' \
    'bool isCJTypedReadHelperCandidate(void *) { return true; }' \
    '}' > "$TMP/colour.cpp"
  c++ -shared -fPIC "$TMP/colour.cpp" -o "$TMP/colour-libLLVM-15.so"
  refresh_tuple_sums
}

make_dry_fixture() {
  new_tmp
  mkdir -p "$TMP/base/bin" "$TMP/base/third_party/llvm/bin" "$TMP/src" "$TMP/stdsrc" "$TMP/host-rt" "$TMP/colour-rt" \
    "$TMP/cpp-src/third_party/llvm-project/llvm/include" \
    "$TMP/cpp-src/build/build/third_party/llvm/include" \
    "$TMP/cpp-src/build/build/include" "$TMP/cpp-src/build/build/schema"
  for rel in third_party/llvm-project/llvm/include build/build/third_party/llvm/include \
    build/build/include build/build/schema; do
    printf 'fixture\n' > "$TMP/cpp-src/$rel/fixture.h"
  done
  printf 'base\n' > "$TMP/base/bin/cjc"
  cp /bin/true "$TMP/base/third_party/llvm/bin/opt"
  printf 'compile-option = "-O2"\n' > "$TMP/src/cjpm.toml"
  mkdir -p "$TMP/base/tools/bin"
  cp /bin/true "$TMP/base/tools/bin/cjpm"
  printf 'source\n' > "$TMP/src/main.cj"
  printf '#!/usr/bin/env python3\n' > "$TMP/stdsrc/build.py"
  printf 'ast\n' > "$TMP/ast.a"
  printf 'int host_symbol;\n' > "$TMP/host.c"
  cc -shared -fPIC "$TMP/host.c" -o "$TMP/libLLVM-15.so"
  make_colour_tuple
  printf 'host runtime\n' > "$TMP/host-rt/libcangjie-runtime.so"
  printf 'colour runtime\n' > "$TMP/colour-rt/libcangjie-runtime.so"
  HOST_SHA=$(sha256sum "$TMP/libLLVM-15.so" | awk '{print $1}')
  AST_SHA=$(sha256sum "$TMP/ast.a" | awk '{print $1}')
  COLOUR_SHA=1111111111111111111111111111111111111111
  export HOST_SHA AST_SHA COLOUR_SHA
}

dry_run() {
  local host_sha="${1:-$HOST_SHA}" ast_sha="${2:-$AST_SHA}"
  bash "$PRODUCT" \
    --work "$TMP/work" --src "$TMP/src" --cjcj-sha aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    --stdsrc "$TMP/stdsrc" --cpp-src "$TMP/cpp-src" --base "$TMP/base" \
    --host-llvm-so "$TMP/libLLVM-15.so" --host-llvm-sha256 "$host_sha" \
    --ast-support "$TMP/ast.a" --ast-support-sha256 "$ast_sha" \
    --colour-tuple "$TMP/colour-tuple" --colour-llvm-sha "$COLOUR_SHA" \
    --colour-rt "$TMP/colour-rt" --host-rt "$TMP/host-rt" \
    --stage all --dry-run
}

check_count() {
  local label="$1" expected="$2" pattern="$3" file="$4" count
  count=$(/usr/bin/grep -c -- "$pattern" "$file" || true)
  [ "$count" -eq "$expected" ] || fail "$label" "pattern count=$count expected=$expected: $pattern"
}

check_shim_call_count() {
  check_count SHIM 2 'CMD shim build label=' "$1"
}

check_dry_contract() {
  local log="$1"
  check_count A1 2 'shape=planned Int64.ti>1 FFI-archives>0' "$log"
  check_count A1 1 'FFI-set-equals=' "$log"
  check_count A2 1 'cjcj-stage1 --version' "$log"
  check_count A2 1 'cjcj-stage2 --version' "$log"
  check_count A3 1 'ASSERT stage1-compiler executable=planned' "$log"
  check_count CJPM 4 'tools/bin/cjpm' "$log"
  check_count CJPM 2 'cjpm build' "$log"
  check_count CJPM 1 'cjpm build -j 1' "$log"
  check_count CJPM 1 'compile-option = "-O1"' "$log"
  check_count CJPM 1 'ASSERT compile-option-o1 planned' "$log"
  check_count CJPM 2 'ISOLATE cjcj-src from=' "$log"
  check_count CJPM 1 'CMD cjpm build bin=' "$log"
  check_count CJPM 1 'CMD cjpm build -j 1 bin=' "$log"
  check_count CJPM 1 'heap=20GB' "$log"
  check_shim_call_count "$log"
  check_count SHIM 1 'CMD shim build label=stage0 .*source-object=source .*sdk=.*/sdk-stage0 .*runtime=.*/host-rt' "$log"
  check_count SHIM 1 'CMD shim build label=stage1 .*source-object=.*/sdk-stage1/third_party/llvm/fixed-llc/cjselfhost_llvmshim.o .*sdk=.*/sdk-stage1 .*runtime=.*/colour-rt' "$log"
  check_count SHIM 2 'CJCJ_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$log"
  check_count SHIM 1 'CJCJ_LLVM_SHIM_O=.*/sdk-stage1/third_party/llvm/fixed-llc/cjselfhost_llvmshim.o' "$log"
  check_count SHIM 2 'OUTPUT stage[01]-shim-cpp .*sha256=planned' "$log"
  check_count SHIM 2 'OUTPUT stage[01]-shim-config .*sha256=planned' "$log"
  check_count A4 2 'rm\\ -rf\\ build/build' "$log"
  check_count A4 2 '--target-lib' "$log"
  check_count A4 4 'CMD env -i HOME=/root TMPDIR=.*/work/tmp-private CANGJIE_HOME=.*bash -c' "$log"
  check_count A4 4 'BUILD-ENV planned HOME=/root TMPDIR=.*/work/tmp-private' "$log"
  check_count LLVM-SO 1 'sdk_build.sh .*--host --llvm-so .*libLLVM-15.so' "$log"
  check_count LLVM-SO 1 'ASSERT installed-host-llvm-so sha256=planned' "$log"
  check_count LLVM-TUPLE 1 'sdk_build.sh .*--target .*--llvm-tuple .*colour-tuple' "$log"
  check_count HOST-RT 1 '--verify-host-rt .*/host-rt' "$log"
  check_count HOST-RUNNER 1 'stage1_host_runner.sh .*/sdk-stage1 .*/sdk-stage0 .*/host-rt' "$log"
  check_count LLVM-TUPLE 8 'ASSERT installed-colour-tuple sha256=planned' "$log"
  check_count LLVM-RULER 2 'ruler=readelf--dyn-syms symbol=llvm::isCJTypedReadHelperCandidate' "$log"
  check_count LLVM-RULER 1 'ASSERT official-opt-zero ruler=strings .* hits=0' "$log"
  check_count LLVM-RULER 2 'ASSERT colour-opt-stamp ruler=strings .* hits=1' "$log"
}

make_sdk_fixture() {
  local base="$TMP/sdk-base"
  mkdir -p "$base/bin" "$base/tools/bin" "$base/third_party/llvm/bin" "$base/third_party/llvm/lib" \
    "$base/runtime/lib/linux_x86_64_cjnative" "$base/lib/linux_x86_64_cjnative"
  cp /bin/true "$base/bin/cjc"
  cp /bin/true "$base/tools/bin/cjpm"
  cp /bin/true "$base/third_party/llvm/bin/llc"
  cp /bin/true "$base/third_party/llvm/bin/opt"
  printf 'int base_llvm;\n' > "$TMP/base-llvm.c"
  cc -shared -fPIC "$TMP/base-llvm.c" -o "$base/third_party/llvm/lib/libLLVM-15.so"
  printf 'int host_runtime;\n' > "$TMP/host-runtime.c"
  cc -shared -fPIC "$TMP/host-runtime.c" -o "$base/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so"
  cc -shared -fPIC "$TMP/host-runtime.c" -o "$base/runtime/lib/linux_x86_64_cjnative/libboundscheck.so"
  cc -c "$TMP/host-runtime.c" -o "$TMP/host-runtime.o"
  ar rcs "$base/lib/linux_x86_64_cjnative/libcangjie-runtime.a" "$TMP/host-runtime.o"
  printf '%s\n' '#!/usr/bin/env bash' 'export PATH="$(dirname "${BASH_SOURCE[0]}")/bin:$PATH"' > "$base/envsetup.sh"
}

run_sdk_so() {
  local product="$1" to="$2"
  bash "$product" --from "$TMP/sdk-base" --to "$to" --host \
    --llvm-so "$TMP/libLLVM-15.so" --force
}

run_sdk_tuple() {
  local product="$1" to="$2"
  bash "$product" --from "$TMP/sdk-base" --to "$to" --host \
    --llvm-tuple "$TMP/colour-tuple" --force
}

make_runtime_payload() {
  local root="$1" sha="$2" tuple="${3:-}" dyn="$1" static=''
  if [ -n "$tuple" ]; then
    dyn="$root/runtime/lib/$tuple"
    static="$root/lib/$tuple"
  fi
  mkdir -p "$dyn"
  [ -z "$static" ] || mkdir -p "$static"
  printf '%s\n' \
    "__attribute__((used)) const char cjrt_commit[] = \"CJRT-COMMIT:$sha\";" \
    'int g_cjLoadBadMask = 1;' > "$TMP/target-runtime.c"
  cc -shared -fPIC "$TMP/target-runtime.c" -o "$dyn/libcangjie-runtime.so"
  printf 'int boundscheck_fixture;\n' > "$TMP/boundscheck.c"
  cc -shared -fPIC "$TMP/boundscheck.c" -o "$dyn/libboundscheck.so"
  if [ -n "$static" ]; then
    cc -c "$TMP/target-runtime.c" -o "$TMP/target-runtime.o"
    ar rcs "$static/libcangjie-runtime.a" "$TMP/target-runtime.o"
  fi
}

run_sdk_runtime() {
  local product="$1" source="$2" to="$3"
  bash "$product" --from "$TMP/sdk-base" --to "$to" --target --runtime "$source" --force
}

run_sdk_runtime_checked() {
  local label="$1" product="$2" source="$3" to="$4" log rc
  log="$TMP/$label-sdk-build.log"
  if run_sdk_runtime "$product" "$source" "$to" > "$log" 2>&1; then
    rc=0
  else
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    sed -n '1,120p' "$log" >&2
    fail "$label" "sdk_build rc=$rc log=$log"
  fi
}

positive_runtime_layouts() {
  local flat_sha=2222222222222222222222222222222222222222 tuple=linux_x86_64_cjnative
  new_tmp
  make_sdk_fixture
  make_runtime_payload "$TMP/$flat_sha" "$flat_sha"
  run_sdk_runtime_checked runtime-flat "$SDK_PRODUCT" "$TMP/$flat_sha" "$TMP/sdk-flat"
  tail -n 1 "$TMP/runtime-flat-sdk-build.log" | /usr/bin/grep -q '^SDK-BUILD-OK ' ||
    fail runtime-flat 'SDK-BUILD-OK was not the final verdict token'
  cmp -s "$TMP/$flat_sha/libcangjie-runtime.so" "$TMP/sdk-flat/runtime/lib/$tuple/libcangjie-runtime.so" ||
    fail runtime-flat 'runtime SO was not installed from flat sodepot'
  cmp -s "$TMP/$flat_sha/libboundscheck.so" "$TMP/sdk-flat/runtime/lib/$tuple/libboundscheck.so" ||
    fail runtime-flat 'boundscheck SO was not installed from flat sodepot'
  cmp -s "$TMP/sdk-base/lib/$tuple/libcangjie-runtime.a" "$TMP/sdk-flat/lib/$tuple/libcangjie-runtime.a" ||
    fail runtime-flat 'flat shared closure unexpectedly changed the base static archive'
  make_runtime_payload "$TMP/runtime-install" 3333333333333333333333333333333333333333 "$tuple"
  run_sdk_runtime_checked runtime-nested "$SDK_PRODUCT" "$TMP/runtime-install" "$TMP/sdk-nested"
  cmp -s "$TMP/runtime-install/runtime/lib/$tuple/libcangjie-runtime.so" "$TMP/sdk-nested/runtime/lib/$tuple/libcangjie-runtime.so" ||
    fail runtime-nested 'runtime SO was not installed from nested prefix'
  cmp -s "$TMP/runtime-install/lib/$tuple/libcangjie-runtime.a" "$TMP/sdk-nested/lib/$tuple/libcangjie-runtime.a" ||
    fail runtime-nested 'runtime archive was not installed from nested prefix'
  echo 'PASS flat and nested runtime layouts'
}

positive_runtime_layout_symlink_nested_only() {
  local sha=9999999999999999999999999999999999999999 tuple=linux_x86_64_cjnative
  new_tmp
  make_sdk_fixture
  make_runtime_payload "$TMP/real-install" "$sha" "$tuple"
  mkdir -p "$TMP/link-install/runtime/lib/$tuple"
  ln -s "$TMP/real-install/runtime/lib/$tuple/libcangjie-runtime.so" \
    "$TMP/link-install/runtime/lib/$tuple/libcangjie-runtime.so"
  run_sdk_runtime_checked runtime-nested-symlink "$SDK_PRODUCT" "$TMP/link-install" "$TMP/sdk-nested-symlink"
  cmp -s "$TMP/real-install/runtime/lib/$tuple/libcangjie-runtime.so" \
    "$TMP/sdk-nested-symlink/runtime/lib/$tuple/libcangjie-runtime.so" ||
    fail runtime-nested-symlink 'resolved nested symlink SO was not installed'
  echo 'PASS nested-only runtime SO symlink rc=0'
}

positive_runtime_layout_symlink_flat_only() {
  local sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa tuple=linux_x86_64_cjnative
  new_tmp
  make_sdk_fixture
  make_runtime_payload "$TMP/real-flat" "$sha"
  mkdir -p "$TMP/$sha"
  ln -s "$TMP/real-flat/libcangjie-runtime.so" "$TMP/$sha/libcangjie-runtime.so"
  ln -s "$TMP/real-flat/libboundscheck.so" "$TMP/$sha/libboundscheck.so"
  run_sdk_runtime_checked runtime-flat-symlink "$SDK_PRODUCT" "$TMP/$sha" "$TMP/sdk-flat-symlink"
  cmp -s "$TMP/real-flat/libcangjie-runtime.so" \
    "$TMP/sdk-flat-symlink/runtime/lib/$tuple/libcangjie-runtime.so" ||
    fail runtime-flat-symlink 'resolved flat symlink SO was not installed'
  echo 'PASS flat-only runtime SO symlink rc=0'
}

fault_runtime_dual_layout() {
  local flat_sha=6666666666666666666666666666666666666666 nested_sha=7777777777777777777777777777777777777777
  local tuple=linux_x86_64_cjnative
  new_tmp
  make_sdk_fixture
  make_runtime_payload "$TMP/$flat_sha" "$flat_sha"
  make_runtime_payload "$TMP/$flat_sha" "$nested_sha" "$tuple"
  run_sdk_runtime "$SDK_PRODUCT" "$TMP/$flat_sha" "$TMP/sdk-dual"
}

fault_runtime_dual_missing_bounds() {
  local flat_sha=1212121212121212121212121212121212121212 nested_sha=3434343434343434343434343434343434343434
  local tuple=linux_x86_64_cjnative
  new_tmp
  make_sdk_fixture
  make_runtime_payload "$TMP/$flat_sha" "$flat_sha"
  rm "$TMP/$flat_sha/libboundscheck.so"
  make_runtime_payload "$TMP/$flat_sha" "$nested_sha" "$tuple"
  run_sdk_runtime "$SDK_PRODUCT" "$TMP/$flat_sha" "$TMP/sdk-dual-missing-bounds"
}

fault_runtime_dual_multiple_nested() {
  local flat_sha=5656565656565656565656565656565656565656 nested_sha=7878787878787878787878787878787878787878
  local other_sha=9090909090909090909090909090909090909090 tuple=linux_x86_64_cjnative
  new_tmp
  make_sdk_fixture
  make_runtime_payload "$TMP/$flat_sha" "$flat_sha"
  make_runtime_payload "$TMP/$flat_sha" "$nested_sha" "$tuple"
  make_runtime_payload "$TMP/$flat_sha" "$other_sha" linux_aarch64_cjnative
  run_sdk_runtime "$SDK_PRODUCT" "$TMP/$flat_sha" "$TMP/sdk-dual-multiple-nested"
}

fault_runtime_layout_symlink_nested() {
  local flat_sha=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb nested_sha=cccccccccccccccccccccccccccccccccccccccc
  local tuple=linux_x86_64_cjnative
  new_tmp
  make_sdk_fixture
  make_runtime_payload "$TMP/$flat_sha" "$flat_sha"
  make_runtime_payload "$TMP/real-nested" "$nested_sha" "$tuple"
  mkdir -p "$TMP/$flat_sha/runtime/lib/$tuple"
  ln -s "$TMP/real-nested/runtime/lib/$tuple/libcangjie-runtime.so" \
    "$TMP/$flat_sha/runtime/lib/$tuple/libcangjie-runtime.so"
  run_sdk_runtime "$SDK_PRODUCT" "$TMP/$flat_sha" "$TMP/sdk-dual-nested-symlink"
}

fault_runtime_layout_symlink_flat() {
  local flat_sha=dddddddddddddddddddddddddddddddddddddddd nested_sha=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
  local tuple=linux_x86_64_cjnative
  new_tmp
  make_sdk_fixture
  make_runtime_payload "$TMP/real-flat" "$flat_sha"
  mkdir -p "$TMP/$flat_sha"
  ln -s "$TMP/real-flat/libcangjie-runtime.so" "$TMP/$flat_sha/libcangjie-runtime.so"
  ln -s "$TMP/real-flat/libboundscheck.so" "$TMP/$flat_sha/libboundscheck.so"
  make_runtime_payload "$TMP/$flat_sha" "$nested_sha" "$tuple"
  run_sdk_runtime "$SDK_PRODUCT" "$TMP/$flat_sha" "$TMP/sdk-dual-flat-symlink"
}

fault_runtime_layout_inner_rc() {
  local flat_sha=8888888888888888888888888888888888888888
  new_tmp
  printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$TMP/sdk-build-rc1.sh"
  chmod +x "$TMP/sdk-build-rc1.sh"
  make_sdk_fixture
  make_runtime_payload "$TMP/$flat_sha" "$flat_sha"
  run_sdk_runtime_checked runtime-flat "$TMP/sdk-build-rc1.sh" "$TMP/$flat_sha" "$TMP/sdk-flat"
}

check_runtime_layouts() {
  local log rc
  positive_runtime_layouts
  positive_runtime_layout_symlink_nested_only
  positive_runtime_layout_symlink_flat_only

  log=$(mktemp)
  rc=0
  BOOTSTRAP_PRODUCT="$PRODUCT" SDK_BUILD_PRODUCT="$SDK_PRODUCT" \
    bash "$0" fault-runtime-dual-layout > "$log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail runtime-dual 'flat+nested layout was accepted'
  /usr/bin/grep -Eq 'runtime 布局歧义: flat=.*/6666666666666666666666666666666666666666/libcangjie-runtime.so stamp=CJRT-COMMIT:6666666666666666666666666666666666666666 nested=.*/6666666666666666666666666666666666666666/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so stamp=CJRT-COMMIT:7777777777777777777777777777777777777777' "$log" ||
    fail runtime-dual "diagnostic omitted both paths/stamps; log=$log"
  echo "PASS dual runtime layout rejected rc=$rc"

  rc=0
  BOOTSTRAP_PRODUCT="$PRODUCT" SDK_BUILD_PRODUCT="$SDK_PRODUCT" \
    bash "$0" fault-runtime-dual-missing-bounds > "$log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail runtime-dual-missing-bounds 'flat without bounds+nested layout was accepted'
  /usr/bin/grep -Eq 'runtime 布局歧义: flat=.*/1212121212121212121212121212121212121212/libcangjie-runtime.so stamp=CJRT-COMMIT:1212121212121212121212121212121212121212 nested=.*/1212121212121212121212121212121212121212/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so stamp=CJRT-COMMIT:3434343434343434343434343434343434343434' "$log" ||
    fail runtime-dual-missing-bounds "diagnostic omitted flat/nested paths; log=$log"
  echo "PASS dual runtime missing bounds diagnostic lists both layouts rc=$rc"

  rc=0
  BOOTSTRAP_PRODUCT="$PRODUCT" SDK_BUILD_PRODUCT="$SDK_PRODUCT" \
    bash "$0" fault-runtime-dual-multiple-nested > "$log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail runtime-dual-multiple-nested 'flat+multiple nested layouts were accepted'
  /usr/bin/grep -Eq 'nested=.*/runtime/lib/linux_aarch64_cjnative/libcangjie-runtime.so stamp=CJRT-COMMIT:9090909090909090909090909090909090909090 nested=.*/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so stamp=CJRT-COMMIT:7878787878787878787878787878787878787878' "$log" ||
    fail runtime-dual-multiple-nested "diagnostic omitted a nested tuple; log=$log"
  echo "PASS dual runtime diagnostic lists every nested tuple rc=$rc"

  rc=0
  BOOTSTRAP_PRODUCT="$PRODUCT" SDK_BUILD_PRODUCT="$SDK_PRODUCT" \
    bash "$0" fault-runtime-layout-symlink-nested > "$log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail runtime-dual-nested-symlink 'flat+nested symlink layout was accepted'
  /usr/bin/grep -Eq 'runtime 布局歧义: flat=.*/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/libcangjie-runtime.so stamp=CJRT-COMMIT:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb nested=.*/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so stamp=CJRT-COMMIT:cccccccccccccccccccccccccccccccccccccccc' "$log" ||
    fail runtime-dual-nested-symlink "diagnostic omitted symlink path/stamp; log=$log"
  echo "PASS dual runtime nested SO symlink rejected rc=$rc"

  rc=0
  BOOTSTRAP_PRODUCT="$PRODUCT" SDK_BUILD_PRODUCT="$SDK_PRODUCT" \
    bash "$0" fault-runtime-layout-symlink-flat > "$log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail runtime-dual-flat-symlink 'symlink flat+nested layout was accepted'
  /usr/bin/grep -Eq 'runtime 布局歧义: flat=.*/dddddddddddddddddddddddddddddddddddddddd/libcangjie-runtime.so stamp=CJRT-COMMIT:dddddddddddddddddddddddddddddddddddddddd nested=.*/dddddddddddddddddddddddddddddddddddddddd/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so stamp=CJRT-COMMIT:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee' "$log" ||
    fail runtime-dual-flat-symlink "diagnostic omitted symlink path/stamp; log=$log"
  echo "PASS dual runtime flat SO symlink rejected rc=$rc"

  rc=0
  BOOTSTRAP_PRODUCT="$PRODUCT" SDK_BUILD_PRODUCT="$SDK_PRODUCT" \
    bash "$0" fault-runtime-layout-inner-rc > "$log" 2>&1 || rc=$?
  [ "$rc" -ne 0 ] || fail runtime-inner-rc 'inner rc=1 was swallowed by layout self-test'
  /usr/bin/grep -q 'TEST-FAIL \[runtime-flat\] sdk_build rc=1 log=' "$log" ||
    fail runtime-inner-rc "outer failure omitted inner rc=1; log=$log"
  echo "PASS runtime layout inner rc=1 propagated rc=$rc"
  rm -f "$log"
}

fault_runtime_stamp() {
  local expected=4444444444444444444444444444444444444444 actual=5555555555555555555555555555555555555555
  new_tmp
  make_sdk_fixture
  make_runtime_payload "$TMP/$expected" "$actual"
  run_sdk_runtime "$SDK_PRODUCT" "$TMP/$expected" "$TMP/sdk-bad-stamp"
}

make_std_fixture() {
  local prefix="$1"
  mkdir -p "$prefix/lib/linux_x86_64_cjnative" "$prefix/runtime/lib/linux_x86_64_cjnative" "$prefix/lib"
  : > "$prefix/lib/linux_x86_64_cjnative/libcangjie-std-core.a"
  : > "$prefix/runtime/lib/linux_x86_64_cjnative/libcangjie-std-core.so"
  : > "$prefix/lib/linux_x86_64_cjnative/libnetFFI.a"
  : > "$prefix/lib/libstdFFI.so"
}

make_fake_nm() {
  mkdir -p "$TMP/fakebin"
  # shellcheck disable=SC2016 # These variables belong to the generated fixture.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'for arg in "$@"; do' \
    '  case "$arg" in' \
    '    *libcangjie-std-core.a) echo "$arg: 0 T Int64.ti";;' \
    '    *libcangjie-std-core.so) [ "${BOOTSTRAP_TEST_INT64_COUNT:-2}" -gt 1 ] && echo "$arg: 0 T Int64.ti";;' \
    '  esac' \
    'done' > "$TMP/fakebin/nm"
  chmod +x "$TMP/fakebin/nm"
}

run_shape_check() {
  local count="$1"
  make_std_fixture "$TMP/std0"
  make_std_fixture "$TMP/std1"
  make_fake_nm
  PATH="$TMP/fakebin:$PATH" BOOTSTRAP_TEST_INT64_COUNT="$count" \
    bash -c 'source "$1"; STAGE=test-A1; DRY=0; assert_std_install_shape "$2" "$3" stdlib-stage2' \
      bash "$PRODUCT" "$TMP/std1" "$TMP/std0"
}

make_isolation_fixture() {
  local root="$TMP/isolation" sdk="$TMP/isolation/sdk" prefix="$TMP/isolation/std"
  mkdir -p "$root/src/build/build" "$sdk/bin" "$sdk/runtime/lib/linux_x86_64_cjnative" "$root/rt"
  printf 'runtime\n' > "$root/rt/libcangjie-runtime.so"
  printf '%s\n' \
    'import os, pathlib, sys' \
    "expected_sdk = '$sdk'" \
    'if os.environ.get("LEAK_ME"):' \
    '    raise SystemExit(44)' \
    'if os.environ.get("CANGJIE_HOME") != expected_sdk:' \
    '    raise SystemExit(45)' \
    'if len(sys.argv) > 1 and sys.argv[1] == "build":' \
    '    target = next((x.split("=", 1)[1] for x in sys.argv if x.startswith("--target-lib=")), "")' \
    '    if target != expected_sdk + "/runtime/lib/linux_x86_64_cjnative":' \
    '        raise SystemExit(46)' \
    'if len(sys.argv) > 1 and sys.argv[1] == "install":' \
    '    prefix = pathlib.Path(sys.argv[sys.argv.index("--prefix") + 1])' \
    '    files = [' \
    '        prefix / "lib/linux_x86_64_cjnative/libcangjie-std-core.a",' \
    '        prefix / "runtime/lib/linux_x86_64_cjnative/libcangjie-std-core.so",' \
    '        prefix / "lib/linux_x86_64_cjnative/libnetFFI.a",' \
    '        prefix / "lib/libstdFFI.so",' \
    '    ]' \
    '    for path in files:' \
    '        path.parent.mkdir(parents=True, exist_ok=True)' \
    '        path.touch()' > "$root/src/build.py"
  make_fake_nm
}

run_isolation_check() {
  local product="$1"
  PATH="$TMP/fakebin:$PATH" LEAK_ME=must-not-cross \
    bash -c 'source "$1"; STAGE=test-A4; DRY=0; WORK="$2/work"; STDSRC="$2"; stdlib_build stdlib-stage1 "$3" "$4" "$5"' \
      bash "$product" "$TMP/isolation/src" "$TMP/isolation/sdk" "$TMP/isolation/rt" "$TMP/isolation/std"
}

positive_build_env() {
  local caller_tmp
  make_dry_fixture
  caller_tmp="$TMP/caller-tmp"
  mkdir -p "$caller_tmp" "$TMP/caller-home"
  HOME="$TMP/caller-home" TMPDIR="$caller_tmp" dry_run > "$TMP/build-env-passthrough.log"
  check_count build-env 4 "CMD env -i HOME=/root TMPDIR=$caller_tmp CANGJIE_HOME=" "$TMP/build-env-passthrough.log"
  (
    unset TMPDIR
    HOME="$TMP/caller-home" dry_run
  ) > "$TMP/build-env-default.log"
  check_count build-env 4 'CMD env -i HOME=/root TMPDIR=.*/work/tmp-private CANGJIE_HOME=' "$TMP/build-env-default.log"
  echo 'PASS bootstrap CLI keeps HOME=/root and passes caller/default TMPDIR'
}

fault_build_env() {
  make_dry_fixture
  sed 's/TMPDIR=$(printf '\''%q'\'' "$BUILD_TMPDIR") //' "$PRODUCT" > "$TMP/bootstrap-no-tmpdir.sh"
  PRODUCT="$TMP/bootstrap-no-tmpdir.sh"
  dry_run > "$TMP/build-env-no-tmpdir.log"
  check_dry_contract "$TMP/build-env-no-tmpdir.log"
}

fault_a2() {
  new_tmp
  mkdir -p "$TMP/sdk" "$TMP/rt"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 23' > "$TMP/cjcj-stage2"
  chmod +x "$TMP/cjcj-stage2"
  bash -c 'source "$1"; STAGE=test-A2; DRY=0; assert_version cjcj-stage2 "$2" "$3" "$4"' \
    bash "$PRODUCT" "$TMP/cjcj-stage2" "$TMP/sdk" "$TMP/rt"
}

fault_a3() {
  new_tmp
  bash -c 'source "$1"; STAGE=test-A3; DRY=0; assert_executable stage1-compiler "$2"' \
    bash "$PRODUCT" "$TMP/sdk-stage1/bin/cjc"
}

fault_cjpm_toml() {
  make_dry_fixture
  rm -f "$TMP/src/cjpm.toml"
  dry_run
}

fault_src_file() {
  make_dry_fixture
  printf 'single\n' > "$TMP/single.cj"
  bash "$PRODUCT" \
    --work "$TMP/work" --src "$TMP/single.cj" --cjcj-sha aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    --stdsrc "$TMP/stdsrc" --cpp-src "$TMP/cpp-src" --base "$TMP/base" \
    --host-llvm-so "$TMP/libLLVM-15.so" --host-llvm-sha256 "$HOST_SHA" \
    --ast-support "$TMP/ast.a" --ast-support-sha256 "$AST_SHA" \
    --colour-tuple "$TMP/colour-tuple" --colour-llvm-sha "$COLOUR_SHA" \
    --colour-rt "$TMP/colour-rt" --host-rt "$TMP/host-rt" \
    --stage all --dry-run
}

fault_compile_option() {
  new_tmp
  printf 'compile-option = "-O0"\n' > "$TMP/cjpm.toml"
  bash -c 'source "$1"; STAGE=test-O1; DRY=0; rewrite_compile_option_o1 "$2"' \
    bash "$PRODUCT" "$TMP/cjpm.toml"
}

positive_compile_option_o1() {
  new_tmp
  printf 'compile-option = "-O1"\n' > "$TMP/cjpm.toml"
  bash -c 'source "$1"; STAGE=test-O1; DRY=0; rewrite_compile_option_o1 "$2"' \
    bash "$PRODUCT" "$TMP/cjpm.toml"
}

fault_product_missing() {
  new_tmp
  mkdir -p "$TMP/empty-bin"
  bash -c 'source "$1"; STAGE=test-product; DRY=0; resolve_cjpm_product "$2" cjcj-stage1' \
    bash "$PRODUCT" "$TMP/empty-bin"
}

fault_shim_wiring() {
  make_dry_fixture
  sed '/^[[:space:]]*shim_build stage0 /d' "$PRODUCT" > "$TMP/bootstrap-skip-stage0-shim.sh"
  PRODUCT="$TMP/bootstrap-skip-stage0-shim.sh"
  dry_run > "$TMP/skip-stage0-shim.log"
  check_shim_call_count "$TMP/skip-stage0-shim.log"
}

check_shim_wiring() {
  make_dry_fixture
  dry_run > "$TMP/shim-wiring.log"
  check_shim_call_count "$TMP/shim-wiring.log"
  echo 'PASS shim wiring stage0+stage1'
}

# Reuse fixture builders without running the test dispatcher.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then return 0; fi

case "${1:-test}" in
  dry-run)
    make_dry_fixture
    dry_run
    ;;
  positive-a1)
    new_tmp
    run_shape_check 2
    ;;
  positive-compile-option-o1)
    positive_compile_option_o1
    ;;
  positive-build-env)
    positive_build_env
    ;;
  positive-runtime-layouts)
    positive_runtime_layouts
    ;;
  positive-runtime-layout-symlink-nested-only)
    positive_runtime_layout_symlink_nested_only
    ;;
  positive-runtime-layout-symlink-flat-only)
    positive_runtime_layout_symlink_flat_only
    ;;
  check-runtime-layouts)
    check_runtime_layouts
    ;;
  check-build-env)
    positive_build_env
    ;;
  fault-a1)
    new_tmp
    run_shape_check 1
    ;;
  fault-a2)
    fault_a2
    ;;
  fault-a3)
    fault_a3
    ;;
  fault-a4)
    new_tmp
    make_isolation_fixture
    sed 's/cmd "env -i /cmd "/' "$PRODUCT" > "$TMP/bootstrap-no-env-i.sh"
    run_isolation_check "$TMP/bootstrap-no-env-i.sh"
    ;;
  fault-build-env)
    fault_build_env
    ;;
  fault-runtime-stamp)
    fault_runtime_stamp
    ;;
  fault-runtime-dual-layout)
    fault_runtime_dual_layout
    ;;
  fault-runtime-dual-missing-bounds)
    fault_runtime_dual_missing_bounds
    ;;
  fault-runtime-dual-multiple-nested)
    fault_runtime_dual_multiple_nested
    ;;
  fault-runtime-layout-symlink-nested)
    fault_runtime_layout_symlink_nested
    ;;
  fault-runtime-layout-symlink-flat)
    fault_runtime_layout_symlink_flat
    ;;
  fault-runtime-layout-inner-rc)
    fault_runtime_layout_inner_rc
    ;;
  fault-host-sha)
    make_dry_fixture
    dry_run 0000000000000000000000000000000000000000000000000000000000000000 "$AST_SHA"
    ;;
  fault-ast-sha)
    make_dry_fixture
    dry_run "$HOST_SHA" 0000000000000000000000000000000000000000000000000000000000000000
    ;;
  fault-host-colour)
    make_dry_fixture
    cp "$TMP/colour-libLLVM-15.so" "$TMP/libLLVM-15.so"
    HOST_SHA=$(sha256sum "$TMP/libLLVM-15.so" | awk '{print $1}')
    dry_run
    ;;
  fault-colour-ruler)
    make_dry_fixture
    cp /bin/true "$TMP/colour-tuple/bin/opt"
    refresh_tuple_sums
    dry_run
    ;;
  fault-colour-stamp-duplicate)
    make_dry_fixture
    printf 'CJLLVM-COMMIT:%s\n' "$COLOUR_SHA" >> "$TMP/colour-tuple/bin/opt"
    refresh_tuple_sums
    dry_run
    ;;
  fault-colour-stamp-mismatch)
    make_dry_fixture
    sed -i 's/CJLLVM-COMMIT:1111111111111111111111111111111111111111/CJLLVM-COMMIT:2222222222222222222222222222222222222222/' "$TMP/colour-tuple/bin/opt"
    refresh_tuple_sums
    dry_run
    ;;
  fault-colour-sha)
    make_dry_fixture
    COLOUR_SHA=2222222222222222222222222222222222222222
    dry_run
    ;;
  fault-llvm-so-location)
    make_dry_fixture
    make_sdk_fixture
    sed 's|target="$canonical"|target="$TO/third_party/llvm/bin/$base"|' "$SDK_PRODUCT" > "$TMP/sdk-build-wrong-so-location.sh"
    run_sdk_so "$TMP/sdk-build-wrong-so-location.sh" "$TMP/sdk-wrong-so"
    ;;
  fault-tuple-missing-opt)
    make_dry_fixture
    rm "$TMP/colour-tuple/bin/opt"
    dry_run
    ;;
  fault-tuple-sums)
    make_dry_fixture
    printf 'changed after sums\n' >> "$TMP/colour-tuple/bin/llc"
    dry_run
    ;;
  fault-tuple-extra-entry)
    make_dry_fixture
    printf 'unexpected\n' > "$TMP/colour-tuple/EXTRA"
    refresh_tuple_sums
    dry_run
    ;;
  fault-old-host-llvm)
    make_dry_fixture
    bash "$PRODUCT" --host-llvm "$TMP/libLLVM-15.so"
    ;;
  fault-old-colour-llc)
    make_dry_fixture
    bash "$PRODUCT" --colour-llc "$TMP/colour-tuple/bin/llc"
    ;;
  fault-cjpm-toml)
    fault_cjpm_toml
    ;;
  fault-src-file)
    fault_src_file
    ;;
  fault-compile-option)
    fault_compile_option
    ;;
  fault-product-missing)
    fault_product_missing
    ;;
  fault-shim-wiring)
    fault_shim_wiring
    ;;
  check-shim-wiring)
    check_shim_wiring
    ;;
  ruler-control)
    [ $# -eq 4 ] || fail ruler-control 'usage: ruler-control OFFICIAL_OPT COLOUR_TUPLE EXPECTED_LLVM_SHA'
    # shellcheck disable=SC1090 # Product path is resolved above.
    source "$PRODUCT"
    STAGE=test-ruler
    assert_official_opt_zero "$2"
    assert_colour_tuple "$3" "$4"
    ;;
  test)
    make_dry_fixture
    dry_run > "$TMP/dry.log"
    check_dry_contract "$TMP/dry.log"
    bash "$0" check-shim-wiring > "$TMP/shim-wiring-positive.log" ||
      fail SHIM 'positive shim wiring check failed'
    make_sdk_fixture
    run_sdk_so "$SDK_PRODUCT" "$TMP/sdk-so" > "$TMP/sdk-so.log"
    cmp -s "$TMP/libLLVM-15.so" "$TMP/sdk-so/third_party/llvm/lib/libLLVM-15.so" ||
      fail LLVM-SO 'sdk_build did not install the requested SO at the canonical lib location'
    cmp -s "$TMP/sdk-base/third_party/llvm/bin/llc" "$TMP/sdk-so/third_party/llvm/bin/llc" ||
      fail LLVM-SO 'SO-only install changed llc'
    cmp -s "$TMP/sdk-base/third_party/llvm/bin/opt" "$TMP/sdk-so/third_party/llvm/bin/opt" ||
      fail LLVM-SO 'SO-only install changed opt'
    run_sdk_tuple "$SDK_PRODUCT" "$TMP/sdk-tuple" > "$TMP/sdk-tuple.log"
    for rel in MANIFEST bin/llc bin/opt lib/STATIC_LLVM.txt fixed-llc/cjselfhost_llvmshim.o fixed-llc/llc.gz fixed-llc/opt.gz fixed-llc/llvm-tools.manifest; do
      cmp -s "$TMP/colour-tuple/$rel" "$TMP/sdk-tuple/third_party/llvm/$rel" ||
        fail LLVM-TUPLE "sdk_build tuple mismatch: $rel"
    done
    run_shape_check 2 > "$TMP/shape-positive.log"
    /usr/bin/grep -q 'shape=ok Int64.ti=2 FFI-archives=1 FFI-set-equal=1' "$TMP/shape-positive.log" ||
      fail A1 'positive stdlib shape arm did not pass'
    make_isolation_fixture
    run_isolation_check "$PRODUCT" > "$TMP/isolation-positive.log"
    /usr/bin/grep -q 'shape=ok Int64.ti=2 FFI-archives=1' "$TMP/isolation-positive.log" ||
      fail A4 'isolated real command path did not pass'
    /usr/bin/grep -q 'cjpm build' "$TMP/dry.log" || fail CJPM 'dry-run CMD missing cjpm build'
    bash "$0" positive-compile-option-o1 > "$TMP/compile-option-o1-positive.log" ||
      fail compile-option 'existing -O1 was not accepted idempotently'
    BOOTSTRAP_PRODUCT="$PRODUCT" SDK_BUILD_PRODUCT="$SDK_PRODUCT" bash "$0" check-build-env > "$TMP/build-env-positive.log" ||
      fail build-env 'bootstrap CLI HOME/TMPDIR contract did not pass'
    BOOTSTRAP_PRODUCT="$PRODUCT" SDK_BUILD_PRODUCT="$SDK_PRODUCT" bash "$0" check-runtime-layouts > "$TMP/runtime-layouts-positive.log" ||
      fail runtime-layouts 'flat/nested/dual/inner-rc runtime layout contract did not pass'
    for arm in a1 a2 a3 a4 build-env runtime-stamp host-sha ast-sha host-colour colour-ruler colour-stamp-duplicate colour-stamp-mismatch colour-sha llvm-so-location tuple-missing-opt tuple-sums tuple-extra-entry old-host-llvm old-colour-llc cjpm-toml src-file compile-option product-missing shim-wiring; do
      log="$TMP/fault-$arm.log"
      if bash "$0" "fault-$arm" > "$log" 2>&1; then
        fail "$arm" 'fault arm unexpectedly passed'
      fi
      case "$arm" in
        a1) marker='BOOTSTRAP-FAIL \[test-A1\].*Int64.ti definitions=1';;
        a2) marker='BOOTSTRAP-FAIL \[test-A2\].*命令失败 rc=23';;
        a3) marker='BOOTSTRAP-FAIL \[test-A3\].*stage1-compiler';;
        a4) marker='BOOTSTRAP-FAIL \[test-A4\].*命令失败 rc=44';;
        build-env) marker='TEST-FAIL \[A4\].*TMPDIR';;
        runtime-stamp) marker='SDK-BUILD-FAIL runtime CJRT-COMMIT 不匹配: expected=4444444444444444444444444444444444444444 actual=5555555555555555555555555555555555555555';;
        host-sha) marker='BOOTSTRAP-FAIL \[stage0\] host-llvm sha256';;
        ast-sha) marker='BOOTSTRAP-FAIL \[stage0\] ast-support sha256';;
        host-colour) marker='BOOTSTRAP-FAIL \[stage0\] host LLVM 含 colour 动态符号 hits=1';;
        colour-ruler) marker='BOOTSTRAP-FAIL \[stage0\] colour LLVM tuple opt 的 CJLLVM-COMMIT 章计数不是 1: hits=0';;
        colour-stamp-duplicate) marker='BOOTSTRAP-FAIL \[stage0\] colour LLVM tuple opt 的 CJLLVM-COMMIT 章计数不是 1: hits=2';;
        colour-stamp-mismatch) marker='BOOTSTRAP-FAIL \[stage0\] colour LLVM tuple opt 章与 MANIFEST LLVM_SHA 不匹配';;
        colour-sha) marker='BOOTSTRAP-FAIL \[stage0\] colour LLVM tuple MANIFEST LLVM_SHA 与期望值不匹配';;
        llvm-so-location) marker='SDK-BUILD-FAIL llvm-so 安装后 sha256 不一致';;
        tuple-missing-opt) marker='BOOTSTRAP-FAIL \[stage0\] colour LLVM tuple 缺 bin/opt';;
        tuple-sums) marker='BOOTSTRAP-FAIL \[stage0\] colour LLVM tuple SHA256SUMS strict 校验失败';;
        tuple-extra-entry) marker='BOOTSTRAP-FAIL \[stage0\] colour LLVM tuple SHA256SUMS 必须且只能登记 8 个 payload: entries=9';;
        old-host-llvm) marker='BOOTSTRAP-FAIL \[init\] 参数 --host-llvm 已废弃；使用 --host-llvm-so';;
        old-colour-llc) marker='BOOTSTRAP-FAIL \[init\] 参数 --colour-llc 已废弃；使用 --colour-tuple';;
        cjpm-toml) marker='BOOTSTRAP-FAIL \[init\] --src 缺少 cjpm.toml';;
        src-file) marker='BOOTSTRAP-FAIL \[init\] --src 必须是含 cjpm.toml 的 cjcj 仓根，拒绝单文件';;
        compile-option) marker='BOOTSTRAP-FAIL \[test-O1\] 隔离副本 cjpm.toml 的 compile-option 不是 -O1';;
        product-missing) marker='BOOTSTRAP-FAIL \[test-product\] cjcj-stage1 cjpm 产物缺失';;
        shim-wiring) marker='TEST-FAIL \[SHIM\] pattern count=1 expected=2: CMD shim build label=';;
      esac
      /usr/bin/grep -Eq "$marker" "$log" || fail "$arm" "fault arm missed precise marker; log=$log"
      echo "PASS precise-red $arm"
    done
    echo 'PASS bootstrap dry contracts, controlled build environment, LLVM assembly, and positive controls'
    ;;
  *)
    echo "usage: $0 [test|dry-run|check-shim-wiring|check-build-env|check-runtime-layouts|positive-a1|positive-build-env|positive-runtime-layouts|positive-runtime-layout-symlink-nested-only|positive-runtime-layout-symlink-flat-only|positive-compile-option-o1|fault-a1|fault-a2|fault-a3|fault-a4|fault-build-env|fault-runtime-stamp|fault-runtime-dual-layout|fault-runtime-dual-missing-bounds|fault-runtime-dual-multiple-nested|fault-runtime-layout-symlink-nested|fault-runtime-layout-symlink-flat|fault-runtime-layout-inner-rc|fault-host-sha|fault-ast-sha|fault-host-colour|fault-colour-ruler|fault-colour-stamp-duplicate|fault-colour-stamp-mismatch|fault-colour-sha|fault-llvm-so-location|fault-tuple-missing-opt|fault-tuple-sums|fault-tuple-extra-entry|fault-old-host-llvm|fault-old-colour-llc|fault-shim-wiring|ruler-control OFFICIAL_OPT COLOUR_TUPLE EXPECTED_LLVM_SHA]" >&2
    exit 2
    ;;
esac
