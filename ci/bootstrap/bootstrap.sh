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
COLOUR_TUPLE=''
COLOUR_LLVM_SHA=''
CRT=''
HRT=''
AST_SUPPORT=''
AST_SUPPORT_SHA256=''
CPP_SRC=''
CJCJ_SHA=''
BASE_SDK="${BASE_SDK:-cjcj-pin-937877c8}"
HEAP="${CJ_HEAP:-24GB}"
STAGE1_HEAP="${STAGE1_HEAP:-20GB}"
JOBS="${CJ_JOBS:-32}"
SDK_BUILD="${SDK_BUILD:-/root/cj_build/tools/sdk_build.sh}"
STAGE1_HOST_RUNNER="${STAGE1_HOST_RUNNER:-$(dirname "${BASH_SOURCE[0]}")/stage1_host_runner.sh}"
STAGE0_CACHE_ROOT="${STAGE0_CACHE_ROOT:-/root/stage0depot}"
BUILD_TMPDIR=''
STAGE=init
WANT=all
DRY=0

usage() {
  echo 'bootstrap.sh --work DIR --src CJCJ_ROOT --cjcj-sha 40HEX --stdsrc STDLIB --cpp-src CANGJIE_CPP_ROOT --host-llvm-so libLLVM-15.so --host-llvm-sha256 HEX --ast-support FILE --ast-support-sha256 HEX --colour-tuple DIR --colour-llvm-sha 40HEX --colour-rt DIR --host-rt DIR [--stage stage0|stage1|all] [--stage1-heap 20GB] [--dry-run]'
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
  [ "$entries" -eq 8 ] || die "colour LLVM tuple SHA256SUMS 必须且只能登记 8 个 payload: entries=$entries"
  for rel in MANIFEST bin/llc bin/opt lib/STATIC_LLVM.txt \
    fixed-llc/cjselfhost_llvmshim.o fixed-llc/llc.gz \
    fixed-llc/opt.gz fixed-llc/llvm-tools.manifest; do
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
  local rc
  echo "CMD $*"
  [ "$DRY" -eq 1 ] && return 0
  eval "$*" && return 0
  rc=$?
  die "命令失败 rc=$rc: $*"
}

prepare_build_env() {
  local private="$WORK/tmp-private"
  BUILD_TMPDIR="${TMPDIR:-$private}"
  cmd "mkdir -p $(printf '%q' "$BUILD_TMPDIR")"
  echo "BUILD-ENV planned HOME=/root TMPDIR=$BUILD_TMPDIR"
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
  local base="$1" rewritten_toml="$2" cjcj_identity stdlib_identity host_runtime_dir host_runtime_so
  local host_nightly compile_options cpp_headers material rel
  cjcj_identity=$(source_identity cjcj "$SRC" 1) || return $?
  stdlib_identity=$(source_identity stdlib "$STDSRC" 0) || return $?
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
    'format=stage0-cache-v1' \
    "cjcj=$cjcj_identity" \
    "stdlib=$stdlib_identity" \
    "host_nightly=$host_nightly" \
    "host_cjc_sha256=$(sha256 "$base/bin/cjc")" \
    "host_llvm_sha256=$(sha256 "$HOST_LLVM_SO")" \
    "host_runtime_so_sha256=$(sha256 "$host_runtime_so")" \
    "ast_support_sha256=$(sha256 "$AST_SUPPORT")" \
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
  local key="$1" out="$2" std="$3" entry manifest compiler_sha stdlib_sha actual
  entry="$STAGE0_CACHE_ROOT/$key"
  manifest="$entry/MANIFEST"
  if [ ! -f "$manifest" ]; then
    echo "STAGE0_CACHE=miss key=$key reason=missing"
    return 1
  fi
  [ "$(manifest_value "$manifest" format)" = 'stage0-cache-v1' ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=format"
    return 1
  }
  [ "$(manifest_value "$manifest" key)" = "$key" ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=key"
    return 1
  }
  compiler_sha=$(manifest_value "$manifest" cjcj_stage1_sha256)
  stdlib_sha=$(manifest_value "$manifest" stdlib_stage1_sha256)
  [ "${#compiler_sha}" -eq 64 ] && [ "${#stdlib_sha}" -eq 64 ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=manifest-sha"
    return 1
  }
  [ -f "$entry/cjcj-stage1" ] && [ -d "$entry/stdlib-stage1" ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=payload-missing"
    return 1
  }
  actual=$(sha256 "$entry/cjcj-stage1")
  [ "$actual" = "$compiler_sha" ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=cjcj-sha-mismatch"
    return 1
  }
  actual=$(tree_content_sha256 "$entry/stdlib-stage1")
  [ "$actual" = "$stdlib_sha" ] || {
    echo "STAGE0_CACHE=rejected key=$key reason=stdlib-sha-mismatch"
    return 1
  }
  rm -rf -- "$out" "$std"
  install -m0755 "$entry/cjcj-stage1" "$out" || return 1
  cp -a "$entry/stdlib-stage1" "$std" || return 1
  [ "$(sha256 "$out")" = "$compiler_sha" ] || return 1
  [ "$(tree_content_sha256 "$std")" = "$stdlib_sha" ] || return 1
  echo "STAGE0_CACHE=hit key=$key path=$entry"
}

