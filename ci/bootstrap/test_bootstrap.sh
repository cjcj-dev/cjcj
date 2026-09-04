#!/usr/bin/env bash
# Vendored from tools@66aec40809b373843a3614472d78a555c94cadcf test_bootstrap.sh
# Purpose: exercise bootstrap contract and fault arms; caller: test_bootstrap.sh:2
# Focused contract and fault-arm tests for bootstrap.sh.
set -u

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
PRODUCT="$ROOT/bootstrap.sh"
SDK_PRODUCT="$ROOT/sdk_build.sh"
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
  mkdir -p "$TMP/base/bin" "$TMP/base/third_party/llvm/bin" "$TMP/src" "$TMP/stdsrc" "$TMP/host-rt" "$TMP/colour-rt"
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
    --work "$TMP/work" --src "$TMP/src" --stdsrc "$TMP/stdsrc" --base "$TMP/base" \
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
  check_count A4 2 'rm\\ -rf\\ build/build' "$log"
  check_count A4 2 '--target-lib' "$log"
  check_count A4 4 'CMD env -i HOME=/root CANGJIE_HOME=.*bash -c' "$log"
  check_count LLVM-SO 1 'sdk_build.sh .*--host --llvm-so .*libLLVM-15.so' "$log"
  check_count LLVM-SO 1 'ASSERT installed-host-llvm-so sha256=planned' "$log"
  check_count LLVM-TUPLE 1 'sdk_build.sh .*--target .*--llvm-tuple .*colour-tuple' "$log"
  check_count LLVM-TUPLE 8 'ASSERT installed-colour-tuple sha256=planned' "$log"
  check_count LLVM-RULER 2 'ruler=readelf--dyn-syms symbol=llvm::isCJTypedReadHelperCandidate' "$log"
  check_count LLVM-RULER 1 'ASSERT official-opt-zero ruler=strings .* hits=0' "$log"
  check_count LLVM-RULER 2 'ASSERT colour-opt-stamp ruler=strings .* hits=1' "$log"
}

make_sdk_fixture() {
  local base="$TMP/sdk-base"
  mkdir -p "$base/bin" "$base/third_party/llvm/bin" "$base/third_party/llvm/lib" \
    "$base/runtime/lib/linux_x86_64_cjnative"
  cp /bin/true "$base/bin/cjc"
  cp /bin/true "$base/third_party/llvm/bin/llc"
  cp /bin/true "$base/third_party/llvm/bin/opt"
  printf 'int base_llvm;\n' > "$TMP/base-llvm.c"
  cc -shared -fPIC "$TMP/base-llvm.c" -o "$base/third_party/llvm/lib/libLLVM-15.so"
  printf 'int host_runtime;\n' > "$TMP/host-runtime.c"
  cc -shared -fPIC "$TMP/host-runtime.c" -o "$base/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so"
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
    bash -c 'source "$1"; STAGE=test-A4; DRY=0; STDSRC="$2"; stdlib_build stdlib-stage1 "$3" "$4" "$5"' \
      bash "$product" "$TMP/isolation/src" "$TMP/isolation/sdk" "$TMP/isolation/rt" "$TMP/isolation/std"
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
    --work "$TMP/work" --src "$TMP/single.cj" --stdsrc "$TMP/stdsrc" --base "$TMP/base" \
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

fault_product_missing() {
  new_tmp
  mkdir -p "$TMP/empty-bin"
  bash -c 'source "$1"; STAGE=test-product; DRY=0; resolve_cjpm_product "$2" cjcj-stage1' \
    bash "$PRODUCT" "$TMP/empty-bin"
}

case "${1:-test}" in
  dry-run)
    make_dry_fixture
    dry_run
    ;;
  positive-a1)
    new_tmp
    run_shape_check 2
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
    for arm in a1 a2 a3 a4 host-sha ast-sha host-colour colour-ruler colour-stamp-duplicate colour-stamp-mismatch colour-sha llvm-so-location tuple-missing-opt tuple-sums tuple-extra-entry old-host-llvm old-colour-llc cjpm-toml src-file compile-option product-missing; do
      log="$TMP/fault-$arm.log"
      if bash "$0" "fault-$arm" > "$log" 2>&1; then
        fail "$arm" 'fault arm unexpectedly passed'
      fi
      case "$arm" in
        a1) marker='BOOTSTRAP-FAIL \[test-A1\].*Int64.ti definitions=1';;
        a2) marker='BOOTSTRAP-FAIL \[test-A2\].*命令失败 rc=23';;
        a3) marker='BOOTSTRAP-FAIL \[test-A3\].*stage1-compiler';;
        a4) marker='BOOTSTRAP-FAIL \[test-A4\].*命令失败 rc=44';;
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
        compile-option) marker='BOOTSTRAP-FAIL \[test-O1\] 隔离副本 cjpm.toml 无 compile-option = "-O2" 可改';;
        product-missing) marker='BOOTSTRAP-FAIL \[test-product\] cjcj-stage1 cjpm 产物缺失';;
      esac
      /usr/bin/grep -Eq "$marker" "$log" || fail "$arm" "fault arm missed precise marker; log=$log"
      echo "PASS precise-red $arm"
    done
    echo 'PASS bootstrap dry contracts, LLVM assembly, and positive controls'
    ;;
  *)
    echo "usage: $0 [test|dry-run|positive-a1|fault-a1|fault-a2|fault-a3|fault-a4|fault-host-sha|fault-ast-sha|fault-host-colour|fault-colour-ruler|fault-colour-stamp-duplicate|fault-colour-stamp-mismatch|fault-colour-sha|fault-llvm-so-location|fault-tuple-missing-opt|fault-tuple-sums|fault-tuple-extra-entry|fault-old-host-llvm|fault-old-colour-llc|ruler-control OFFICIAL_OPT COLOUR_TUPLE EXPECTED_LLVM_SHA]" >&2
    exit 2
    ;;
esac
