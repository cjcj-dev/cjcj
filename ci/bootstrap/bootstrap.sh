#!/usr/bin/env bash
# Purpose: build cjcj in two stages; callers: bootstrap lanes and test_bootstrap.sh.
# Two-stage cjcj bootstrap; see ops/design/BOOTSTRAP_PATH.md.
set -u

RED() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
die() { RED "BOOTSTRAP-FAIL [$STAGE] $*"; exit 1; }
ok() { printf '  ✓ %s\n' "$*"; }

WORK=''
SRC=''
STDSRC=''
HOST_LLVM_SO=''
HOST_LLVM_SHA256=''
COLOUR_LLVM_SO=''
COLOUR_LLVM_SHA256=''
COLOUR_TUPLE=''
COLOUR_LLVM_SHA=''
CRT=''
HRT=''
AST_SUPPORT=''
AST_SUPPORT_SHA256=''
CPP_SRC=''
CJCJ_SHA=''
BASE_SDK="${BASE_SDK:-cjcj-pin-937877c8}"
HEAP="${CJ_HEAP:-96GB}"
STAGE1_HEAP="${STAGE1_HEAP:-20GB}"
JOBS="${CJ_JOBS:-$(getconf _NPROCESSORS_ONLN)}"
SDK_BUILD="${SDK_BUILD:-$(dirname "${BASH_SOURCE[0]}")/sdk_build.sh}"
SDK_VERIFY="${SDK_VERIFY:-$(dirname "${BASH_SOURCE[0]}")/sdk_verify.py}"
STAGE1_HOST_RUNNER="${STAGE1_HOST_RUNNER:-$(dirname "${BASH_SOURCE[0]}")/stage1_host_runner.sh}"
STAGE0_CACHE_ROOT="${STAGE0_CACHE_ROOT:-/root/stage0depot}"
BUILD_TMPDIR=''
STAGE=init
STAGE1_ELF=''
STAGE1_SHA256=''
HOST_SDK=''
RUNTIME_SHA=''
CHECK_ONLY=0
RESUME_COLOUR_GATE=0
RESUME_STD_SUMS=''
COLOUR_GATE_SOURCE=''
COLOUR_GATE_INSTALL=''
HOST_IDENTITIES=''
HOST_IDENTITIES_SHA256=''
WANT=all
DRY=0
# Host tuple directories and the multiarch loader path, from the machine this
# script runs on. Linux only: the script assumes ELF .so names, GNU find/install/
# nm and lib/<tuple> layouts, so a Darwin host is refused here rather than
# failing later on a path that happened to be spelled for x86_64.
HOST_TUPLE=''
HOST_MULTIARCH=''
host_tuple_init() {
  local os arch
  os=$(uname -s); arch=$(uname -m)
  case "$os/$arch" in
    Linux/x86_64) HOST_TUPLE=linux_x86_64_cjnative; HOST_MULTIARCH=x86_64-linux-gnu;;
    Linux/aarch64) HOST_TUPLE=linux_aarch64_cjnative; HOST_MULTIARCH=aarch64-linux-gnu;;
    *) die "host $os/$arch is not supported by bootstrap.sh (Linux x86_64/aarch64 only: ELF .so, GNU find/install/nm, lib/<tuple> layout)";;
  esac
  echo "HOST-TUPLE $HOST_TUPLE multiarch=$HOST_MULTIARCH home=$BUILD_HOME"
}
# HOME for the isolated `env -i` builds: the caller's, /root when unset (kkk2).
BUILD_HOME="${HOME:-/root}"

usage() {
  echo 'bootstrap.sh --work DIR --src CJCJ_ROOT --cjcj-sha 40HEX --stdsrc STDLIB --cpp-src CANGJIE_CPP_ROOT --host-llvm-so libLLVM-15.so --host-llvm-sha256 HEX --colour-llvm-so libLLVM-15.so --colour-llvm-sha256 HEX --ast-support FILE --ast-support-sha256 HEX --colour-tuple DIR --colour-llvm-sha 40HEX --colour-rt DIR --host-rt DIR [--stage supplied-stage1|stage0|stage1|stage1-initial-std|stage1-std|stage1-compiler|all] [--stage1-heap 20GB] [--dry-run]'
  echo 'resume completed same-source std: --resume-colour-gate captured-sha256-file (original private work directory)'
  echo 'colour runtime gate: --colour-gate-source RUNTIME_ROOT --colour-gate-install INSTALL_ROOT (supplied-stage1 only)'
  echo 'supplied-stage1 additionally requires --stage1-elf FILE --stage1-sha256 64HEX --host-sdk DIR --runtime-sha 40HEX --host-identities FILE --host-identities-sha256 64HEX; optional --check-only (no work creation)'
}

sha256() {
  if [ -f "$1" ]; then
    sha256sum "$1" | awk '{print $1}'
  elif [ -d "$1" ]; then
    find "$1" -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}'
  fi
}

record() {
  local label="$1" path="$2"
  [ -e "$path" ] || die "$label 不存在: $path"
  printf 'INPUT %s path=%s sha256=%s\n' "$label" "$(readlink -f "$path")" "$(sha256 "$path")"
}

assert_expected_sha() {
  local label="$1" path="$2" expected="$3" actual
  [ "${#expected}" -eq 64 ] || die "$label 期望 sha256 必须是 64 位十六进制数"
  case "$expected" in *[!0-9a-fA-F]*) die "$label 期望 sha256 不是十六进制";; esac
  actual=$(sha256 "$path")
  [ -n "$actual" ] || die "$label 无法计算 sha256: $path"
  printf 'ASSERT %s-sha256 expected=%s actual=%s\n' "$label" "${expected,,}" "$actual"
  [ "$actual" = "${expected,,}" ] || die "$label sha256 不匹配"
  ok "$label sha256 匹配"
}

tuple_sum_has() {
  local tuple="$1" rel="$2"
  awk -v rel="./$rel" '$2 == rel { found=1 } END { exit !found }' "$tuple/SHA256SUMS"
}

assert_colour_tuple() {
  local tuple="$1" expected="$2" output stamps stamp_hits stamp_sha manifest_sha rel entries
  [ -d "$tuple" ] || die "colour LLVM tuple 不是目录: $tuple"
  [ -f "$tuple/SHA256SUMS" ] || die "colour LLVM tuple 缺 SHA256SUMS: $tuple"
  if ! awk '
    length($1) != 64 || $1 ~ /[^0-9a-fA-F]/ || $2 !~ /^\.\// || $2 ~ /(^|\/)\.\.($|\/)/ { bad=1 }
    END { exit bad || NR == 0 }
  ' "$tuple/SHA256SUMS"; then
    die 'colour LLVM tuple SHA256SUMS 格式或相对路径非法'
  fi
  entries=$(wc -l < "$tuple/SHA256SUMS")
  [ "$entries" -eq 10 ] || die "colour LLVM tuple SHA256SUMS 必须且只能登记 10 个 payload: entries=$entries"
  for rel in MANIFEST bin/llc bin/opt bin/ld.lld lib/STATIC_LLVM.txt \
    fixed-llc/cjselfhost_llvmshim.o fixed-llc/llc.gz \
    fixed-llc/opt.gz fixed-llc/ld.lld.gz fixed-llc/llvm-tools.manifest; do
    [ -f "$tuple/$rel" ] || die "colour LLVM tuple 缺 $rel"
    tuple_sum_has "$tuple" "$rel" || die "colour LLVM tuple SHA256SUMS 未登记 $rel"
  done
  output=$(cd "$tuple" && sha256sum --strict -c SHA256SUMS 2>&1) || {
    printf '%s\n' "$output" >&2
    die 'colour LLVM tuple SHA256SUMS strict 校验失败'
  }
  manifest_sha=$(awk -F= '$1 == "LLVM_SHA" { print $2 }' "$tuple/MANIFEST")
  [ "${#manifest_sha}" -eq 40 ] || die 'colour LLVM tuple MANIFEST LLVM_SHA 必须是 40 位十六进制数'
  case "$manifest_sha" in *[!0-9a-fA-F]*) die 'colour LLVM tuple MANIFEST LLVM_SHA 不是十六进制';; esac
  [ "${#expected}" -eq 40 ] || die 'colour LLVM 期望 SHA 必须是 40 位十六进制数'
  case "$expected" in *[!0-9a-fA-F]*) die 'colour LLVM 期望 SHA 不是十六进制';; esac
  echo "ASSERT colour-manifest-sha expected=${expected,,} actual=${manifest_sha,,}"
  [ "${manifest_sha,,}" = "${expected,,}" ] || die 'colour LLVM tuple MANIFEST LLVM_SHA 与期望值不匹配'
  output=$(strings "$tuple/bin/opt" 2>/dev/null) || die "strings 无法读取 colour LLVM opt: $tuple/bin/opt"
  stamps=$(printf '%s\n' "$output" |
    /usr/bin/grep -Eo 'CJLLVM-COMMIT:[0-9a-fA-F]{40}' || true)
  stamp_hits=$(printf '%s\n' "$stamps" | awk 'NF {n++} END {print n+0}')
  stamp_sha=${stamps#CJLLVM-COMMIT:}
  echo "ASSERT colour-opt-stamp ruler=strings token=CJLLVM-COMMIT:<40hex> hits=$stamp_hits sha=${stamp_sha:-none} file=$tuple/bin/opt"
  [ "$stamp_hits" -eq 1 ] || die "colour LLVM tuple opt 的 CJLLVM-COMMIT 章计数不是 1: hits=$stamp_hits"
  [ "${stamp_sha,,}" = "${manifest_sha,,}" ] || die 'colour LLVM tuple opt 章与 MANIFEST LLVM_SHA 不匹配'
  echo "ASSERT colour-tuple-sums ruler=sha256sum--strict status=ok file=$tuple/SHA256SUMS"
}