stage0_cache_publish() {
  local key="$1" out="$2" std="$3" entry incoming rejected compiler_sha stdlib_sha
  entry="$STAGE0_CACHE_ROOT/$key"
  mkdir -p "$STAGE0_CACHE_ROOT"
  incoming=$(mktemp -d "$STAGE0_CACHE_ROOT/.incoming-$key.XXXXXX") || return 1
  install -m0755 "$out" "$incoming/cjcj-stage1" || return 1
  cp -a "$std" "$incoming/stdlib-stage1" || return 1
  compiler_sha=$(sha256 "$incoming/cjcj-stage1")
  stdlib_sha=$(tree_content_sha256 "$incoming/stdlib-stage1")
  printf '%s\t%s\n' \
    format stage0-cache-v1 \
    key "$key" \
    cjcj_stage1_sha256 "$compiler_sha" \
    stdlib_stage1_sha256 "$stdlib_sha" > "$incoming/MANIFEST"
  if [ -e "$entry" ]; then
    rejected="$STAGE0_CACHE_ROOT/.replaced-$key-$$"
    mv "$entry" "$rejected" || return 1
  else
    rejected=''
  fi
  mv "$incoming" "$entry" || return 1
  [ -z "$rejected" ] || rm -rf -- "$rejected"
  echo "STAGE0_CACHE=stored key=$key path=$entry cjcj_sha=$compiler_sha stdlib_sha=$stdlib_sha"
}

sdk_ld_path() {
  local sdk="$1" runtime="$2"
  printf '%s' "$(runtime_dir "$runtime"):$sdk/runtime/lib/linux_x86_64_cjnative:$sdk/lib/linux_x86_64_cjnative:$sdk/third_party/llvm/lib:$sdk/tools/lib:/usr/lib/x86_64-linux-gnu"
}

assert_version() {
  local label="$1" compiler="$2" sdk="$3" runtime="$4" ld
  assert_executable "$label" "$compiler"
  ld=$(sdk_ld_path "$sdk" "$runtime")
  cmd "env -i HOME=/root CANGJIE_HOME=$(printf '%q' "$sdk") LD_LIBRARY_PATH=$(printf '%q' "$ld") PATH=/usr/bin:/bin $(printf '%q' "$compiler") --version"
  [ "$DRY" -eq 1 ] || ok "$label --version rc=0"
}

ffi_manifest() {
  local prefix="$1"
  {
    find "$prefix/lib/linux_x86_64_cjnative" -maxdepth 1 -type f -iname '*FFI.a' -printf 'lib/linux_x86_64_cjnative/%f\n' 2>/dev/null
    [ -f "$prefix/lib/libstdFFI.so" ] && echo 'lib/libstdFFI.so'
  } | sort
}

