#!/usr/bin/env bash
# Purpose: bind bootstrap host processes separately from target backend processes.
# Caller: bootstrap.sh stage1; this workspace SDK is not a distributable SDK.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/host_tools.sh"
fail() { echo "STAGE1-RUNNER-FAIL $*" >&2; exit 1; }
self=$(host_readlink -f "$0")
here=$(dirname "$self")
identities=${STAGE1_HOST_IDENTITIES:-$here/stage1_host_identities.txt}
[ -f "$identities" ] || fail "missing host identities: $identities"
# Arguments are intentionally explicit: the input hashes have already been pinned
# by bootstrap, and are checked again against the declared host triple here.
if [ "$#" -lt 8 ] || [ "$#" -gt 9 ]; then
  fail 'usage: TARGET_SDK HOST_SDK HOST_RUNTIME HOST_LLVM_SHA COMPILER COMPILER_SHA RUN_SDK COLOUR_LLVM_SHA [BACKEND_RUNTIME_DIR]'
fi
target=$(host_readlink -f "$1")
host=$(host_readlink -f "$2")
hrt=$(host_readlink -f "$3")
llvm_sha=$4
compiler=$(host_readlink -f "$5")
compiler_sha=$6
run_sdk=$(host_readlink -f "$7")
colour_llvm_sha=$8
record_evidence() {
  local dest=$1
  {
    printf 'runner %s %s\n' "$(host_sha256sum "$self" | awk '{print $1}')" "$self"
    if [ -n "${STAGE1_TEST_FILE:-}" ] && [ -f "$STAGE1_TEST_FILE" ]; then
      printf 'test %s %s\n' "$(host_sha256sum "$STAGE1_TEST_FILE" | awk '{print $1}')" "$(host_readlink -f "$STAGE1_TEST_FILE")"
    fi
    printf 'identities %s %s\n' "$(host_sha256sum "$identities" | awk '{print $1}')" "$identities"
  } > "$dest"
}
if [ -n "${STAGE1_EVIDENCE_DIR:-}" ]; then
  mkdir -p "$STAGE1_EVIDENCE_DIR"
  record_evidence "$STAGE1_EVIDENCE_DIR/runner-test.sha256"