assert_official_opt_zero() {
  local opt="$1" output hits
  [ -f "$opt" ] || die "official LLVM opt 不存在: $opt"
  output=$(strings "$opt" 2>/dev/null) || die "strings 无法读取 official LLVM opt: $opt"
  hits=$(printf '%s\n' "$output" | /usr/bin/grep -c 'CJLLVM-COMMIT:' || true)
  echo "ASSERT official-opt-zero ruler=strings token=CJLLVM-COMMIT: hits=$hits file=$opt"
  [ "$hits" -eq 0 ] || die "official LLVM opt 含 colour commit 章 hits=$hits"
}

dynsym_count() {
  local elf="$1" output
  output=$(readelf --dyn-syms --wide "$elf" 2>/dev/null) || die "readelf 无法读取 LLVM ELF: $elf"
  printf '%s\n' "$output" | c++filt |
    awk 'index($0, "llvm::isCJTypedReadHelperCandidate(") {n++} END {print n+0}'
}

assert_llvm() {
  local host="$1" tuple="$2" expected="$3" host_hits
  [ -f "$host" ] || die "host LLVM SO 不存在: $host"
  case "$(basename "$host")" in libLLVM*.so*) ;; *) die "host LLVM SO 文件名不是 libLLVM*.so*: $host";; esac
  assert_colour_tuple "$tuple" "$expected"
  assert_expected_sha host-llvm "$host" "$HOST_LLVM_SHA256"
  host_hits=$(dynsym_count "$host")
  echo "ASSERT host-llvm-zero ruler=readelf--dyn-syms symbol=llvm::isCJTypedReadHelperCandidate hits=$host_hits file=$host"
  [ "$host_hits" -eq 0 ] || die "host LLVM 含 colour 动态符号 hits=$host_hits"
  ok 'host LLVM 动态符号零命中，colour tuple 章与 manifest 匹配'
}

assert_installed_llvm_so() {
  local sdk="$1" source="$2" target expected actual
  target="$sdk/third_party/llvm/lib/$(basename "$source")"
  if [ "$DRY" -eq 1 ]; then
    echo "ASSERT installed-host-llvm-so sha256=planned source=$source target=$target"
    return 0
  fi
  [ -f "$target" ] || die "host LLVM SO 安装位置缺失: $target"
  expected=$(sha256 "$source")
  actual=$(sha256 "$target")
  echo "ASSERT installed-host-llvm-so expected=$expected actual=$actual target=$target"
  [ "$expected" = "$actual" ] || die 'host LLVM SO 安装后 sha256 不一致'
}

# Keep the official compiler SDK intact. Only cjcj processes use this copy.
prepare_stage0_run_sdk() {
  local sdk="$WORK/sdk-stage0-run"
  assert_expected_sha colour-llvm "$COLOUR_LLVM_SO" "$COLOUR_LLVM_SHA256"
  cmd "rm -rf -- $(printf '%q' "$sdk")"
  cmd "cp -aL $(printf '%q' "$WORK/sdk-stage0") $(printf '%q' "$sdk")"
  cmd "install -m644 $(printf '%q' "$COLOUR_LLVM_SO") $(printf '%q' "$sdk/third_party/llvm/lib/libLLVM-15.so")"
  if [ "$DRY" -eq 0 ]; then
    assert_expected_sha installed-colour-llvm "$sdk/third_party/llvm/lib/libLLVM-15.so" "$COLOUR_LLVM_SHA256"
    assert_expected_sha preserved-host-llvm "$WORK/sdk-stage0/third_party/llvm/lib/libLLVM-15.so" "$HOST_LLVM_SHA256"
  fi
}