assert_std_install_shape() {
  local prefix="$1" compare_prefix="${2:-}" label="${3:-stdlib}" core_a core_so ffi_so ti ffi_archives actual_ffi expected_ffi
  if [ "$DRY" -eq 1 ]; then
    echo "ASSERT $label shape=planned Int64.ti>1 FFI-archives>0${compare_prefix:+ FFI-set-equals=$compare_prefix}"
    return 0
  fi
  core_a="$prefix/lib/linux_x86_64_cjnative/libcangjie-std-core.a"
  core_so="$prefix/runtime/lib/linux_x86_64_cjnative/libcangjie-std-core.so"
  ffi_so="$prefix/lib/libstdFFI.so"
  if [ ! -f "$core_a" ] || [ ! -f "$core_so" ] || [ ! -f "$ffi_so" ]; then
    die "$label install shape: core archive/shared 或 libstdFFI.so 缺失"
  fi
  ti=$({ nm -A --defined-only "$core_a" 2>/dev/null; nm -A --defined-only "$core_so" "$ffi_so" 2>/dev/null; } |
    awk '$NF=="Int64.ti"{n++}END{print n+0}')
  [ "$ti" -gt 1 ] || die "$label install shape: Int64.ti definitions=$ti (expected >1)"
  ffi_archives=$(find "$prefix/lib/linux_x86_64_cjnative" -maxdepth 1 -type f -iname '*FFI.a' -printf '.\n' 2>/dev/null | wc -l)
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

stdlib_build() {
  local label="$1" sdk="$2" runtime="$3" prefix="$4" compare_prefix="${5:-}" ld script
  ld=$(sdk_ld_path "$sdk" "$runtime")
  prepare_build_env
  # shellcheck disable=SC2016 # Expanded by the inner bash, not this shell.
  script='cd "$1" && rm -rf build/build && python3 build.py clean && python3 build.py build -t relwithdebinfo --jobs "$2" --target-lib="$3" && python3 build.py install --prefix "$4"'
  cmd "env -i HOME=/root TMPDIR=$(printf '%q' "$BUILD_TMPDIR") CANGJIE_HOME=$(printf '%q' "$sdk") LD_LIBRARY_PATH=$(printf '%q' "$ld") PATH=$(printf '%q' "$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:/usr/bin:/bin") cjHeapSize=$(printf '%q' "$HEAP") bash -c $(printf '%q' "$script") bash $(printf '%q' "$STDSRC") $(printf '%q' "$JOBS") $(printf '%q' "$sdk/runtime/lib/linux_x86_64_cjnative") $(printf '%q' "$prefix")"
  assert_std_install_shape "$prefix" "$compare_prefix" "$label"
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
    echo "CMD rsync -a --exclude target $(printf '%q' "$SRC/") $(printf '%q' "$dest/")"
    return 0
  fi
  mkdir -p "$dest"
  cmd "rsync -a --exclude target $(printf '%q' "$SRC/") $(printf '%q' "$dest/")"
}

rewrite_compile_option_o1() {
  local toml="$1" o1_hits o2_hits
  if [ "$DRY" -eq 1 ]; then
    echo "CMD sed -i s/compile-option = \"-O2\"/compile-option = \"-O1\"/ $(printf '%q' "$toml")"
    echo "ASSERT compile-option-o1 planned file=$toml"
    return 0
  fi
  [ -f "$toml" ] || die "隔离副本缺 cjpm.toml: $toml"
  o2_hits=$(/usr/bin/grep -c -- 'compile-option = "-O2"' "$toml" || true)
  if [ "$o2_hits" -gt 0 ]; then
    cmd "sed -i 's/compile-option = \"-O2\"/compile-option = \"-O1\"/' $(printf '%q' "$toml")"
  fi
  o1_hits=$(/usr/bin/grep -c -- 'compile-option = "-O1"' "$toml" || true)
  [ "$o1_hits" -ge 1 ] || die "隔离副本 cjpm.toml 的 compile-option 不是 -O1: $toml"
  o2_hits=$(/usr/bin/grep -c -- 'compile-option = "-O2"' "$toml" || true)
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
  local sdk="$1" runtime="$2" srcdir="$3" extra="$4" heap="$5" ld cjpm script
  ld=$(sdk_ld_path "$sdk" "$runtime")
  prepare_build_env
  cjpm="$sdk/tools/bin/cjpm"
  script="cd $(printf '%q' "$srcdir") && $(printf '%q' "$cjpm") build${extra:+ $extra}"
  echo "CMD cjpm build${extra:+ $extra} bin=$cjpm cwd=$srcdir heap=$heap"
  cmd "env -i HOME=/root TMPDIR=$(printf '%q' "$BUILD_TMPDIR") CANGJIE_HOME=$(printf '%q' "$sdk") LD_LIBRARY_PATH=$(printf '%q' "$ld") PATH=$(printf '%q' "$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:/usr/bin:/bin") cjHeapSize=$(printf '%q' "$heap") bash -c $(printf '%q' "$script")"
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
  cmd "env -i HOME=/root CANGJIE_HOME=$(printf '%q' "$sdk") CANGJIE_CPP_SRC=$(printf '%q' "$CPP_SRC") CJCJ_COMMIT=$(printf '%q' "$CJCJ_SHA") ${source_env}LD_LIBRARY_PATH=$(printf '%q' "$ld") PATH=$(printf '%q' "$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:$node_bin:/usr/bin:/bin") bash $(printf '%q' "$srcdir/runtime_shim/build_shim.sh")"
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
  local base out std sdk ld cache_key='' cacheable=0 cache_hit=0
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
  std="$WORK/stdlib-stage1"
  sdk="$WORK/sdk-stage0"
  echo "OUTPUT cjcj-stage1=$out"
  echo "OUTPUT stdlib-stage1=$std"
  cmd "bash $(printf '%q' "$SDK_BUILD") --from $(printf '%q' "$base") --to $(printf '%q' "$sdk") --host --llvm-so $(printf '%q' "$HOST_LLVM_SO") --force"
  assert_installed_llvm_so "$sdk" "$HOST_LLVM_SO"
  cmd "install -Dm644 $(printf '%q' "$AST_SUPPORT") $(printf '%q' "$sdk/lib/linux_x86_64_cjnative/libcangjie-ast-support.a")"
  if [ "$DRY" -eq 0 ]; then
    assert_expected_sha installed-ast-support "$sdk/lib/linux_x86_64_cjnative/libcangjie-ast-support.a" "$AST_SUPPORT_SHA256"
  fi
  ld=$(sdk_ld_path "$sdk" "$HRT")
  local copy seed
  copy="$WORK/cjcj-src-stage0"
  isolate_cjcj_src "$copy"
  rewrite_compile_option_o1 "$copy/cjpm.toml"
  if [ "$DRY" -eq 0 ]; then
    if cache_key=$(stage0_cache_key "$base" "$copy/cjpm.toml"); then
      cacheable=1
      if stage0_cache_restore "$cache_key" "$out" "$std"; then
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
    stdlib_build stdlib-stage1 "$sdk" "$HRT" "$std"
  fi
  if [ "$DRY" -eq 0 ]; then
    assert_executable cjcj-stage1 "$out"
    [ -d "$std" ] || die 'stage0 未产出 stdlib-stage1'
  fi
  assert_version cjcj-stage1 "$out" "$sdk" "$HRT"
  if [ "$DRY" -eq 0 ] && [ "$cacheable" -eq 1 ] && [ "$cache_hit" -eq 0 ]; then
    stage0_cache_publish "$cache_key" "$out" "$std" || die 'stage0 cache 发布失败'
  fi
  if [ "$DRY" -eq 0 ]; then
    printf '%s\n' "$out" > "$WORK/.cjcj-stage1"
    printf '%s\n' "$std" > "$WORK/.stdlib-stage1"
  fi
}

stage1() {
  STAGE=stage1
  echo '[stage1] cjcj-stage1 self-host + coloured LLVM; C++=RelWithDebInfo'
  local compiler previous_std out std sdk ld
  compiler=$(cat "$WORK/.cjcj-stage1" 2>/dev/null || true)
  previous_std=$(cat "$WORK/.stdlib-stage1" 2>/dev/null || true)
  if [ "$DRY" -eq 1 ]; then
    compiler="${compiler:-$WORK/cjcj-stage1}"
    previous_std="${previous_std:-$WORK/stdlib-stage1}"
    echo "INPUT cjcj-stage1 path=$compiler sha256=not-built(dry-run)"
    echo "INPUT stdlib-stage1 path=$previous_std sha256=not-built(dry-run)"
  else
    [ -n "$compiler" ] || die '缺少 stage0 cjcj-stage1'
    [ -n "$previous_std" ] || die '缺少 stage1 stdlib'
    record cjcj-stage1 "$compiler"
    record stdlib-stage1 "$previous_std"
  fi
  record colour-llvm-tuple "$COLOUR_TUPLE"
  record colour-runtime "$CRT"
  assert_llvm "$HOST_LLVM_SO" "$COLOUR_TUPLE" "$COLOUR_LLVM_SHA"

  out="$WORK/cjcj-stage2"
  std="$WORK/stdlib-stage2"
  sdk="$WORK/sdk-stage1"
  echo "OUTPUT cjcj-stage2=$out"
  echo "OUTPUT stdlib-stage2=$std"
  cmd "bash $(printf '%q' "$SDK_BUILD") --from $(printf '%q' "$WORK/sdk-stage0") --to $(printf '%q' "$sdk") --target --cjc $(printf '%q' "$compiler") --llvm-tuple $(printf '%q' "$COLOUR_TUPLE") --runtime $(printf '%q' "$CRT") --std $(printf '%q' "$previous_std") --verify-host-rt $(printf '%q' "$HRT") --force"
  assert_installed_llvm_tuple "$sdk" "$COLOUR_TUPLE"
  local compiler_sha=planned
  [ "$DRY" -eq 1 ] || compiler_sha=$(sha256 "$compiler")
  cmd "bash $(printf '%q' "$STAGE1_HOST_RUNNER") $(printf '%q' "$sdk") $(printf '%q' "$WORK/sdk-stage0") $(printf '%q' "$HRT") $(printf '%q' "$HOST_LLVM_SHA256") $(printf '%q' "$compiler") $(printf '%q' "$compiler_sha")"
  assert_executable stage1-compiler "$sdk/bin/cjc"
  ld=$(sdk_ld_path "$sdk" "$CRT")
  local copy seed
  copy="$WORK/cjcj-src-stage1"
  isolate_cjcj_src "$copy"
  shim_build stage1 "$sdk" "$CRT" "$copy" "$sdk/third_party/llvm/fixed-llc/cjselfhost_llvmshim.o"
  cjpm_build "$sdk" "$CRT" "$copy" "-j 1" "$STAGE1_HEAP"
  seed=$(resolve_cjpm_product "$copy/target/release/bin" cjcj-stage2)
  install_stage_compiler "$seed" "$out" "$WORK/cjc-stage2"
  stdlib_build stdlib-stage2 "$sdk" "$CRT" "$std" "$previous_std"
  if [ "$DRY" -eq 0 ]; then
    assert_executable cjcj-stage2 "$out"
    [ -d "$std" ] || die 'stage1 未产出 stdlib-stage2'
  fi
  assert_version cjcj-stage2 "$out" "$sdk" "$CRT"
}

main() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --work) WORK="${2:?}"; shift 2;;
      --src) SRC="${2:?}"; shift 2;;
      --cjcj-sha) CJCJ_SHA="${2:?}"; shift 2;;
      --stdsrc) STDSRC="${2:?}"; shift 2;;
      --cpp-src) CPP_SRC="${2:?}"; shift 2;;
      --base) BASE_SDK="${2:?}"; shift 2;;
      --host-llvm-so) HOST_LLVM_SO="${2:?}"; shift 2;;
      --host-llvm|--host-llc) die "参数 $1 已废弃；使用 --host-llvm-so <libLLVM-15.so>";;
      --host-llvm-sha256) HOST_LLVM_SHA256="${2:?}"; shift 2;;
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
  for value in WORK SRC CJCJ_SHA STDSRC HOST_LLVM_SO HOST_LLVM_SHA256 AST_SUPPORT AST_SUPPORT_SHA256 COLOUR_TUPLE COLOUR_LLVM_SHA CRT HRT; do
    eval "[ -n \"\${$value}\" ]" || die "缺少参数 $value"
  done
  case "$WANT" in stage0|stage1|all) ;; *) die '--stage 只能是 stage0|stage1|all';; esac
  case "$WANT" in
    stage0|all) [ -n "$CPP_SRC" ] || die '缺少参数 CPP_SRC';;
  esac
  assert_cjcj_sha
  assert_cjcj_root
  case "$WANT" in
    stage0) stage0;;
    stage1) stage1;;
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