fi
for root in "$target" "$host" "$run_sdk"; do
  case "$root" in /root/sdks|/root/sdks/*|/root/.cjv|/root/.cjv/*) fail "workspace SDK required: $root";; esac
  [ -d "$root" ] || fail "missing SDK: $root"
done
if [ "$target" = "$host" ] || [ "$run_sdk" = "$host" ] || [ "$run_sdk" = "$target" ]; then
  fail 'host, run and target SDK must differ'
fi
# Host tuple from the machine, as bootstrap.sh derives it.
case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) platform=linux_x86_64_cjnative; multiarch=x86_64-linux-gnu;;
  Linux/aarch64) platform=linux_aarch64_cjnative; multiarch=aarch64-linux-gnu;;
  Darwin/arm64) platform=darwin_aarch64_cjnative; multiarch=;;
  Darwin/x86_64) platform=darwin_x86_64_cjnative; multiarch=;;
  *) fail "unsupported native host";;
esac
if [ -f "$hrt/runtime/lib/$platform/libcangjie-runtime.${HOST_LIB_EXT}" ]; then
  hrt="$hrt/runtime/lib/$platform"
elif [ -f "$hrt/lib/$platform/libcangjie-runtime.${HOST_LIB_EXT}" ]; then
  hrt="$hrt/lib/$platform"
fi
decl_runtime='' decl_bounds='' decl_llvm=''
# Only the native platform's reviewed triple may authorize these host bytes.
# No unscoped fallback: another platform's declaration cannot fill a missing pin.
while read -r identity_platform key val extra; do
  [ -n "${identity_platform:-}" ] || continue
  case "$identity_platform" in
    '#'*) continue ;;
    linux_x86_64|linux_aarch64|darwin_x86_64|darwin_aarch64) ;;
    *) fail "unknown identity platform: $identity_platform" ;;
  esac
  [ "$identity_platform" = "${platform%_cjnative}" ] || continue
  if [ -n "${extra:-}" ] || [[ ! "${val:-}" =~ ^[a-f0-9]{64}$ ]]; then
    fail "invalid host identity: $identity_platform $key"
  fi
  case "$key" in
    libcangjie-runtime.${HOST_LIB_EXT}) [ -z "$decl_runtime" ] || fail "duplicate host identity: $key"; decl_runtime=$val ;;
    libboundscheck.${HOST_LIB_EXT}) [ -z "$decl_bounds" ] || fail "duplicate host identity: $key"; decl_bounds=$val ;;
    ${HOST_LLVM_LIBRARY}) [ -z "$decl_llvm" ] || fail "duplicate host identity: $key"; decl_llvm=$val ;;
    *) fail "unknown identity key: $key" ;;
  esac
done < "$identities"
if [ -z "$decl_runtime" ] || [ -z "$decl_bounds" ] || [ -z "$decl_llvm" ]; then
  fail "incomplete host identities: ${platform%_cjnative} $identities"
fi
[ "$llvm_sha" = "$decl_llvm" ] || fail "llvm sha is not the declared host triple: arg=$llvm_sha declared=$decl_llvm"
check_sha() {
  local path=$1 expected=$2 actual
  actual=$(host_sha256sum "$path")
  actual=${actual%% *}
  [ "$actual" = "$expected" ] || fail "sha mismatch: $path expected=$expected actual=$actual"
}
check_sha "$host/third_party/llvm/lib/${HOST_LLVM_LIBRARY}" "$decl_llvm"
check_sha "$run_sdk/third_party/llvm/lib/${HOST_LLVM_LIBRARY}" "$colour_llvm_sha"
check_sha "$target/third_party/llvm/lib/${HOST_LLVM_LIBRARY}" "$colour_llvm_sha"
check_sha "$compiler" "$compiler_sha"
check_sha "$hrt/libcangjie-runtime.${HOST_LIB_EXT}" "$decl_runtime"
check_sha "$hrt/libboundscheck.${HOST_LIB_EXT}" "$decl_bounds"
check_sha "$host/runtime/lib/$platform/libcangjie-runtime.${HOST_LIB_EXT}" "$decl_runtime"
check_sha "$host/runtime/lib/$platform/libboundscheck.${HOST_LIB_EXT}" "$decl_bounds"
for rel in bin/cjc tools/bin/cjpm third_party/llvm/bin/opt third_party/llvm/bin/llc; do
  if [ ! -x "$target/$rel" ] || [ -L "$target/$rel" ]; then
    fail "regular executable required: $rel"
  fi
done
host_ld="$host/runtime/lib/$platform:$host/lib/$platform:$host/third_party/llvm/lib:$host/tools/lib${multiarch:+:/usr/lib/$multiarch}"
compiler_ld="$host/runtime/lib/$platform:$host/lib/$platform:$run_sdk/third_party/llvm/lib:$host/tools/lib${multiarch:+:/usr/lib/$multiarch}"
backend_runtime="${9:-$target/runtime/lib/$platform}"
if [ ! -f "$backend_runtime/libcangjie-runtime.${HOST_LIB_EXT}" ] || [ ! -f "$backend_runtime/libboundscheck.${HOST_LIB_EXT}" ]; then
  fail "missing backend runtime: $backend_runtime"
fi
target_ld="$backend_runtime:$target/lib/$platform:$target/third_party/llvm/lib:$target/tools/lib${multiarch:+:/usr/lib/$multiarch}"
state="$target/.stage1-host"
[ ! -e "$state" ] || fail 'runner already installed; reassemble the workspace SDK'
mkdir "$state"
record_evidence "$state/RUNNER.sha256"
# Preserve the genuine mapping basename. exec -a or a symlink named cjc does not
# change /proc/self/maps, which the official runtime uses for frame classification.
cp -p "$compiler" "$target/bin/cjcj-stage1"
check_sha "$target/bin/cjcj-stage1" "$compiler_sha"
cp -p "$host/tools/bin/cjpm" "$target/tools/bin/cjpm-stage1"
write_runner() {
  local entry=$1 real=$2 ld=$3
  # Existing executable mode is retained; only the isolated SDK files are written.
  {
    printf '#!/usr/bin/env bash\n'
    printf 'export CANGJIE_HOME=%q\n' "$target"
    printf 'export %s=%q\n' "$HOST_LOADER_VAR" "$ld"
    printf 'exec %q "$@"\n' "$real"
  } > "$entry"
  chmod +x "$entry"
}
write_runner "$target/bin/cjc" "$target/bin/cjcj-stage1" "$compiler_ld"
write_runner "$target/tools/bin/cjpm" "$target/tools/bin/cjpm-stage1" "$host_ld"
for name in opt llc; do
  cp -p "$target/third_party/llvm/bin/$name" "$target/third_party/llvm/bin/$name-stage1"
  write_runner "$target/third_party/llvm/bin/$name" "$target/third_party/llvm/bin/$name-stage1" "$target_ld"
done
# Ancillary LLVM tools remain official host executables. They must not inherit
# the cjcj process library when launched by the compiler (Gnu.cj:69).
for name in llvm-objcopy llvm-ar; do
  if [ -f "$target/third_party/llvm/bin/$name" ]; then
    cp -p "$target/third_party/llvm/bin/$name" "$target/third_party/llvm/bin/$name-stage1"
    write_runner "$target/third_party/llvm/bin/$name" "$target/third_party/llvm/bin/$name-stage1" "$host_ld"
  fi
done
host_sha256sum "$compiler" "$host/runtime/lib/$platform/"*.${HOST_LIB_EXT} \
  "$host/third_party/llvm/lib/${HOST_LLVM_LIBRARY}" "$run_sdk/third_party/llvm/lib/${HOST_LLVM_LIBRARY}" "$host/tools/bin/cjpm" \
  "$target/bin/cjcj-stage1" "$target/third_party/llvm/bin/"*-stage1 > "$state/INPUTS.sha256"
printf 'host=%s\ntarget=%s\nhost_ld=%s\ntarget_ld=%s\ndecl_runtime=%s\ndecl_bounds=%s\ndecl_llvm=%s\n' \
  "$host" "$target" "$host_ld" "$target_ld" "$decl_runtime" "$decl_bounds" "$decl_llvm" > "$state/binding.txt"
printf 'run_sdk=%s\ncompiler_ld=%s\ncolour_llvm_sha=%s\n' "$run_sdk" "$compiler_ld" "$colour_llvm_sha" >> "$state/binding.txt"
echo "STAGE1-RUNNER-OK host=$host target=$target compiler=$target/bin/cjcj-stage1"