assert_installed_llvm_tuple() {
  local sdk="$1" tuple="$2" line expected rel target actual count=0
  while IFS= read -r line; do
    expected=${line%% *}
    rel=${line#*  }
    rel=${rel#./}
    [ -n "$rel" ] || continue
    count=$((count+1))
    target="$sdk/third_party/llvm/$rel"
    if [ "$DRY" -eq 1 ]; then
      echo "ASSERT installed-colour-tuple sha256=planned expected=$expected target=$target"
      continue
    fi
    [ -f "$target" ] || die "colour LLVM tuple 安装位置缺失: $target"
    actual=$(sha256 "$target")
    echo "ASSERT installed-colour-tuple expected=$expected actual=$actual target=$target"
    [ "$expected" = "$actual" ] || die "colour LLVM tuple 安装后 sha256 不一致: $rel"
  done < "$tuple/SHA256SUMS"
  [ "$count" -gt 0 ] || die 'colour LLVM tuple 安装断言没有清单输入'
  if [ "$DRY" -eq 0 ]; then
    [ -f "$sdk/third_party/llvm/SHA256SUMS" ] || die 'colour LLVM tuple 安装后缺 SHA256SUMS'
    cmp -s "$tuple/SHA256SUMS" "$sdk/third_party/llvm/SHA256SUMS" ||
      die 'colour LLVM tuple 安装后 SHA256SUMS 不一致'
  fi
}

assert_path() {
  [ -e "$2" ] || die "$1 缺失: $2"
  if [ -d "$2" ]; then
    find "$2" -type f -print -quit | /usr/bin/grep -q . || die "$1 为空: $2"
  else
    [ -s "$2" ] || die "$1 为空: $2"
  fi
  echo "ASSERT $1 exists=1 sha256=$(sha256 "$2")"
}

cmd() {
  local rc started=$SECONDS
  echo "CMD $*"
  [ "$DRY" -eq 1 ] && return 0
  if eval "$*"; then rc=0; else rc=$?; fi
  echo "STEP_RESULT stage=$STAGE rc=$rc wall=$((SECONDS-started))"
  [ "$rc" -eq 0 ] && return 0
  RED "BOOTSTRAP-FAIL [$STAGE] 命令失败 rc=$rc: $*"
  exit "$rc"
}

prepare_build_env() {
  local private="$WORK/tmp-private"
  BUILD_TMPDIR="${TMPDIR:-$private}"
  cmd "mkdir -p $(printf '%q' "$BUILD_TMPDIR")"
  echo "BUILD-ENV planned HOME=$BUILD_HOME TMPDIR=$BUILD_TMPDIR"
}

assert_executable() {
  local label="$1" path="$2"
  if [ "$DRY" -eq 1 ]; then
    echo "ASSERT $label executable=planned path=$path"
  else
    [ -x "$path" ] || die "$label 不存在或不可执行: $path"
    echo "ASSERT $label executable=1 path=$path"
  fi
}

runtime_dir() {
  local root="$1" so
  if [ -f "$root/libcangjie-runtime.so" ]; then
    readlink -f "$root"
    return
  fi
  so=$(find "$root" -type f -name libcangjie-runtime.so -print -quit 2>/dev/null || true)
  if [ -n "$so" ]; then
    dirname "$(readlink -f "$so")"
  else
    readlink -f "$root"
  fi
}

tree_content_sha256() {
  local root="$1"
  [ -d "$root" ] || return 1
  (
    set -o pipefail
    tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
      -C "$root" -cf - . 2>/dev/null | sha256sum | awk '{print $1}'
  )
}

source_identity() {
  local label="$1" root="$2" required_git="${3:-0}" head dirty digest
  head=$(git -C "$root" rev-parse HEAD 2>/dev/null || true)
  if [ -n "$head" ]; then
    if ! dirty=$(git -C "$root" status --porcelain --untracked-files=normal 2>/dev/null); then
      echo "STAGE0_CACHE=disabled reason=${label}-status-failed" >&2
      return 2
    fi
    if [ -n "$dirty" ]; then
      echo "STAGE0_CACHE=disabled reason=${label}-dirty" >&2
      return 2
    fi
    printf 'git:%s' "${head,,}"
    return 0
  fi
  if [ "$required_git" -eq 1 ]; then
    echo "STAGE0_CACHE=disabled reason=${label}-not-git" >&2
    return 2
  fi
  digest=$(tree_content_sha256 "$root") || return 1
  printf 'tree:%s' "$digest"
}

stage0_cache_key() {
  local base="$1" rewritten_toml="$2" cjcj_identity host_runtime_dir host_runtime_so
  local host_nightly compile_options cpp_headers material rel
  cjcj_identity=$(source_identity cjcj "$SRC" 1) || return $?
  host_nightly=$(awk -F= '$1 == "CJCJ_TOOLCHAIN" {print $2}' "$SRC/ci/host_sdk_pin.env" 2>/dev/null || true)
  if [ -z "$host_nightly" ]; then
    echo 'STAGE0_CACHE=disabled reason=host-nightly-pin-missing' >&2
    return 2
  fi
  compile_options=$(awk '/^[[:space:]]*compile-option[[:space:]]*=/ {print}' "$rewritten_toml" 2>/dev/null || true)
  if [ -z "$compile_options" ]; then
    echo 'STAGE0_CACHE=disabled reason=compile-option-missing' >&2
    return 2
  fi
  host_runtime_dir=$(runtime_dir "$HRT")
  host_runtime_so="$host_runtime_dir/libcangjie-runtime.so"
  [ -f "$host_runtime_so" ] || {
    echo "STAGE0_CACHE=disabled reason=host-runtime-so-missing" >&2
    return 2
  }
  cpp_headers=''
  for rel in third_party/llvm-project/llvm/include \
    build/build/third_party/llvm/include build/build/include build/build/schema; do
    cpp_headers="$cpp_headers$rel=$(tree_content_sha256 "$CPP_SRC/$rel")"$'\n' || return 1
  done
  material=$(printf '%s\n' \
    'format=stage0-cache-v2' \
    "cjcj=$cjcj_identity" \
    "host_nightly=$host_nightly" \
    "host_cjc_sha256=$(sha256 "$base/bin/cjc")" \
    "host_llvm_sha256=$(sha256 "$HOST_LLVM_SO")" \
    "host_runtime_so_sha256=$(sha256 "$host_runtime_so")" \
    "ast_support_sha256=$(sha256 "$AST_SUPPORT")" \
    "ast_inputs_sha256=$(sha256 "$(dirname "$AST_SUPPORT")/SHA256SUMS")" \
    "ast_installer_sha256=$(sha256 "$SRC/ci/install_std_sdk_inputs.py")" \
    "build_resources_sha256=$(sha256 "$SRC/ci/build_resources.sh")" \
    "bootstrap_sha256=$(sha256 "${BASH_SOURCE[0]}")" \
    "sdk_build_sha256=$(sha256 "$SDK_BUILD")" \
    "cpp_headers_sha256=$cpp_headers" \
    "cjcj_compile_options=$compile_options")
  printf '%s' "$material" | sha256sum | awk '{print $1}'
}

manifest_value() {
  local manifest="$1" field="$2"
  awk -F '\t' -v field="$field" '$1 == field {print $2}' "$manifest"
}

stage0_cache_restore() {
  local key="$1" out="$2" entry manifest compiler_sha actual
  entry="$STAGE0_CACHE_ROOT/$key"
  manifest="$entry/MANIFEST"
  if [ ! -f "$manifest" ]; then
    echo "STAGE0_CACHE=miss key=$key reason=missing"
    return 1
  fi
  [ "$(manifest_value "$manifest" format)" = 'stage0-cache-v2' ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=format"
    return 1
  }
  [ "$(manifest_value "$manifest" key)" = "$key" ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=key"
    return 1
  }
  compiler_sha=$(manifest_value "$manifest" cjcj_stage1_sha256)
  [ "${#compiler_sha}" -eq 64 ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=manifest-sha"
    return 1
  }
  [ -f "$entry/cjcj-stage1" ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=payload-missing"
    return 1
  }
  actual=$(sha256 "$entry/cjcj-stage1")
  [ "$actual" = "$compiler_sha" ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=cjcj-sha-mismatch"
    return 1
  }
  rm -f -- "$out"
  install -m0755 "$entry/cjcj-stage1" "$out" || return 1
  [ "$(sha256 "$out")" = "$compiler_sha" ] || return 1
  echo "STAGE0_CACHE=hit key=$key path=$entry"
}

stage0_cache_publish() {
  local key="$1" out="$2" entry incoming rejected compiler_sha
  entry="$STAGE0_CACHE_ROOT/$key"
  mkdir -p "$STAGE0_CACHE_ROOT"
  incoming=$(mktemp -d "$STAGE0_CACHE_ROOT/.incoming-$key.XXXXXX") || return 1
  install -m0755 "$out" "$incoming/cjcj-stage1" || return 1
  compiler_sha=$(sha256 "$incoming/cjcj-stage1")
  printf '%s\t%s\n' \
    format stage0-cache-v2 \
    key "$key" \
    cjcj_stage1_sha256 "$compiler_sha" > "$incoming/MANIFEST"
  if [ -e "$entry" ]; then
    rejected="$STAGE0_CACHE_ROOT/.replaced-$key-$$"
    mv "$entry" "$rejected" || return 1
  else
    rejected=''
  fi
  mv "$incoming" "$entry" || return 1
  [ -z "$rejected" ] || rm -rf -- "$rejected"
  echo "STAGE0_CACHE=stored key=$key path=$entry cjcj_sha=$compiler_sha"
}

sdk_ld_path() {
  local sdk="$1" runtime="$2"
  printf '%s' "$(runtime_dir "$runtime"):$sdk/runtime/lib/$HOST_TUPLE:$sdk/lib/$HOST_TUPLE:$sdk/third_party/llvm/lib:$sdk/tools/lib:/usr/lib/$HOST_MULTIARCH"
}

assert_version() {
  local label="$1" compiler="$2" sdk="$3" runtime="$4" ld
  assert_executable "$label" "$compiler"
  ld=$(sdk_ld_path "$sdk" "$runtime")
  cmd "env -i $(compiler_cache_env)HOME=$(printf '%q' "$BUILD_HOME") CANGJIE_HOME=$(printf '%q' "$sdk") LD_LIBRARY_PATH=$(printf '%q' "$ld") PATH=/usr/bin:/bin $(printf '%q' "$compiler") --version"
  [ "$DRY" -eq 1 ] || ok "$label --version rc=0"
}

ffi_manifest() {
  local prefix="$1"
  {
    find "$prefix/lib/$HOST_TUPLE" -maxdepth 1 -type f -iname '*FFI.a' -printf "lib/$HOST_TUPLE/%f\n" 2>/dev/null
    [ -f "$prefix/lib/libstdFFI.so" ] && echo 'lib/libstdFFI.so'
  } | sort
}

assert_std_install_shape() {
  local prefix="$1" compare_prefix="${2:-}" label="${3:-stdlib}" core_a core_so ffi_so ti ffi_archives actual_ffi expected_ffi
  if [ "$DRY" -eq 1 ]; then
    echo "ASSERT $label shape=planned Int64.ti>1 FFI-archives>0${compare_prefix:+ FFI-set-equals=$compare_prefix}"
    return 0
  fi
  core_a="$prefix/lib/$HOST_TUPLE/libcangjie-std-core.a"
  core_so="$prefix/runtime/lib/$HOST_TUPLE/libcangjie-std-core.so"
  ffi_so="$prefix/lib/libstdFFI.so"
  if [ ! -f "$core_a" ] || [ ! -f "$core_so" ] || [ ! -f "$ffi_so" ]; then
    die "$label install shape: core archive/shared 或 libstdFFI.so 缺失"
  fi
  ti=$({ nm -A --defined-only "$core_a" 2>/dev/null; nm -A --defined-only "$core_so" "$ffi_so" 2>/dev/null; } |
    awk '$NF=="Int64.ti"{n++}END{print n+0}')
  [ "$ti" -gt 1 ] || die "$label install shape: Int64.ti definitions=$ti (expected >1)"
  ffi_archives=$(find "$prefix/lib/$HOST_TUPLE" -maxdepth 1 -type f -iname '*FFI.a' -printf '.\n' 2>/dev/null | wc -l)
  [ "$ffi_archives" -gt 0 ] || die "$label install shape: FFI archive set is empty"
  if [ -n "$compare_prefix" ]; then
    [ -d "$compare_prefix" ] || die "$label compare prefix 不存在: $compare_prefix"
    actual_ffi=$(ffi_manifest "$prefix")
    expected_ffi=$(ffi_manifest "$compare_prefix")
    if [ "$actual_ffi" != "$expected_ffi" ]; then
      printf '%s\n' "EXPECTED FFI:" "$expected_ffi" "ACTUAL FFI:" "$actual_ffi" >&2
      die "$label install shape: FFI library set differs from same-run stage0"
    fi
  fi
  echo "ASSERT $label shape=ok Int64.ti=$ti FFI-archives=$ffi_archives${compare_prefix:+ FFI-set-equal=1}"
}

# Keep the caller's C/C++ cache configuration across the isolated build env.
# These are build settings only; GitHub credentials are never forwarded.
compiler_cache_env() {
  local name value
  for name in CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER SCCACHE_PATH SCCACHE_DIR SCCACHE_CACHE_SIZE SCCACHE_IDLE_TIMEOUT SCCACHE_GHA_ENABLED SCCACHE_LOG SCCACHE_ERROR_LOG; do
    eval "value=\${$name-}"
    [ -z "$value" ] || printf '%s=%q ' "$name" "$value"
  done
}

stdlib_build() {
  local label="$1" sdk="$2" runtime="$3" prefix="$4" compare_prefix="${5:-}" target_lib="${6:-$2/runtime/lib/$HOST_TUPLE}" ld script compiler
  source "$SRC/ci/build_resources.sh"
  configure_build_resources "$HEAP" || die "cannot determine std build resources"
  cmd "python3 $(printf '%q' "$SRC/ci/install_std_sdk_inputs.py") $(printf '%q' "$(dirname "$AST_SUPPORT")") $(printf '%q' "$sdk") $(printf '%q' "$HOST_TUPLE")"
  ld=$(sdk_ld_path "$sdk" "$runtime")
  prepare_build_env
  compiler="$sdk/bin/cjc"; [ ! -f "$sdk/bin/cjcj-stage1" ] || compiler="$sdk/bin/cjcj-stage1"
  cmd "node $(printf '%q' "$SRC/ci/bootstrap/std-receipt.mjs") begin $(printf '%q' "$prefix") $(printf '%q' "$STDSRC") $(printf '%q' "$compiler")"
  # shellcheck disable=SC2016 # Expanded by the inner bash, not this shell.
  script='cd "$1" && rm -rf build/build && python3 build.py clean && python3 build.py build -t relwithdebinfo --jobs "$2" --target-lib="$3" && python3 build.py install --prefix "$4"'
  cmd "env -i $(compiler_cache_env)HOME=$(printf '%q' "$BUILD_HOME") TMPDIR=$(printf '%q' "$BUILD_TMPDIR") CANGJIE_HOME=$(printf '%q' "$sdk") LD_LIBRARY_PATH=$(printf '%q' "$ld") PATH=$(printf '%q' "$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:/usr/bin:/bin") cjHeapSize=$(printf '%q' "$STD_BUILD_HEAP") bash -c $(printf '%q' "$script") bash $(printf '%q' "$STDSRC") $(printf '%q' "$STD_BUILD_JOBS") $(printf '%q' "$target_lib") $(printf '%q' "$prefix")"
  assert_std_install_shape "$prefix" "$compare_prefix" "$label"
  # Match sdk_verify.measured_cjc_sha: the runner is only a launcher.
  compiler="$sdk/bin/cjc"
  [ ! -f "$sdk/bin/cjcj-stage1" ] || compiler="$sdk/bin/cjcj-stage1"
  cmd "node $(printf '%q' "$SRC/ci/bootstrap/std-receipt.mjs") finish $(printf '%q' "$prefix") $(printf '%q' "$STDSRC") $(printf '%q' "$compiler")"
}

assert_cjcj_root() {
  [ -d "$SRC" ] || die "--src 必须是含 cjpm.toml 的 cjcj 仓根，拒绝单文件: $SRC"
  [ -f "$SRC/cjpm.toml" ] || die "--src 缺少 cjpm.toml: $SRC"
  echo "ASSERT cjcj-root cjpm.toml=1 path=$SRC/cjpm.toml"
}

isolate_cjcj_src() {
  local dest="$1"
  echo "ISOLATE cjcj-src from=$SRC dest=$dest (user tree untouched)"
  if [ "$DRY" -eq 1 ]; then
    echo "CMD rsync -a --exclude target --exclude /.srcbuild/ $(printf '%q' "$SRC/") $(printf '%q' "$dest/")"
    return 0
  fi
  mkdir -p "$dest"
  cmd "rsync -a --exclude target --exclude /.srcbuild/ $(printf '%q' "$SRC/") $(printf '%q' "$dest/")"
}

rewrite_compile_option_o1() {
  local toml="$1" o1_hits o2_hits
  if [ "$DRY" -eq 1 ]; then
    echo "CMD sed -i s/compile-option = \"-O2\"/compile-option = \"-O1\"/ $(printf '%q' "$toml")"
    echo "ASSERT compile-option-o1 planned file=$toml"
    return 0
  fi
  [ -f "$toml" ] || die "隔离副本缺 cjpm.toml: $toml"
  o2_hits=$(/usr/bin/grep -Ec -- '^ *compile-option = "-O2([[:space:]]|")' "$toml" || true)
  if [ "$o2_hits" -gt 0 ]; then
    cmd "sed -E -i 's/^( *compile-option = \")-O2([[:space:]]|\")/\1-O1\2/' $(printf '%q' "$toml")"
  fi
  o1_hits=$(/usr/bin/grep -Ec -- '^ *compile-option = "-O1([[:space:]]|")' "$toml" || true)
  [ "$o1_hits" -ge 1 ] || die "隔离副本 cjpm.toml 的 compile-option 不是 -O1: $toml"
  o2_hits=$(/usr/bin/grep -Ec -- '^ *compile-option = "-O2([[:space:]]|")' "$toml" || true)
  [ "$o2_hits" -eq 0 ] || die "compile-option 仍含 -O2: $toml"
  echo "ASSERT compile-option-o1 ok file=$toml"
}

resolve_cjpm_product() {
  local bin_dir="$1" label="$2" found="" n=0 f
  if [ "$DRY" -eq 1 ]; then
    echo "ASSERT $label product=planned dir=$bin_dir names=cjc@cjcj|cjcj::cjc"
    printf '%s\n' "$bin_dir/cjcj::cjc"
    return 0
  fi
  [ -d "$bin_dir" ] || die "$label cjpm 产物目录不存在: $bin_dir"
  for f in "$bin_dir/cjc@cjcj" "$bin_dir/cjcj::cjc"; do
    if [ -f "$f" ]; then
      found="$f"
      n=$((n+1))
    fi
  done
  [ "$n" -eq 1 ] || die "$label cjpm 产物缺失或非恰好 1 个（候选 cjc@cjcj / cjcj::cjc）n=$n dir=$bin_dir"
  echo "ASSERT $label product exists=1 path=$found" >&2
  printf '%s\n' "$found"
}

install_stage_compiler() {
  local seed="$1" dest="$2" link="$3"
  cmd "install -m0755 $(printf '%q' "$seed") $(printf '%q' "$dest")"
  cmd "ln -sfn $(printf '%q' "$(basename "$dest")") $(printf '%q' "$link")"
}

cjpm_build() {
  local sdk="$1" runtime="$2" srcdir="$3" extra="$4" heap="$5" ld cjpm script llvm_arg=''
  [ "$WANT" != supplied-stage1 ] || llvm_arg=" $(printf '%q' "$COLOUR_LLVM_SHA")"
  cmd "node $(printf '%q' "$srcdir/ci/check-codegen-runtime-layout.mjs") $(printf '%q' "$WORK/layout-sources") $(printf '%q' "$RUNTIME_PIN")$llvm_arg"
  source "$SRC/ci/build_resources.sh"
  configure_build_resources "$heap" || die "cannot determine compiler build resources"
  heap="$STD_BUILD_HEAP"
  ld=$(sdk_ld_path "$sdk" "$runtime")
  prepare_build_env
  cjpm="$sdk/tools/bin/cjpm"
  local trim_debug=""
  case " $extra " in *" -g "*) trim_debug=" --debug";; esac
  cmd "node $(printf '%q' "$SRC/ci/release/trimpath.mjs") $(printf '%q' "$srcdir")$trim_debug"
  script="cd $(printf '%q' "$srcdir") && $(printf '%q' "$cjpm") build${extra:+ $extra}"
  echo "CMD cjpm build${extra:+ $extra} bin=$cjpm cwd=$srcdir heap=$heap"
  cmd "env -i $(compiler_cache_env)HOME=$(printf '%q' "$BUILD_HOME") TMPDIR=$(printf '%q' "$BUILD_TMPDIR") CANGJIE_HOME=$(printf '%q' "$sdk") LD_LIBRARY_PATH=$(printf '%q' "$ld") PATH=$(printf '%q' "$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:/usr/bin:/bin") cjHeapSize=$(printf '%q' "$heap") bash -c $(printf '%q' "$script")"
}

assert_shim_cpp_src() {
  local rel
  [ -d "$CPP_SRC" ] || die "--cpp-src 不是目录: $CPP_SRC"
  for rel in third_party/llvm-project/llvm/include \
    build/build/third_party/llvm/include build/build/include build/build/schema; do
    [ -d "$CPP_SRC/$rel" ] || die "--cpp-src 缺 shim 头文件目录: $CPP_SRC/$rel"
    find "$CPP_SRC/$rel" -type f -print -quit | /usr/bin/grep -q . ||
      die "--cpp-src shim 头文件目录为空: $CPP_SRC/$rel"
    echo "ASSERT shim-cpp-src exists=1 path=$CPP_SRC/$rel"
  done
}

assert_cjcj_sha() {
  local actual
  [ "${#CJCJ_SHA}" -eq 40 ] || die '--cjcj-sha 必须是 40 位十六进制数'
  case "$CJCJ_SHA" in *[!0-9a-fA-F]*) die '--cjcj-sha 不是十六进制';; esac
  CJCJ_SHA=${CJCJ_SHA,,}
  actual=$(git -C "$SRC" rev-parse HEAD 2>/dev/null || true)
  if [ -n "$actual" ]; then
    echo "ASSERT cjcj-sha expected=$CJCJ_SHA actual=${actual,,} source=git"
    [ "${actual,,}" = "$CJCJ_SHA" ] || die 'cjcj 源码 HEAD 与 --cjcj-sha 不匹配'
  else
    echo "ASSERT cjcj-sha expected=$CJCJ_SHA actual=unavailable source=explicit-pin"
  fi
}

