#!/usr/bin/env bash
# Purpose: bind bootstrap host processes separately from target backend processes.
# Caller: bootstrap.sh stage1; this workspace SDK is not a distributable SDK.
set -euo pipefail
fail() { echo "STAGE1-RUNNER-FAIL $*" >&2; exit 1; }
self=$(readlink -f "$0")
here=$(dirname "$self")
identities=${STAGE1_HOST_IDENTITIES:-$here/stage1_host_identities.txt}
[ -f "$identities" ] || fail "missing host identities: $identities"
# Arguments are intentionally explicit: the input hashes have already been pinned
# by bootstrap, and are checked again against the declared host triple here.
[ "$#" -eq 6 ] || fail 'usage: TARGET_SDK HOST_SDK HOST_RUNTIME HOST_LLVM_SHA COMPILER COMPILER_SHA'
target=$(readlink -f "$1")
host=$(readlink -f "$2")
hrt=$(readlink -f "$3")
llvm_sha=$4
compiler=$(readlink -f "$5")
compiler_sha=$6
record_evidence() {
  local dest=$1
  {
    printf 'runner %s %s\n' "$(sha256sum "$self" | awk '{print $1}')" "$self"
    if [ -n "${STAGE1_TEST_FILE:-}" ] && [ -f "$STAGE1_TEST_FILE" ]; then
      printf 'test %s %s\n' "$(sha256sum "$STAGE1_TEST_FILE" | awk '{print $1}')" "$(readlink -f "$STAGE1_TEST_FILE")"
    fi
    printf 'identities %s %s\n' "$(sha256sum "$identities" | awk '{print $1}')" "$identities"
  } > "$dest"
}
if [ -n "${STAGE1_EVIDENCE_DIR:-}" ]; then
  mkdir -p "$STAGE1_EVIDENCE_DIR"
  record_evidence "$STAGE1_EVIDENCE_DIR/runner-test.sha256"
fi
for root in "$target" "$host"; do
  case "$root" in /root/sdks|/root/sdks/*|/root/.cjv|/root/.cjv/*) fail "workspace SDK required: $root";; esac
  [ -d "$root" ] || fail "missing SDK: $root"
done
[ "$target" != "$host" ] || fail 'host and target SDK must differ'
platform=linux_x86_64_cjnative
if [ -f "$hrt/runtime/lib/$platform/libcangjie-runtime.so" ]; then
  hrt="$hrt/runtime/lib/$platform"
elif [ -f "$hrt/lib/$platform/libcangjie-runtime.so" ]; then
  hrt="$hrt/lib/$platform"
fi
decl_runtime= decl_bounds= decl_llvm=
while read -r key val _; do
  [ -n "${key:-}" ] || continue
  case "$key" in
    '#'*) continue ;;
    libcangjie-runtime.so) decl_runtime=$val ;;
    libboundscheck.so) decl_bounds=$val ;;
    libLLVM-15.so) decl_llvm=$val ;;
    *) fail "unknown identity key: $key" ;;
  esac
done < "$identities"
[ -n "$decl_runtime" ] && [ -n "$decl_bounds" ] && [ -n "$decl_llvm" ] || fail "incomplete host identities: $identities"
[ "$llvm_sha" = "$decl_llvm" ] || fail "llvm sha is not the declared host triple: arg=$llvm_sha declared=$decl_llvm"
check_sha() {
  local path=$1 expected=$2 actual
  actual=$(sha256sum "$path")
  actual=${actual%% *}
  [ "$actual" = "$expected" ] || fail "sha mismatch: $path expected=$expected actual=$actual"
}
check_sha "$host/third_party/llvm/lib/libLLVM-15.so" "$decl_llvm"
check_sha "$compiler" "$compiler_sha"
check_sha "$hrt/libcangjie-runtime.so" "$decl_runtime"
check_sha "$hrt/libboundscheck.so" "$decl_bounds"
check_sha "$host/runtime/lib/$platform/libcangjie-runtime.so" "$decl_runtime"
check_sha "$host/runtime/lib/$platform/libboundscheck.so" "$decl_bounds"
for rel in bin/cjc tools/bin/cjpm third_party/llvm/bin/opt third_party/llvm/bin/llc; do
  [ -x "$target/$rel" ] && [ ! -L "$target/$rel" ] || fail "regular executable required: $rel"
done
host_ld="$host/runtime/lib/$platform:$host/lib/$platform:$host/third_party/llvm/lib:$host/tools/lib:/usr/lib/x86_64-linux-gnu"
target_ld="$target/runtime/lib/$platform:$target/lib/$platform:$target/third_party/llvm/lib:$target/tools/lib:/usr/lib/x86_64-linux-gnu"
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
    printf 'export LD_LIBRARY_PATH=%q\n' "$ld"
    printf 'exec %q "$@"\n' "$real"
  } > "$entry"
  chmod +x "$entry"
}
write_runner "$target/bin/cjc" "$target/bin/cjcj-stage1" "$host_ld"
write_runner "$target/tools/bin/cjpm" "$target/tools/bin/cjpm-stage1" "$host_ld"
for name in opt llc; do
  cp -p "$target/third_party/llvm/bin/$name" "$target/third_party/llvm/bin/$name-stage1"
  write_runner "$target/third_party/llvm/bin/$name" "$target/third_party/llvm/bin/$name-stage1" "$target_ld"
done
sha256sum "$compiler" "$host/runtime/lib/$platform/"*.so \
  "$host/third_party/llvm/lib/libLLVM-15.so" "$host/tools/bin/cjpm" \
  "$target/bin/cjcj-stage1" "$target/third_party/llvm/bin/"*-stage1 > "$state/INPUTS.sha256"
printf 'host=%s\ntarget=%s\nhost_ld=%s\ntarget_ld=%s\ndecl_runtime=%s\ndecl_bounds=%s\ndecl_llvm=%s\n' \
  "$host" "$target" "$host_ld" "$target_ld" "$decl_runtime" "$decl_bounds" "$decl_llvm" > "$state/binding.txt"
echo "STAGE1-RUNNER-OK host=$host target=$target compiler=$target/bin/cjcj-stage1"