shim_build() {
  local label="$1" sdk="$2" runtime="$3" srcdir="$4" source_object="${5:-}" ld npx_path node_bin source_env=''
  ld=$(sdk_ld_path "$sdk" "$runtime")
  npx_path=$(command -v npx 2>/dev/null || true)
  [ -x "$npx_path" ] || die "$label shim 构建需要可执行 npx"
  node_bin=$(dirname "$npx_path")
  echo "ASSERT $label-npx executable=1 path=$npx_path node-bin=$node_bin"
  if [ -n "$source_object" ]; then
    if [ "$DRY" -eq 0 ]; then
      [ -s "$source_object" ] || die "$label 四件套 shim 对象缺失或为空: $source_object"
    fi
    source_env="CJCJ_LLVM_SHIM_O=$(printf '%q' "$source_object") "
  else
    assert_shim_cpp_src
  fi
  echo "CMD shim build label=$label cwd=$srcdir cpp-src=$CPP_SRC source-object=${source_object:-source} sdk=$sdk runtime=$runtime"
  cmd "rm -f $(printf '%q' "$srcdir/runtime_shim/cjselfhost_llvmshim.o") $(printf '%q' "$srcdir/runtime_shim/cjc_runtime_config.o")"
  cmd "env -i $(compiler_cache_env)HOME=$(printf '%q' "$BUILD_HOME") CANGJIE_HOME=$(printf '%q' "$sdk") CANGJIE_CPP_SRC=$(printf '%q' "$CPP_SRC") CJCJ_COMMIT=$(printf '%q' "$CJCJ_SHA") ${source_env}LD_LIBRARY_PATH=$(printf '%q' "$ld") PATH=$(printf '%q' "$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:$node_bin:/usr/bin:/bin") bash $(printf '%q' "$srcdir/runtime_shim/build_shim.sh")"
  if [ "$DRY" -eq 1 ]; then
    echo "OUTPUT $label-shim-cpp path=$srcdir/runtime_shim/cjselfhost_llvmshim.o sha256=planned"
    echo "OUTPUT $label-shim-config path=$srcdir/runtime_shim/cjc_runtime_config.o sha256=planned"
  else
    record "$label-shim-cpp" "$srcdir/runtime_shim/cjselfhost_llvmshim.o"
    record "$label-shim-config" "$srcdir/runtime_shim/cjc_runtime_config.o"
  fi
}

resolve_base_sdk() {
  local sdk
  if [[ "$BASE_SDK" = /* ]]; then
    sdk="$BASE_SDK"
  else
    sdk="/root/sdks/$BASE_SDK"
    [ -d "$sdk" ] || sdk="/root/.cjv/toolchains/$BASE_SDK"
  fi
  sdk=$(readlink -f "$sdk" 2>/dev/null || true)
  [ -d "$sdk" ] || die "官方 SDK 不存在: $BASE_SDK"
  echo "$sdk"
}

stage0() {
  STAGE=stage0
  echo '[stage0] official cjc + stdlib + host LLVM; cjcj=-O1'
  local base out sdk ld cache_key='' cacheable=0 cache_hit=0
  base=$(resolve_base_sdk)
  record official-sdk "$base"
  assert_official_opt_zero "$base/third_party/llvm/bin/opt"
  record host-llvm-so "$HOST_LLVM_SO"
  record ast-support "$AST_SUPPORT"
  record host-runtime "$HRT"
  record colour-control "$COLOUR_TUPLE"
  assert_expected_sha ast-support "$AST_SUPPORT" "$AST_SUPPORT_SHA256"
  assert_llvm "$HOST_LLVM_SO" "$COLOUR_TUPLE" "$COLOUR_LLVM_SHA"
  assert_cjcj_root
  assert_path cjcj-source "$SRC"
  assert_path stdlib-source "$STDSRC"
  mkdir -p "$WORK"

  out="$WORK/cjcj-stage1"
  sdk="$WORK/sdk-stage0"
  echo "OUTPUT cjcj-stage1=$out"
  cmd "bash $(printf '%q' "$SDK_BUILD") --runtime-pin $(printf '%q' "$RUNTIME_PIN") --from $(printf '%q' "$base") --to $(printf '%q' "$sdk") --host --llvm-so $(printf '%q' "$HOST_LLVM_SO") --colour-runtime $(printf '%q' "$(runtime_dir "$CRT")/libcangjie-runtime.so") --host-runtime $(printf '%q' "$(runtime_dir "$HRT")/libcangjie-runtime.so") --force"
  if [ "$DRY" -eq 0 ]; then
    cmd "python3 $(printf '%q' "$SDK_VERIFY") --sdk $(printf '%q' "$sdk") --role host --runtime-pin $(printf '%q' "$RUNTIME_PIN")"
  fi
  assert_installed_llvm_so "$sdk" "$HOST_LLVM_SO"
  cmd "install -Dm644 $(printf '%q' "$AST_SUPPORT") $(printf '%q' "$sdk/lib/$HOST_TUPLE/libcangjie-ast-support.a")"
  if [ "$DRY" -eq 0 ]; then
    assert_expected_sha installed-ast-support "$sdk/lib/$HOST_TUPLE/libcangjie-ast-support.a" "$AST_SUPPORT_SHA256"
  fi
  ld=$(sdk_ld_path "$sdk" "$HRT")
  local copy seed
  copy="$WORK/cjcj-src-stage0"
  isolate_cjcj_src "$copy"
  rewrite_compile_option_o1 "$copy/cjpm.toml"
  # Cache hits bypass cjpm_build, so validate their source contract here too.
  cmd "node $(printf '%q' "$copy/ci/check-codegen-runtime-layout.mjs") $(printf '%q' "$WORK/layout-sources") $(printf '%q' "$RUNTIME_PIN")"
  if [ "$DRY" -eq 0 ]; then
    if cache_key=$(stage0_cache_key "$base" "$copy/cjpm.toml"); then
      cacheable=1
      if stage0_cache_restore "$cache_key" "$out"; then
        cache_hit=1
        cmd "ln -sfn $(printf '%q' "$(basename "$out")") $(printf '%q' "$WORK/cjc")"
      fi
    fi
  else
    echo 'STAGE0_CACHE=planned key=content-addressed dirty=disabled'
  fi
  if [ "$cache_hit" -eq 0 ]; then
    shim_build stage0 "$sdk" "$HRT" "$copy"
    cjpm_build "$sdk" "$HRT" "$copy" "" "$HEAP"
    seed=$(resolve_cjpm_product "$copy/target/release/bin" cjcj-stage1)
    install_stage_compiler "$seed" "$out" "$WORK/cjc"
  fi
  if [ "$DRY" -eq 0 ]; then
    assert_executable cjcj-stage1 "$out"
  fi
  prepare_stage0_run_sdk
  assert_version cjcj-stage1 "$out" "$WORK/sdk-stage0-run" "$HRT"
  # The Linux x64 layout CI uses the actual seed, including cached seeds. Its
  # host runtime/std stay paired; only the LLVM producer/reader use the target pin.
  if [ "$HOST_TUPLE" = linux_x86_64_cjnative ]; then
    cmd "bash $(printf '%q' "$copy/ci/test-codegen-runtime-layout.sh") $(printf '%q' "$out") $(printf '%q' "$sdk") $(printf '%q' "$COLOUR_LLVM_SO") $(printf '%q' "$WORK/layout-sources/llvm") $(printf '%q' "$WORK/layout-sources/runtime") $(printf '%q' "$WORK/layout-ir-stage0") $(printf '%q' "$RUNTIME_PIN")"
  fi
  if [ "$DRY" -eq 0 ] && [ "$cacheable" -eq 1 ] && [ "$cache_hit" -eq 0 ]; then
    stage0_cache_publish "$cache_key" "$out" || die 'stage0 cache 发布失败'
  fi
  if [ "$DRY" -eq 0 ]; then
    printf '%s\n' "$out" > "$WORK/.cjcj-stage1"
  fi
}

assemble_stage1_sdk() {
  local sdk="$1" compiler="$2" std="$3"
  cmd "bash $(printf '%q' "$SDK_BUILD") --runtime-pin $(printf '%q' "$RUNTIME_PIN") --from $(printf '%q' "$WORK/sdk-stage0") --to $(printf '%q' "$sdk") --target $(printf '%q' "$HOST_TUPLE") --cjc $(printf '%q' "$compiler") --llvm-tuple $(printf '%q' "$COLOUR_TUPLE") --llvm-so $(printf '%q' "$COLOUR_LLVM_SO") --runtime $(printf '%q' "$CRT") --std $(printf '%q' "$std") --verify-host-rt $(printf '%q' "$HRT") --colour-runtime $(printf '%q' "$(runtime_dir "$CRT")/libcangjie-runtime.so") --host-runtime $(printf '%q' "$(runtime_dir "$HRT")/libcangjie-runtime.so") --force"
  if [ "$DRY" -eq 0 ]; then
    cmd "python3 $(printf '%q' "$SDK_VERIFY") --sdk $(printf '%q' "$sdk") --role target --runtime-pin $(printf '%q' "$RUNTIME_PIN")"
  fi
  assert_installed_llvm_tuple "$sdk" "$COLOUR_TUPLE"
  if [ "$DRY" -eq 0 ]; then
    assert_expected_sha target-colour-llvm "$sdk/third_party/llvm/lib/libLLVM-15.so" "$COLOUR_LLVM_SHA256"
  fi
  local compiler_sha=planned
  [ "$DRY" -eq 1 ] || compiler_sha=$(sha256 "$compiler")
  cmd "bash $(printf '%q' "$STAGE1_HOST_RUNNER") $(printf '%q' "$sdk") $(printf '%q' "$WORK/sdk-stage0") $(printf '%q' "$HRT") $(printf '%q' "$HOST_LLVM_SHA256") $(printf '%q' "$compiler") $(printf '%q' "$compiler_sha") $(printf '%q' "$WORK/sdk-stage0-run") $(printf '%q' "$COLOUR_LLVM_SHA256")"
  assert_executable stage1-compiler "$sdk/bin/cjc"
}

# Bootstrap the first coloured std without installing host std beside CRT.
# The temporary SDK stays a host pair; only the output link and native backend
# processes use CRT. It is discarded before the target SDK is assembled.
bootstrap_target_std() {
  local compiler="$1" std="$2" sdk="$WORK/sdk-std-bootstrap" compiler_sha=planned target_lib
  local link_root="$WORK/std-runtime-link" native dynamic file arch
  target_lib=$(runtime_dir "$CRT")
  cmd "bash $(printf '%q' "$SDK_BUILD") --runtime-pin $(printf '%q' "$RUNTIME_PIN") --from $(printf '%q' "$WORK/sdk-stage0") --to $(printf '%q' "$sdk") --host --llvm-tuple $(printf '%q' "$COLOUR_TUPLE") --colour-runtime $(printf '%q' "$(runtime_dir "$CRT")/libcangjie-runtime.so") --host-runtime $(printf '%q' "$(runtime_dir "$HRT")/libcangjie-runtime.so") --force"
  assert_installed_llvm_tuple "$sdk" "$COLOUR_TUPLE"
  cmd "install -m755 $(printf '%q' "$compiler") $(printf '%q' "$sdk/bin/cjc")"
  cmd "install -m644 $(printf '%q' "$COLOUR_LLVM_SO") $(printf '%q' "$sdk/third_party/llvm/lib/libLLVM-15.so")"
  if [ "$DRY" -eq 0 ]; then
    compiler_sha=$(sha256 "$compiler")
    record std-bootstrap-host-std "$sdk/lib/$HOST_TUPLE/libcangjie-std-core.a"
    record std-bootstrap-host-runtime "$sdk/runtime/lib/$HOST_TUPLE/libcangjie-runtime.so"
    record std-bootstrap-target-runtime "$target_lib/libcangjie-runtime.so"
  fi
  cmd "bash $(printf '%q' "$STAGE1_HOST_RUNNER") $(printf '%q' "$sdk") $(printf '%q' "$WORK/sdk-stage0") $(printf '%q' "$HRT") $(printf '%q' "$HOST_LLVM_SHA256") $(printf '%q' "$compiler") $(printf '%q' "$compiler_sha") $(printf '%q' "$WORK/sdk-stage0-run") $(printf '%q' "$COLOUR_LLVM_SHA256") $(printf '%q' "$target_lib")"
  # stdlib's common-layout probe selects the FIRST runtime search path. A
  # bare --target-lib directory is too late: its fallback is the host SDK.
  arch=${HOST_TUPLE#linux_}
  arch=${arch%_cjnative}
  native="$link_root/common/linux_relwithdebinfo_$arch/lib/$HOST_TUPLE"
  dynamic="$link_root/common/linux_relwithdebinfo_$arch/runtime/lib/$HOST_TUPLE"
  cmd "rm -rf -- $(printf '%q' "$link_root")"
  cmd "mkdir -p $(printf '%q' "$native") $(printf '%q' "$dynamic")"
  for file in libcangjie-aio.a cjstart.o cjld.shared.lds discard_eh_frame.lds; do
    cmd "install -m644 $(printf '%q' "$sdk/lib/$HOST_TUPLE/$file") $(printf '%q' "$native/$file")"
    [ "$DRY" -eq 1 ] || record std-bootstrap-native "$native/$file"
  done
  for file in libcangjie-runtime.so libboundscheck.so; do
    cmd "install -m644 $(printf '%q' "$target_lib/$file") $(printf '%q' "$dynamic/$file")"
    [ "$DRY" -eq 1 ] || record std-bootstrap-target "$dynamic/$file"
  done
  stdlib_build stdlib-stage1 "$sdk" "$HRT" "$std" "" "$link_root"
  cmd "python3 $(printf '%q' "$(dirname "$SDK_BUILD")/std_runtime_colour.py") --colour-runtime $(printf '%q' "$(runtime_dir "$CRT")/libcangjie-runtime.so") --host-runtime $(printf '%q' "$(runtime_dir "$HRT")/libcangjie-runtime.so") --runtime $(printf '%q' "$target_lib/libcangjie-runtime.so") --std $(printf '%q' "$std/lib/$HOST_TUPLE/libcangjie-std-core.a") --source $(printf '%q' "$STDSRC")"
  cmd "rm -rf -- $(printf '%q' "$sdk")"
  cmd "rm -rf -- $(printf '%q' "$link_root")"
}

# Each phase is also an independent GHA job. The combined CLI uses the same
# functions, so the std-before-compiler ordering has only one implementation.
stage1_inputs() {
  compiler=$(cat "$WORK/.cjcj-stage1" 2>/dev/null || true)
  previous_std="$WORK/stdlib-stage1"
  if [ "$DRY" -eq 1 ]; then
    compiler="${compiler:-$WORK/cjcj-stage1}"
    echo "INPUT cjcj-stage1 path=$compiler sha256=not-built(dry-run)"
  else
    [ -n "$compiler" ] || die '缺少 stage0 cjcj-stage1'
    record cjcj-stage1 "$compiler"
  fi
  record colour-llvm-tuple "$COLOUR_TUPLE"
  record colour-runtime "$CRT"
  assert_llvm "$HOST_LLVM_SO" "$COLOUR_TUPLE" "$COLOUR_LLVM_SHA"

  out="$WORK/cjcj-stage2"
  std="$WORK/stdlib-stage2"
  sdk="$WORK/sdk-stage1"
}

stage1_initial_std() {
  STAGE=stage1-initial-std
  prepare_stage0_run_sdk
  bootstrap_target_std "$compiler" "$previous_std"
}

stage1_std() {
  STAGE=stage1-std
  assemble_stage1_sdk "$sdk" "$compiler" "$previous_std"
  stdlib_build stdlib-stage2 "$sdk" "$HRT" "$std" "$previous_std"
}

stage1_compiler() {
  local started=$SECONDS
  STAGE=stage1-compiler
  echo "STAGE_BEGIN stage=stage2-compiler epoch=$(date +%s)"
  echo "OUTPUT cjcj-stage2=$out"
  echo "OUTPUT bootstrap-std=$std"
  # The compiler links std statically: consume the completed std from its job.
  assemble_stage1_sdk "$sdk" "$compiler" "$std"
  ld=$(sdk_ld_path "$sdk" "$HRT")
  local copy seed
  copy="$WORK/cjcj-src-stage1"
  isolate_cjcj_src "$copy"
  shim_build stage1 "$sdk" "$CRT" "$copy" "$sdk/third_party/llvm/fixed-llc/cjselfhost_llvmshim.o"
  cjpm_build "$sdk" "$HRT" "$copy" "-j $JOBS" "$STAGE1_HEAP"
  seed=$(resolve_cjpm_product "$copy/target/release/bin" cjcj-stage2)
  install_stage_compiler "$seed" "$out" "$WORK/cjc-stage2"
  if [ "$DRY" -eq 0 ]; then
    assert_executable cjcj-stage2 "$out"
    [ -d "$std" ] || die 'stage1 未产出 stdlib-stage2'
  fi
  assert_version cjcj-stage2 "$out" "$sdk" "$CRT"
  cmd "npx --yes zx@8 $(printf '%q' "$SRC/ci/bootstrap/publish-std-output.mjs") $(printf '%q' "$WORK") $(printf '%q' "$std") $(printf '%q' "$compiler") $(printf '%q' "$HOST_TUPLE")"
  # Forensic arm is opt-in and runs only after the release compiler is installed.
  # It does not rewrite $out. Spec: cjpm `build -g` (default off) lands in
  # target/debug; std RelWithDebInfo already passes -g via AddCangjieSource.cmake.
  stage2_forensic
  echo "STAGE_RESULT stage=stage2-compiler rc=0 wall=$((SECONDS-started))"
}


stage1() {
  STAGE=stage1
  echo '[stage1] cjcj-stage1 self-host + coloured LLVM; C++=RelWithDebInfo'
  local compiler previous_std out std sdk ld
  stage1_inputs
  case "${1:-all}" in
    initial-std) stage1_initial_std;;
    std) stage1_std;;
    compiler) stage1_compiler;;
    all) stage1_initial_std; stage1_std; stage1_compiler;;
  esac
}

# Optional -g stage2 for line tables on cjcj packages. Default off.
# Independent tree; same shim inputs as the release arm; one extra cjpm flag.
stage2_forensic() {
  local copy seed out sdk src_stamp
  [ "${CJCJ_FORENSIC_STAGE2:-0}" = 1 ] || return 0
  sdk="$WORK/sdk-stage1"
  out="$WORK/cjcj-stage2-forensic"
  copy="$WORK/cjcj-src-stage1-forensic"
  echo "OUTPUT cjcj-stage2-forensic=$out"
  echo "FORENSIC stage2 enabled=1 flag=-g product-dir=target/debug/bin source=$copy"
  isolate_cjcj_src "$copy"
  shim_build stage1 "$sdk" "$CRT" "$copy" "$sdk/third_party/llvm/fixed-llc/cjselfhost_llvmshim.o"
  cjpm_build "$sdk" "$HRT" "$copy" "-j $JOBS -g" "$STAGE1_HEAP"
  seed=$(resolve_cjpm_product "$copy/target/debug/bin" cjcj-stage2-forensic)
  install_stage_compiler "$seed" "$out" "$WORK/cjc-stage2-forensic"
  if [ "$DRY" -eq 0 ]; then
    assert_executable cjcj-stage2-forensic "$out"
    record cjcj-stage2-forensic "$out"
    src_stamp="$copy/cjpm.toml"
    record cjcj-stage2-forensic-src "$src_stamp"
    echo "INPUT cjcj-stage2-forensic-cjcj-sha sha256=$CJCJ_SHA"
  else
    echo "INPUT cjcj-stage2-forensic path=$out sha256=planned"
    echo "INPUT cjcj-stage2-forensic-src path=$copy/cjpm.toml sha256=planned"
    echo "INPUT cjcj-stage2-forensic-cjcj-sha sha256=$CJCJ_SHA"
  fi
}

# Supplied-stage1 uses exactly the existing initial std, SDK and compiler
# recipes. There is no stage0 rebuild, second std rebuild, or stage3 here.
supplied_stage1_validate() {
  local value actual
  for value in STAGE1_ELF STAGE1_SHA256 HOST_SDK RUNTIME_SHA HOST_IDENTITIES HOST_IDENTITIES_SHA256; do
    [ -n "${!value}" ] || die "缺少参数 $value (supplied-stage1)"
  done
  [[ "$RUNTIME_SHA" =~ ^[0-9a-f]{40}$ ]] || die 'runtime SHA must be 40 lowercase hex digits'
  if [ -n "$COLOUR_GATE_SOURCE$COLOUR_GATE_INSTALL" ]; then
    if [ -z "$COLOUR_GATE_SOURCE" ] || [ -z "$COLOUR_GATE_INSTALL" ]; then die 'both colour gate inputs required'; fi
    actual=$(git -C "$COLOUR_GATE_SOURCE" rev-parse HEAD) || die 'colour gate source must be a Git checkout'
    [ "$actual" = "$RUNTIME_SHA" ] || die 'colour gate source differs from runtime SHA'
    [ "$(realpath "$STDSRC")" = "$(realpath "$COLOUR_GATE_SOURCE/stdlib")" ] || die 'colour gate requires the runtime checkout stdlib'
    [ -z "$(git -C "$COLOUR_GATE_SOURCE" status --porcelain -- stdlib)" ] || die 'colour gate stdlib source is modified'
  fi
  actual=$(node "$(dirname "${BASH_SOURCE[0]}")/../runtime-pin.mjs" --shell "$RUNTIME_PIN") || die 'runtime selection rejected'
  printf '%s\n' "$actual" | /usr/bin/grep -Fx "RUNTIME_REF='$RUNTIME_SHA'" >/dev/null || die 'runtime SHA differs from runtime pin'
  [ -z "${LD_LIBRARY_PATH:-}" ] || die 'mixed domain: inherited LD_LIBRARY_PATH must be empty'
  [ -z "${CANGJIE_HOME:-}" ] || die 'mixed domain: inherited CANGJIE_HOME must be empty'
  assert_expected_sha host-identities "$HOST_IDENTITIES" "$HOST_IDENTITIES_SHA256"
  export STAGE1_HOST_IDENTITIES="$HOST_IDENTITIES"
  HOST_SDK=$(realpath -e "$HOST_SDK") || die 'missing host SDK'
  WORK=$(realpath -m "$WORK")
  case "$WORK" in /|/root|/root/sdks|/root/sdks/*|/root/.cjv|/root/.cjv/*) die 'private work directory required';; esac
  case "$HOST_SDK/" in "$WORK/"*) die 'host SDK must be outside work directory';; esac
  if [ "$RESUME_COLOUR_GATE" -eq 1 ]; then
    [ -n "$COLOUR_GATE_SOURCE" ] || die 'resume requires the complete colour gate'
    [ -f "$RESUME_STD_SUMS" ] || die 'resume requires captured same-source std hashes'
    npx --yes zx@8 "$SRC/ci/bootstrap/verify-resume-std.mjs" "$WORK" "$RESUME_STD_SUMS" "$COLOUR_GATE_SOURCE" "$RUNTIME_SHA" "$STAGE1_SHA256" || die 'resume retained input identity mismatch'
    assert_expected_sha resumed-stage1 "$WORK/cjcj-stage1" "$STAGE1_SHA256"
  else
    [ ! -e "$WORK" ] || die 'supplied-stage1 refuses an existing work directory'
  fi
  [ -x "$STAGE1_ELF" ] || die 'stage1 ELF is not executable'
  readelf -h "$STAGE1_ELF" >/dev/null || die 'stage1 input must be ELF'
  assert_expected_sha stage1 "$STAGE1_ELF" "$STAGE1_SHA256"
  assert_expected_sha host-llvm "$HOST_LLVM_SO" "$HOST_LLVM_SHA256"
  assert_expected_sha colour-llvm "$COLOUR_LLVM_SO" "$COLOUR_LLVM_SHA256"
  assert_expected_sha ast-support "$AST_SUPPORT" "$AST_SUPPORT_SHA256"
  assert_colour_tuple "$COLOUR_TUPLE" "$COLOUR_LLVM_SHA"
  # The assembler verifies the runtime commit and colour against these inputs.
  strings "$(runtime_dir "$CRT")/libcangjie-runtime.so" | /usr/bin/grep -Fx "CJRT-COMMIT:$RUNTIME_SHA" >/dev/null || die 'runtime artifact commit differs from explicit SHA'
  [ -f "$STDSRC/build.py" ] || die 'missing std source build.py'
  [ -x "$HOST_SDK/tools/bin/cjpm" ] || die 'missing host cjpm'
  echo 'SUPPLIED-STAGE1-INPUTS-OK (identity/domain checks only; no compilation)'
}

supplied_stage1() {
  local out std sdk compiler previous_std
  if [ "$RESUME_COLOUR_GATE" -eq 1 ]; then
    stage1_inputs
    echo 'RESUME colour-runtime-gate: captured same-source std and SDK inputs verified'
  else
    cmd "mkdir -p $(printf '%q' "$WORK")"
    cmd "cp -aL $(printf '%q' "$HOST_SDK") $(printf '%q' "$WORK/sdk-stage0")"
    cmd "python3 $(printf '%q' "$SRC/ci/install_std_sdk_inputs.py") $(printf '%q' "$(dirname "$AST_SUPPORT")") $(printf '%q' "$WORK/sdk-stage0") $(printf '%q' "$HOST_TUPLE")"
    cmd "install -m755 $(printf '%q' "$STAGE1_ELF") $(printf '%q' "$WORK/cjcj-stage1")"
    printf '%s\n' "$WORK/cjcj-stage1" > "$WORK/.cjcj-stage1"
    stage1_inputs
    stage1_initial_std
  fi
  # The full std just produced is the stage2 compiler's static-link input.
  std="$previous_std"
  if [ -n "${COLOUR_GATE_SOURCE:-}${COLOUR_GATE_INSTALL:-}" ]; then STAGE=colour-runtime-gate; assemble_stage1_sdk "$sdk" "$compiler" "$std"; cmd "npx --yes zx@8 $(printf '%q' "$SRC/ci/release/gate_colour_runtime.mjs") --build-sdk $(printf '%q' "${COLOUR_GATE_SOURCE:?colour gate source}") $(printf '%q' "$sdk") $(printf '%q' "$WORK/colour-gate-active") $(printf '%q' "${COLOUR_GATE_INSTALL:?colour gate install}")"; fi
  stage1_compiler
  STAGE=stage2-smoke
  printf 'main(): Int64 { return 0 }\n' > "$WORK/main.cj"
  cmd "env -i HOME=$(printf '%q' "$BUILD_HOME") CANGJIE_HOME=$(printf '%q' "$sdk") PATH=$(printf '%q' "$sdk/bin:/usr/bin:/bin") LD_LIBRARY_PATH=$(printf '%q' "$(sdk_ld_path "$sdk" "$CRT")") $(printf '%q' "$out") $(printf '%q' "$WORK/main.cj") -o $(printf '%q' "$WORK/main")"
  cmd "env -i PATH=/usr/bin:/bin LD_LIBRARY_PATH=$(printf '%q' "$(runtime_dir "$CRT"):$sdk/lib/$HOST_TUPLE") $(printf '%q' "$WORK/main")"
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --host-identities) HOST_IDENTITIES="${2:?}"; shift 2;;
      --host-identities-sha256) HOST_IDENTITIES_SHA256="${2:?}"; shift 2;;
      --stage1-elf) STAGE1_ELF="${2:?}"; shift 2;;
      --stage1-sha256) STAGE1_SHA256="${2:?}"; shift 2;;
      --host-sdk) HOST_SDK="${2:?}"; shift 2;;
      --runtime-sha) RUNTIME_SHA="${2:?}"; shift 2;;
      --colour-gate-source) COLOUR_GATE_SOURCE="${2:?}"; shift 2;;
      --colour-gate-install) COLOUR_GATE_INSTALL="${2:?}"; shift 2;;
      --resume-colour-gate) RESUME_COLOUR_GATE=1; RESUME_STD_SUMS="${2:?captured std sha256 file}"; shift 2;;
      --check-only) CHECK_ONLY=1; shift;;
      --work) WORK="${2:?}"; shift 2;;
      --runtime-pin) RUNTIME_PIN="${2:?}"; shift 2;;
      --src) SRC="${2:?}"; shift 2;;
      --cjcj-sha) CJCJ_SHA="${2:?}"; shift 2;;
      --stdsrc) STDSRC="${2:?}"; shift 2;;
      --cpp-src) CPP_SRC="${2:?}"; shift 2;;
      --base) BASE_SDK="${2:?}"; shift 2;;
      --host-llvm-so) HOST_LLVM_SO="${2:?}"; shift 2;;
      --host-llvm|--host-llc) die "参数 $1 已废弃；使用 --host-llvm-so <libLLVM-15.so>";;
      --host-llvm-sha256) HOST_LLVM_SHA256="${2:?}"; shift 2;;
      --colour-llvm-so) COLOUR_LLVM_SO="${2:?}"; shift 2;;
      --colour-llvm-sha256) COLOUR_LLVM_SHA256="${2:?}"; shift 2;;
      --ast-support|--ast-support-a) AST_SUPPORT="${2:?}"; shift 2;;
      --ast-support-sha256) AST_SUPPORT_SHA256="${2:?}"; shift 2;;
      --colour-tuple) COLOUR_TUPLE="${2:?}"; shift 2;;
      --colour-llvm-sha) COLOUR_LLVM_SHA="${2:?}"; shift 2;;
      --colour-llc) die '参数 --colour-llc 已废弃；使用 --colour-tuple <depot目录>';;
      --colour-rt) CRT="${2:?}"; shift 2;;
      --host-rt) HRT="${2:?}"; shift 2;;
      --stage) WANT="${2:?}"; shift 2;;
      --stage1-heap) STAGE1_HEAP="${2:?}"; shift 2;;
      --dry-run) DRY=1; shift;;
      -h|--help) usage; exit 0;;
      *) die "未知参数 $1";;
    esac
  done
  local value
  for value in WORK SRC CJCJ_SHA STDSRC HOST_LLVM_SO HOST_LLVM_SHA256 COLOUR_LLVM_SO COLOUR_LLVM_SHA256 AST_SUPPORT AST_SUPPORT_SHA256 COLOUR_TUPLE COLOUR_LLVM_SHA CRT HRT; do
    eval "[ -n \"\${$value}\" ]" || die "缺少参数 $value"
  done
  [ -z "$COLOUR_GATE_SOURCE$COLOUR_GATE_INSTALL" ] || [ "$WANT" = supplied-stage1 ] || die 'colour gate requires supplied-stage1'
  [ "$RESUME_COLOUR_GATE" -eq 0 ] || [ "$WANT" = supplied-stage1 ] || die 'resume requires supplied-stage1'
  case "$WANT" in supplied-stage1|stage0|stage1|stage1-initial-std|stage1-std|stage1-compiler|all) ;; *) die '--stage 只能是 stage0|stage1|stage1-initial-std|stage1-std|stage1-compiler|all';; esac
  case "$WANT" in
    stage0|all) [ -n "$CPP_SRC" ] || die '缺少参数 CPP_SRC';;
  esac
  RUNTIME_PIN="${RUNTIME_PIN:-$(dirname "${BASH_SOURCE[0]}")/../runtime_pin.env}"
  RUNTIME_PIN=$(realpath "$RUNTIME_PIN")
  node "$(dirname "${BASH_SOURCE[0]}")/../runtime-pin.mjs" --shell "$RUNTIME_PIN" >/dev/null || die "runtime selection rejected"
  record runtime-pin "$RUNTIME_PIN"
  host_tuple_init
  assert_cjcj_sha
  assert_cjcj_root
  if [ "$WANT" = supplied-stage1 ]; then
    [ "$DRY" -eq 0 ] || die 'use --check-only for supplied-stage1 static validation'
    supplied_stage1_validate
    [ "$CHECK_ONLY" -eq 0 ] || return 0
  elif [ "$CHECK_ONLY" -eq 1 ]; then
    die '--check-only requires --stage supplied-stage1'
  fi
  case "$WANT" in
    supplied-stage1) supplied_stage1;;
    stage0) stage0;;
    stage1) stage1;;
    stage1-initial-std) stage1 initial-std;;
    stage1-std) stage1 std;;
    stage1-compiler) stage1 compiler;;
    all) stage0; stage1;;
  esac
  echo "BOOTSTRAP-OK 到 $WANT work=$WORK"
  if [ "$DRY" -eq 1 ]; then
    echo 'DRY-RUN: no compilation performed'
  fi
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  main "$@"
fi
