#!/bin/bash
# Purpose: assemble an isolated custom SDK; callers: bootstrap.sh and SDK build lanes.
# 组装一枚定制 SDK —— ⭐ 公用工具，⛔ 别再每条 lane 手搓一遍
#
# ⛔⛔⛔ 为什么要有它（⭐ 全是 0807-0808 的实账）：
#   ⭐ **宿主 runtime 着色** ⇒ 宿主 cjc 0.46 秒 SIGSEGV。⭐ 至少两条 lane 各踩一次。
#   ⭐ **拿被换过的共享 SDK 当基线** ⇒ `nightly-…0619/bin/cjc` 的 RUNPATH 指向某 lane 私有树
#     ⇒ ⭐⭐ 它实际链的是系统 LLVM ⇒ ⭐ 我差点拿它论证"官方布局"
#   ⭐ **改共享安装** ⇒ 0807 换掉 5 类文件（4 类无备份）⇒ 一整天错误归因
#   ⭐ **只验尺寸/sha 就宣布装好** ⇒ 新 llc 在 kkk2 上根本加载不了（⭐ 需要 GLIBC_2.38，⭐ 宿主 2.35）
#     ⇒ ⭐⭐⭐ sha 只证同一性，⛔ **不证有效性** ⇒ ⭐ 判据顺序永远 `file` → `ldd` → `--version`
#   ⭐ **换漏位置 / 换到不存在的位置** ⇒ 我在两份任务书里写过"llc 有两个位置"，
#     ⭐ 实测原厂与 stageB **只有 `third_party/llvm/bin/llc`**，⭐ 而 driver 也只搜这一个
#     （`packages/driver/src/CJNATIVEBackend.cj:56-58` · `ToolChain.cj:482`）
#     ⇒ ⭐⭐ 本工具只替换**基线里已存在**的位置，⛔ 不凭猜测新建路径
#
# 用法:
#   sdk_build.sh --from <基线SDK名或路径> --to <目标目录> --host|--target [选项]
#
# 必选:
#   --from <x>      基线：⭐ cjv 工具链名 或 绝对路径
#   --to <dir>      目标目录（⛔ 不许在 /root/sdks 或 /root/.cjv 下）
#   --host          ⭐ 这是【宿主】SDK ⇒ ⭐⭐ 断言 runtime **未着色**（mask=0）
#   --target        ⭐ 这是【目标】SDK ⇒ ⭐⭐ 断言 runtime **着色**（mask=1）
#
# 可选（各自可省；⭐ 只替换给了的）:
#   --llc <file>    --opt <file>    --cjpm <file>    --cjc <file>
#   --llvm-so <libLLVM*.so*>  只覆盖 third_party/llvm/lib 同名 SO；llc/opt 保持基线
#   --llvm-tuple <dir>        按 SHA256SUMS strict 校验并整套安装静态 LLVM tuple
#   --runtime <dir> runtime 安装根（含 lib/<平台>+runtime/lib/<平台>），
#                   或仅 runtime/lib/<平台>（会在同轮 install 旁路找 lib/<平台> 静态库），
#                   或 flat sodepot（直接含 runtime + boundscheck 两枚 SO）
#                   40hex 根核提交章；64hex 根核 runtime sha256 及唯一 clean 章
#   --runtime-commit <40hex> 独立预期提交；flat 任意名称根必须显式提供，nested 给出时也核验
#   --std <dir>     build.py install prefix，或兼容旧调用的整个 modules/<平台> 目录
#   --verify-host-rt <dir|sdk>  target SDK 验证 managed 工具时使用的未着色宿主 runtime
#   --link <name>   ⭐ 组好后 `cjv toolchain link <name> <to>`
#   --force         ⭐ 目标已存在时先删（⛔ 默认拒绝覆盖）
set -u

RED() { printf '\033[31m%s\033[0m\n' "$*"; }
die() { RED "SDK-BUILD-FAIL $*"; exit 1; }

# ⭐⭐⭐ 子命令 `env` —— ⭐ 把「宿主/目标分开设」变成可执行的东西，⛔ 不再靠人记
#   ⭐ 自举期一枚 SDK **当不了两头**：⭐ 宿主要 runtime 未着色（⭐ 否则 cjc 自己崩）、
#     ⭐ 目标要 runtime 着色（⭐ 否则最终链接 `undefined reference to g_cjLoadBadMask`）
#   ⇒ ⭐⭐ 两枚 SDK 一起用：⭐ CANGJIE_HOME 指**目标**（⭐ -L / 链接输入 / std 从这儿来）
#      ⭐ LD_LIBRARY_PATH **首项**指**宿主**的 runtime（⭐ cjc 进程自己加载的是它）
#   用法: sdk_build.sh env --host-sdk <dir> --target-sdk <dir>
if [ "${1:-}" = env ]; then
  shift; HOSTSDK= TGTSDK=
  while [ $# -gt 0 ]; do
    case "$1" in
      --host-sdk) HOSTSDK="${2:?}"; shift 2;;
      --target-sdk) TGTSDK="${2:?}"; shift 2;;
      *) die "env: 未知参数 $1";;
    esac
  done
  [ -d "${HOSTSDK:-}" ] || die "env: 缺 --host-sdk"
  [ -d "${TGTSDK:-}" ]  || die "env: 缺 --target-sdk"
  hso=$(find "$HOSTSDK/runtime/lib" -name libcangjie-runtime.so | head -1)
  tso=$(find "$TGTSDK/runtime/lib"  -name libcangjie-runtime.so | head -1)
  [ -n "$hso" ] && [ -n "$tso" ] || die "env: 找不到 libcangjie-runtime.so"
  hm=$(nm -D "$hso" 2>/dev/null | grep -c g_cjLoadBadMask || true)
  tm=$(nm -D "$tso" 2>/dev/null | grep -c g_cjLoadBadMask || true)
  [ "$hm" = 0 ] || die "env: ⛔ 宿主 runtime 着色了（mask=$hm）⇒ ⭐ cjc 会 SEGV"
  [ "$tm" = 1 ] || die "env: ⛔ 目标 runtime 未着色（mask=$tm）⇒ ⭐ 最终链接会 undefined reference to g_cjLoadBadMask"
  # ⛔⛔⛔ 0808 实账：⭐⭐ **mask 对了照样崩** —— ⭐ mask 是必要条件，⛔ 不是充分条件
  #   ⭐ `ptrmask` 用 nightly-0619 的 runtime（mask=0）跑 stageB 那枚自举 cjc
  #     ⇒ ⭐ `There are no one managed frame / ThrowException fail`
  #   ⭐ 因为那枚 cjc 是对着 **g3dump-0728** 那一代 runtime 建的（⭐ 两份 sha 不同）
  #   ⇒ ⭐⭐⭐ 所以还要**实跑一次**：⭐ 环境装上之后 `cjc --version` 起不来就别往下走
  _env_ld="$(dirname "$hso"):$TGTSDK/third_party/llvm/lib:$TGTSDK/tools/lib"
  _env_path="$TGTSDK/bin:$TGTSDK/tools/bin:$TGTSDK/third_party/llvm/bin:/usr/bin:/bin"
  # ⚠⚠ ⭐⭐⭐ 用 `--version` 当烟测**不够** —— ⭐ 实测它在错配的环境下照样 ✓
  #   ⭐ 那条路径不走托管帧/异常机制，⛔ 而真正崩的是编译时的那一段
  #   ⇒ ⭐⭐ 所以真编一个最小程序，⭐ 那才踩到 `There are no one managed frame`
  _probe=$(mktemp -d)
  printf 'main(): Int64 { return 0 }\n' > "$_probe/p.cj"
  if ! CANGJIE_HOME="$TGTSDK" LD_LIBRARY_PATH="$_env_ld" PATH="$_env_path" \
       "$TGTSDK/bin/cjc" "$_probe/p.cj" -o "$_probe/p" >"$_probe/log" 2>&1; then
    RED "env: ⛔ 这套环境下 cjc **编不动最小程序**（⭐ mask 两边都对，⛔ 但宿主 runtime 与该 cjc 不配对）"
    head -5 "$_probe/log"
    rm -rf "$_probe"
    die "env: ⭐ 换一份宿主 runtime —— ⭐⭐ 要用【那枚 cjc 当初对着建的】那一份"
  fi
  rm -rf "$_probe"
  echo "# host mask=$hm ✓   target mask=$tm ✓   最小程序编译 ✓"
  echo "export CANGJIE_HOME=$TGTSDK"
  echo "export LD_LIBRARY_PATH=$(dirname "$hso"):$TGTSDK/third_party/llvm/lib:$TGTSDK/tools/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
  echo "export PATH=$TGTSDK/bin:$TGTSDK/tools/bin:\$PATH"
  echo "# ⚠ LD_LIBRARY_PATH 首项必须是宿主 runtime —— ⭐ 顺序就是判据"
  exit 0
fi

FROM= TO= ROLE= LLC= OPT= LLVM_SO= LLVM_TUPLE= CJPM= CJC= RUNTIME= RUNTIME_COMMIT= STD= VERIFY_HOST_RT= LINKNAME= FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM="${2:?}"; shift 2;;
    --to) TO="${2:?}"; shift 2;;
    --host) ROLE=host; shift;;
    --target) ROLE=target; shift;;
    --llc) LLC="${2:?}"; shift 2;;
    --opt) OPT="${2:?}"; shift 2;;
    --llvm-so) LLVM_SO="${2:?}"; shift 2;;
    --llvm-tuple) LLVM_TUPLE="${2:?}"; shift 2;;
    --cjpm) CJPM="${2:?}"; shift 2;;
    --cjc) CJC="${2:?}"; shift 2;;
    --runtime) RUNTIME="${2:?}"; shift 2;;
    --runtime-commit) RUNTIME_COMMIT="${2:?}"; shift 2;;
    --std) STD="${2:?}"; shift 2;;
    --verify-host-rt) VERIFY_HOST_RT="${2:?}"; shift 2;;
    --link) LINKNAME="${2:?}"; shift 2;;
    --force) FORCE=1; shift;;
    -h|--help) sed -n '1,40p' "$0"; exit 0;;
    *) die "未知参数 $1";;
  esac
done
[ -n "$FROM" ] || die "缺 --from"
[ -n "$TO" ]   || die "缺 --to"
[ -n "$ROLE" ] || die "缺 --host 或 --target —— ⭐ 这一条不许省：宿主/目标的着色要求相反"
if [ -n "$LLVM_SO" ] && [ -n "$LLVM_TUPLE" ]; then
  die '--llvm-so 与 --llvm-tuple 不可同时使用'
fi
if [ -n "$LLVM_TUPLE" ] && { [ -n "$LLC" ] || [ -n "$OPT" ]; }; then
  die '--llvm-tuple 已包含 llc/opt，不可再混用 --llc/--opt'
fi

if [ -n "$RUNTIME_COMMIT" ]; then
  [ -n "$RUNTIME" ] || die '--runtime-commit 必须与 --runtime 一起使用'
  [[ "$RUNTIME_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]] || die '--runtime-commit 必须是 40 位十六进制 clean commit'
  RUNTIME_COMMIT=${RUNTIME_COMMIT,,}
fi

VERIFY_HOST_RT_DIR=
if [ -n "$VERIFY_HOST_RT" ]; then
  [ "$ROLE" = target ] || die "--verify-host-rt 只用于 --target"
  if [ -f "$VERIFY_HOST_RT/libcangjie-runtime.so" ]; then
    VERIFY_HOST_RT_DIR=$(readlink -f "$VERIFY_HOST_RT")
  else
    VERIFY_HOST_RT_SO=$(find "$VERIFY_HOST_RT" -name libcangjie-runtime.so 2>/dev/null | head -1)
    [ -n "$VERIFY_HOST_RT_SO" ] || die "--verify-host-rt 找不到 libcangjie-runtime.so: $VERIFY_HOST_RT"
    VERIFY_HOST_RT_DIR=$(dirname "$(readlink -f "$VERIFY_HOST_RT_SO")")
  fi
  VERIFY_HOST_MASK=$(nm -D "$VERIFY_HOST_RT_DIR/libcangjie-runtime.so" 2>/dev/null | grep -c g_cjLoadBadMask || true)
  [ "$VERIFY_HOST_MASK" = 0 ] || die "--verify-host-rt 必须未着色（mask=$VERIFY_HOST_MASK）"
fi

CJV="${CJV:-/root/.local/bin/cjv}"

# ⭐ 基线：⭐ 名字 ⇒ 解析到 cjv 目录
case "$FROM" in
  /*) BASE="$FROM";;
  *)  BASE="/root/.cjv/toolchains/$FROM"
      [ -d "$BASE" ] || BASE="/root/sdks/$FROM";;
esac
[ -d "$BASE" ] || die "基线不存在: $FROM"
# ⭐⭐⭐ 0808 冒烟测出的真 bug：⭐ `cjv toolchain link` 装的条目是**符号链接**
#   ⭐ `/root/.cjv/toolchains/cjcj-pin-937877c8 -> /root/sdks/cjcj-pin-937877c8`
#   ⇒ ⭐ `cp -a` 复制的是**那条链接**，⭐ 于是"副本"仍指向共享安装
#   ⇒ ⭐⭐⭐ **后面每一次组件替换都会写进共享 SDK** —— ⭐ 正是本工具要防的事
#   ⚠ ⭐ 当时只是因为 `find` 默认不跟随符号链接、⭐ 没找到 llc 才没酿成事故 ⇒ ⭐ 那是运气
#   ⇒ ⭐ 所以：⭐⭐ **先解引用**，⭐ 之后所有判断都用实路径
BASE=$(readlink -f "$BASE") || die "无法解析基线路径"
[ -f "$BASE/bin/cjc" ] || die "$BASE 不像 SDK（缺 bin/cjc）"

# ⛔⛔ 目标不许落在共享安装里 —— ⭐ 这是本工具存在的第一理由
# ⭐ 目标可能还不存在 ⇒ ⭐ 用**父目录**的实路径来判（⛔ 别只判字符串）
TO_PARENT=$(readlink -f "$(dirname "$TO")" 2>/dev/null || true)
[ -n "$TO_PARENT" ] || die "目标父目录不存在: $(dirname "$TO")"
TO_REAL="$TO_PARENT/$(basename "$TO")"
case "$TO_REAL" in
  /root/sdks/*|/root/.cjv/*) die "⛔ 目标在共享安装内: $TO_REAL —— ⭐ 定制一律 cp -a 到别处 + cjv toolchain link";;
esac
[ "$TO_REAL" = "$BASE" ] && die "⛔ 目标就是基线本身: $BASE"
TO="$TO_REAL"

# ⭐ 基线自身干净吗？⛔ 拿被换过的 SDK 当基线是 0808 的实账
if [ -x /root/sdk_integrity.py ]; then
  _bad=$(/root/sdk_integrity.py check 2>/dev/null | grep -E "^SDK-INTEGRITY-(FOREIGN-RPATH|CHANGED|MISSING).*${BASE}" || true)
  [ -z "$_bad" ] || { RED "⚠ 基线可能被换过："; printf '%s\n' "$_bad"; die "先 cjv install --force 恢复再来"; }
fi

if [ -e "$TO" ]; then
  [ "$FORCE" = 1 ] || die "$TO 已存在（⭐ 加 --force 覆盖）"
  rm -rf "$TO"
fi

echo "[1/5] cp -a $BASE -> $TO"
# ⭐ 拷**内容**（`$BASE/.`），⛔ 不拷目录项本身 —— ⭐ 免得再把符号链接复制过来
mkdir -p "$TO" || die "mkdir 失败: $TO"
cp -a "$BASE/." "$TO/" || die "cp -a 失败"
# ⭐⭐ 复核：⭐ 副本必须是**真目录**，⛔ 不是链接；⭐ 且不能与基线同一个 inode
[ -L "$TO" ] && die "⛔ $TO 是符号链接 —— ⭐ 替换会写进它指向的地方"
[ "$(readlink -f "$TO")" = "$BASE" ] && die "⛔ 副本与基线是同一个目录"
[ -f "$TO/bin/cjc" ] || die "副本不完整（缺 bin/cjc）"

# ⭐ 只替换**基线里已存在**的位置；⛔ 不新建路径
swap_all() {                     # swap_all <相对文件名> <源文件> <标签>
  local rel="$1" src="$2" label="$3" n=0 dst
  [ -n "$src" ] || return 0
  [ -f "$src" ] || die "$label 源文件不存在: $src"
  while IFS= read -r dst; do
    [ -n "$dst" ] || continue
    cp -f "$src" "$dst" || die "写入失败: $dst"
    n=$((n+1))
    printf '      %s\n' "${dst#$TO/}"
  done < <(find "$TO" -maxdepth 4 -type f -name "$rel" 2>/dev/null)
  [ "$n" -gt 0 ] || die "$label: ⭐ 基线里没有名为 $rel 的位置 —— ⛔ 本工具不新建路径，⭐ 请确认组件名"
  echo "  [$label] 替换 $n 处  sha=$(sha256sum "$src" | cut -c1-16)"
}

same_sha() {
  local source="$1" target="$2" expected actual
  expected=$(sha256sum "$source" | awk '{print $1}') || return 1
  actual=$(sha256sum "$target" | awk '{print $1}') || return 1
  [ "$expected" = "$actual" ]
}

install_llvm_so() {
  local source="$1" base canonical target
  [ -f "$source" ] || die "llvm-so 源文件不存在: $source"
  base=$(basename "$source")
  case "$base" in libLLVM*.so*) ;; *) die "--llvm-so 文件名必须是 libLLVM*.so*: $source";; esac
  canonical="$TO/third_party/llvm/lib/$base"
  target="$canonical"
  [ -f "$canonical" ] || die "llvm-so: 基线里没有同名位置 $canonical"
  cp -f "$source" "$target" || die "llvm-so 写入失败: $target"
  same_sha "$source" "$canonical" || die 'llvm-so 安装后 sha256 不一致'
  echo "  [llvm-so] $source -> ${target#$TO/}  sha=$(sha256sum "$target" | cut -c1-16)"
}

tuple_sum_has() {
  local tuple="$1" rel="$2"
  awk -v rel="./$rel" '$2 == rel { found=1 } END { exit !found }' "$tuple/SHA256SUMS"
}

validate_llvm_tuple() {
  local tuple="$1" output rel entries
  [ -d "$tuple" ] || die "llvm-tuple 不是目录: $tuple"
  [ -f "$tuple/SHA256SUMS" ] || die "llvm-tuple 缺 SHA256SUMS: $tuple"
  # 清单只准 `<64hex><two spaces>./<relative>`；拒绝绝对路径和 `..` 逃逸。
  if ! awk '
    length($1) != 64 || $1 ~ /[^0-9a-fA-F]/ || $2 !~ /^\.\// || $2 ~ /(^|\/)\.\.($|\/)/ { bad=1 }
    END { exit bad || NR == 0 }
  ' "$tuple/SHA256SUMS"; then
    die 'llvm-tuple SHA256SUMS 格式或相对路径非法'
  fi
  entries=$(wc -l < "$tuple/SHA256SUMS")
  [ "$entries" -eq 8 ] || die "llvm-tuple SHA256SUMS 必须且只能登记 8 个 payload: entries=$entries"
  for rel in MANIFEST bin/llc bin/opt lib/STATIC_LLVM.txt \
    fixed-llc/cjselfhost_llvmshim.o fixed-llc/llc.gz \
    fixed-llc/opt.gz fixed-llc/llvm-tools.manifest; do
    [ -f "$tuple/$rel" ] || die "llvm-tuple 缺 $rel"
    tuple_sum_has "$tuple" "$rel" || die "llvm-tuple SHA256SUMS 未登记 $rel"
  done
  output=$(cd "$tuple" && sha256sum --strict -c SHA256SUMS 2>&1) || {
    printf '%s\n' "$output"
    die 'llvm-tuple SHA256SUMS strict 校验失败'
  }
  echo "  [llvm-tuple] SHA256SUMS strict ✓"
}

install_llvm_tuple() {
  local tuple="$1" line expected rel source target actual count=0
  validate_llvm_tuple "$tuple"
  [ -f "$TO/third_party/llvm/bin/llc" ] || die 'llvm-tuple: 基线里没有安装位置 third_party/llvm/bin/llc'
  [ -f "$TO/third_party/llvm/bin/opt" ] || die 'llvm-tuple: 基线里没有安装位置 third_party/llvm/bin/opt'
  rm -rf "$TO/third_party/llvm/fixed-llc"
  while IFS= read -r line; do
    expected=${line%% *}
    rel=${line#*  }
    rel=${rel#./}
    [ -n "$rel" ] || continue
    source="$tuple/$rel"
    target="$TO/third_party/llvm/$rel"
    mkdir -p "$(dirname "$target")" || die "llvm-tuple mkdir 失败: $(dirname "$target")"
    rm -f "$target"
    cp -a "$source" "$target" || die "llvm-tuple 写入失败: $target"
    count=$((count+1))
    echo "      $rel"
  done < "$tuple/SHA256SUMS"
  [ "$count" -gt 0 ] || die 'llvm-tuple 安装时没有清单输入'
  while IFS= read -r line; do
    expected=${line%% *}
    rel=${line#*  }
    rel=${rel#./}
    target="$TO/third_party/llvm/$rel"
    [ -f "$target" ] || die "llvm-tuple 安装位置缺失: $rel"
    actual=$(sha256sum "$target" | awk '{print $1}') || die "llvm-tuple 无法计算安装 sha256: $rel"
    [ "$expected" = "$actual" ] || die "llvm-tuple 安装后 sha256 不一致: $rel"
  done < "$tuple/SHA256SUMS"
  cp -f "$tuple/SHA256SUMS" "$TO/third_party/llvm/SHA256SUMS" || die 'llvm-tuple SHA256SUMS 安装失败'
  echo "  [llvm-tuple] installed every SHA256SUMS payload + SHA256SUMS"
}

echo "[2/5] 替换组件"
swap_all llc  "$LLC"  llc
swap_all opt  "$OPT"  opt
if [ -n "$LLVM_SO" ]; then
  install_llvm_so "$LLVM_SO"
fi
if [ -n "$LLVM_TUPLE" ]; then
  install_llvm_tuple "$LLVM_TUPLE"
fi
swap_all cjpm "$CJPM" cjpm
swap_all cjc  "$CJC"  cjc
# ⭐⭐⭐ 同轮元组：runtime 的 .so 装在 runtime/lib/<tuple>，.a 装在 lib/<tuple>
#   CMake 真值：runtime/CMakeLists.txt:518 (shared→runtime/lib) · :799 (static→lib)
#   Driver 真值：Linux_CJNATIVE.cj:104 静态链 -l:libcangjie-runtime.a（-L 先 lib/ 再 runtime/lib）
#   080811 实账：--runtime 只换 runtime/lib ⇒ lib/libcangjie-runtime.a 基线遗留（mask=0、无 CJRT 戳）
#   同理 std 的 .a/.so 分居 lib/ 与 runtime/lib/ —— install-prefix 路径必须两边一起换
# 同轮判据：静态 .a 与动态 .so 必须同代。
# 半套 SDK 旁路（…/runtime/lib/<t> 旁的 …/lib/<t> 基线遗留）会 mask/stamp 对不上。
runtime_pair_same_round() {
  local so="$1/libcangjie-runtime.so" a="$2/libcangjie-runtime.a"
  [ -f "$so" ] && [ -f "$a" ] || return 1
  local sm am ss as
  sm=$(nm -D "$so" 2>/dev/null | grep -c g_cjLoadBadMask || true)
  am=$(nm "$a" 2>/dev/null | grep -c g_cjLoadBadMask || true)
  # 着色方向必须一致：SO 有 mask ⇒ .a 也必须有；SO 无 mask ⇒ .a 也必须无
  if [ "${sm:-0}" -ge 1 ]; then
    [ "${am:-0}" -ge 1 ] || return 1
  else
    [ "${am:-0}" -eq 0 ] || return 1
  fi
  ss=$(strings "$so" 2>/dev/null | grep -o 'CJRT-COMMIT:[0-9a-f-]*' | head -1 || true)
  as=$(strings "$a" 2>/dev/null | grep -o 'CJRT-COMMIT:[0-9a-f-]*' | head -1 || true)
  # 两边都有戳 ⇒ 必须相等；一边有一边无 ⇒ 不同轮
  if [ -n "$ss" ] || [ -n "$as" ]; then
    [ -n "$ss" ] && [ -n "$as" ] && [ "$ss" = "$as" ] || return 1
  fi
  return 0
}

assert_runtime_stamp() {
  local so="$1" expected="$2" output stamps hits actual
  output=$(strings "$so" 2>/dev/null) || die "strings 无法读取 runtime: $so"
  stamps=$(printf '%s\n' "$output" | /usr/bin/grep -Eo 'CJRT-COMMIT:[[:alnum:]_-]*' | sort -u || true)
  hits=$(printf '%s\n' "$stamps" | awk 'NF {n++} END {print n+0}')
  actual=${stamps#CJRT-COMMIT:}
  actual=${actual,,}
  echo "ASSERT runtime-stamp expected=${expected:-unique-clean} actual=${actual:-none} hits=$hits file=$so"
  [ "$hits" -eq 1 ] || die "runtime CJRT-COMMIT 章计数不是 1: expected=$expected actual=${actual:-none} hits=$hits"
  [[ "$actual" =~ ^[0-9a-f]{40}$ ]] || die "runtime CJRT-COMMIT 不是 clean 40hex 章: actual=$actual"
  if [ -n "$expected" ]; then
    [ "$actual" = "$expected" ] || die "runtime CJRT-COMMIT 不匹配: expected=$expected actual=$actual"
  fi
  if [ -n "$RUNTIME_COMMIT" ]; then
    [ "$actual" = "$RUNTIME_COMMIT" ] || die "runtime 显式 CJRT-COMMIT 不匹配: expected=$RUNTIME_COMMIT actual=$actual"
  fi
}

assert_flat_runtime_identity() {
  local root="$1" name so expected= actual_hash
  name=$(basename "$root")
  name=${name,,}
  so="$root/libcangjie-runtime.so"
  if [[ "$name" =~ ^[0-9a-f]{40}$ ]]; then
    expected=$name
    echo "ASSERT runtime-identity source=commit-root expected=$expected explicit=${RUNTIME_COMMIT:-none} root=$root"
  elif [[ "$name" =~ ^[0-9a-f]{64}$ ]]; then
    actual_hash=$(sha256sum "$so") || die "runtime 无法读取 sha256: $so"
    actual_hash=${actual_hash%% *}
    echo "ASSERT runtime-identity source=sha256-root expected=$name actual=$actual_hash explicit=${RUNTIME_COMMIT:-none} root=$root"
    [ "$actual_hash" = "$name" ] || die "runtime sha256 不匹配: expected=$name actual=$actual_hash"
  else
    [ -n "$RUNTIME_COMMIT" ] || die "flat runtime 根身份不充分，需显式 --runtime-commit: root=$root"
    echo "ASSERT runtime-identity source=explicit-commit expected=$RUNTIME_COMMIT root=$root"
  fi
  assert_runtime_stamp "$so" "$expected"
}

runtime_stamp_summary() {
  local so="$1" output stamps
  output=$(strings "$so" 2>/dev/null) || {
    printf 'unreadable'
    return 0
  }
  stamps=$(printf '%s\n' "$output" | /usr/bin/grep -Eo 'CJRT-COMMIT:[0-9a-fA-F]{40}(-dirty)?' | sort -u || true)
  if [ -n "$stamps" ]; then
    printf '%s\n' "$stamps" | paste -sd, -
  else
    printf 'none'
  fi
}

resolve_runtime_pair() {
  # 输出到全局：RT_DYN_SRC（必有）· RT_STATIC_SRC（可空）· RT_TUPLE · RT_LAYOUT
  RT_DYN_SRC= RT_STATIC_SRC= RT_TUPLE= RT_LAYOUT=nested
  local root="$1" cand so flat_so nested_so nested_sos flat_stamp nested_summary
  # flat 与 nested 使用同一把尺：路径跟随符号链接后必须是常规文件。
  flat_so=$(find -L "$root" -mindepth 1 -maxdepth 1 -type f -name libcangjie-runtime.so -print -quit 2>/dev/null || true)
  nested_sos=$(find -L "$root" -mindepth 2 -type f -name libcangjie-runtime.so -print 2>/dev/null | sort || true)
  nested_so=
  nested_summary=
  while IFS= read -r so; do
    [ -n "$so" ] || continue
    [ -n "$nested_so" ] || nested_so="$so"
    nested_summary="$nested_summary nested=$so stamp=$(runtime_stamp_summary "$so")"
  done <<< "$nested_sos"
  if [ -n "$flat_so" ] && [ -n "$nested_so" ]; then
    flat_stamp=$(runtime_stamp_summary "$flat_so")
    die "runtime 布局歧义: flat=$flat_so stamp=$flat_stamp$nested_summary"
  fi
  if [ -n "$flat_so" ]; then
    [ -f "$root/libboundscheck.so" ] || die "flat runtime 缺 libboundscheck.so: $root"
    RT_DYN_SRC=$(readlink -f "$root")
    RT_LAYOUT=flat
    assert_flat_runtime_identity "$RT_DYN_SRC"
    return 0
  else
    so="$nested_so"
    [ -n "$so" ] || die "runtime 源找不到 libcangjie-runtime.so: $root"
    RT_DYN_SRC=$(dirname "$(readlink -f "$so")")
    if [ -n "$RUNTIME_COMMIT" ]; then
      assert_runtime_stamp "$RT_DYN_SRC/libcangjie-runtime.so" "$RUNTIME_COMMIT"
    fi
  fi
  RT_TUPLE=$(basename "$RT_DYN_SRC")
  # 候选按优先级试；每个都过 same-round 才收
  for cand in \
      "$(readlink -f "$RT_DYN_SRC/../../../lib/$RT_TUPLE" 2>/dev/null || true)" \
      "$( [ -d "$root/lib/$RT_TUPLE" ] && readlink -f "$root/lib/$RT_TUPLE" || true )" \
      "$(readlink -f "$RT_DYN_SRC/../../lib/$RT_TUPLE" 2>/dev/null || true)"; do
    [ -n "$cand" ] && [ -d "$cand" ] || continue
    if runtime_pair_same_round "$RT_DYN_SRC" "$cand"; then
      RT_STATIC_SRC="$cand"
      break
    fi
  done
}

if [ -n "$RUNTIME" ]; then
  [ -d "$RUNTIME" ] || die "runtime 源目录不存在: $RUNTIME"
  resolve_runtime_pair "$RUNTIME"
  d=$(find "$TO/runtime/lib" -maxdepth 1 -mindepth 1 -type d | head -1)
  [ -n "$d" ] || die "目标里找不到 runtime/lib/<平台>"
  # 平台名以目标为准；源侧 tuple 必须对得上（或仅一份）
  tgt_tuple=$(basename "$d")
  if [ "$RT_LAYOUT" = flat ]; then
    for base in libcangjie-runtime.so libboundscheck.so; do
      [ -f "$d/$base" ] || die "flat runtime: 基线里没有 runtime/lib/$tgt_tuple/$base，拒绝新建"
      cp -f "$RT_DYN_SRC/$base" "$d/$base" || die "flat runtime 动态库替换失败: $base"
      same_sha "$RT_DYN_SRC/$base" "$d/$base" || die "flat runtime 安装后 sha256 不一致: $base"
    done
    echo "  [runtime-dyn] flat ${RT_DYN_SRC} -> ${d#$TO/} files=2"
  else
    [ "$RT_TUPLE" = "$tgt_tuple" ] || \
      die "runtime 平台不一致: 源=$RT_TUPLE 目标=$tgt_tuple"
    rm -rf "$d" && cp -a "$RT_DYN_SRC" "$d" || die "runtime 动态库替换失败"
    echo "  [runtime-dyn] ${RT_DYN_SRC} -> ${d#$TO/}"
  fi
  # ⭐ 静态侧：基线若有 lib/<tuple> 里的 runtime 相关归档，必须同轮替换
  lib_d="$TO/lib/$tgt_tuple"
  if [ -d "$lib_d" ]; then
    if [ "$RT_LAYOUT" = flat ]; then
      echo "  [runtime-static] (skip: flat sodepot 只承载两枚 shared SO)"
    elif [ -z "$RT_STATIC_SRC" ]; then
      # 基线有静态 runtime 却找不到同轮源 ⇒ fail-closed（半套 = G2 身份污染）
      if [ -f "$lib_d/libcangjie-runtime.a" ]; then
        die "runtime: 基线有 lib/$tgt_tuple/libcangjie-runtime.a，但 --runtime 源旁找不到同轮静态库（给完整 install 根，或 runtime/lib 旁带 lib/<tuple>）"
      fi
      echo "  [runtime-static] (skip: 基线无 libcangjie-runtime.a)"
    else
      n=0
      while IFS= read -r src; do
        base=$(basename "$src")
        # 只替换 runtime 族：libcangjie-runtime* · libboundscheck* · 以及源侧与基线共有的非 std 文件
        case "$base" in
          libcangjie-std*) continue ;;  # std 走 --std，不混进 runtime 轮
        esac
        dst="$lib_d/$base"
        [ -f "$dst" ] || continue   # ⛔ 不新建基线没有的路径
        cp -f "$src" "$dst" || die "runtime 静态库写入失败: $dst"
        n=$((n+1))
        printf '      lib/%s/%s\n' "$tgt_tuple" "$base"
      done < <(find "$RT_STATIC_SRC" -maxdepth 1 -type f | sort)
      [ "$n" -gt 0 ] || die "runtime: 静态源 $RT_STATIC_SRC 与基线 lib/$tgt_tuple 无交集"
      # 硬断言：若基线有 .a，本轮必须换到
      if [ -f "$BASE/lib/$tgt_tuple/libcangjie-runtime.a" ]; then
        [ -f "$lib_d/libcangjie-runtime.a" ] || die "runtime: 替换后仍缺 lib/$tgt_tuple/libcangjie-runtime.a"
        # 同一性：与源同 sha（同轮自证）
        src_a="$RT_STATIC_SRC/libcangjie-runtime.a"
        [ -f "$src_a" ] || die "runtime: 静态源缺 libcangjie-runtime.a"
        s1=$(sha256sum "$src_a" | awk '{print $1}')
        s2=$(sha256sum "$lib_d/libcangjie-runtime.a" | awk '{print $1}')
        [ "$s1" = "$s2" ] || die "runtime: lib/.../libcangjie-runtime.a 与源 sha 不一致"
      fi
      echo "  [runtime-static] ${RT_STATIC_SRC} -> lib/$tgt_tuple  files=$n"
    fi
  fi
fi
if [ -n "$STD" ]; then
  [ -d "$STD" ] || die "std 源目录不存在: $STD"
  d=$(find "$TO/modules" -maxdepth 1 -mindepth 1 -type d -name 'linux*' | head -1)
  [ -n "$d" ] || die "目标里找不到 modules/<平台>"
  if [ -d "$STD/modules" ]; then
    smod=$(find "$STD/modules" -maxdepth 1 -mindepth 1 -type d -name 'linux*' | head -1)
    [ -n "$smod" ] || die "std install prefix 里找不到 modules/linux*"
    rm -rf "$d" && cp -a "$smod" "$d" || die "std modules 替换失败"
    echo "  [std-prefix] modules -> ${d#$TO/}"
    n=0
    # ⭐ 两边同轮：lib/<tuple> 的 .a + runtime/lib/<tuple> 的 .so（+ FFI）
    for relroot in lib/linux_x86_64_cjnative runtime/lib/linux_x86_64_cjnative; do
      [ -d "$STD/$relroot" ] || die "std install prefix 缺目录: $relroot"
      while IFS= read -r src; do
        base=$(basename "$src")
        # ⛔ std 安装根不得夹带 runtime 核心库（否则会盖掉 --runtime 同轮产物）
        case "$base" in
          libcangjie-runtime*|libboundscheck*) continue ;;
        esac
        rel="${src#$STD/}"
        dst="$TO/$rel"
        [ -f "$BASE/$rel" ] || die "std: 基线里没有 $rel，拒绝新建"
        cp -f "$src" "$dst" || die "std 写入失败: $rel"
        n=$((n+1))
      done < <(find "$STD/$relroot" -maxdepth 1 -type f | sort)
    done
    for rel in lib/libstdFFI.so; do
      [ -f "$STD/$rel" ] || die "std install prefix 缺文件: $rel"
      [ -f "$TO/$rel" ] || die "std: 基线里没有 $rel，拒绝新建"
      cp -f "$STD/$rel" "$TO/$rel" || die "std 写入失败: $rel"
      n=$((n+1))
    done
    # ⭐ 同轮自证：core 的 .a 与 .so 必须都来自本 prefix（sha 对源）
    for pair in \
      "lib/linux_x86_64_cjnative/libcangjie-std-core.a" \
      "runtime/lib/linux_x86_64_cjnative/libcangjie-std-core.so"; do
      [ -f "$STD/$pair" ] || die "std install prefix 缺 $pair"
      [ -f "$TO/$pair" ] || die "std: 替换后缺 $pair"
      s1=$(sha256sum "$STD/$pair" | awk '{print $1}')
      s2=$(sha256sum "$TO/$pair" | awk '{print $1}')
      [ "$s1" = "$s2" ] || die "std: $pair 与源 sha 不一致（半套装配）"
    done
    echo "  [std-prefix] replaced existing library files=$n (lib/ + runtime/lib/ same-round)"
  else
    # 旧调用：只给 modules/<平台> —— ⭐ 这会留下 lib/ 与 runtime/lib/ 的基线 std
    # 080811 实账：半套 std 让 --version 绿、最小编译崩。fail-closed。
    die "std: 拒绝 modules-only 源（$STD）—— 会留下 lib/<tuple> 基线 std。请传 build.py install --prefix 的完整根（含 modules/ + lib/ + runtime/lib/）"
  fi
fi

# ⭐⭐⭐ 着色断言 —— ⭐ 宿主与目标要求**相反**，⛔ 这一条最常被漏
echo "[3/5] 着色断言（role=$ROLE）"
RTSO=$(find "$TO/runtime/lib" -name libcangjie-runtime.so | head -1)
[ -n "$RTSO" ] || die "找不到 libcangjie-runtime.so"
MASK=$(nm -D "$RTSO" 2>/dev/null | grep -c g_cjLoadBadMask || true)
case "$ROLE" in
  host)   [ "$MASK" = 0 ] || die "⛔ 宿主 SDK 的 runtime **着色**了（mask=$MASK）⇒ ⭐ 宿主 cjc 会在 0.5 秒内 SEGV";;
  target) [ "$MASK" = 1 ] || die "⛔ 目标 SDK 的 runtime **未着色**（mask=$MASK）⇒ ⭐ 编出来的程序拿不到着色 ABI";;
esac
echo "  g_cjLoadBadMask=$MASK ✓  ($RTSO)"

# ⭐⭐ 有效性三步：⛔ sha 只证同一性
echo "[4/5] 自证 file -> ldd -> --version"
# ⭐⭐⭐ 必须**带 SDK 环境**验，⛔ 不能裸跑 —— ⭐ 0808 用户令点破的那件事：
#   ⭐ 官方 cjc 无 rpath、⭐ 也不该有 ⇒ ⭐⭐ 库是靠 envsetup.sh 的 LD_LIBRARY_PATH 找到的
#   ⇒ ⭐ 裸 `ldd` 对 cjpm/cjc 必然报 `libcangjie-runtime.so => not found`
#   ⇒ ⭐⭐ 那是**我没给环境**，⛔ 不是产物坏 —— ⭐ 按裸结果判会把好 SDK 判成废品
# ⭐⭐ 环境**直接 source SDK 自己的 envsetup.sh**，⛔ 别自己拼一份
#   ⭐ 理由（0808 用户令）：⭐⭐ **官方不设 rpath，⭐ 因为库靠 envsetup 找** ⇒ ⭐ envsetup 就是契约
#   ⇒ ⭐ 自己拼会漏 —— ⭐ 我第一版只设了 LD_LIBRARY_PATH，⭐ 漏了 PATH
#     ⇒ ⭐⭐ 于是 `cjpm --version` 内部调 `cjc -v` 找不到 cjc ⇒ ⭐⭐⭐ 把好 SDK 判成废品
#   ⇒ ⭐ source 它还有个好处：⭐⭐ envsetup 将来改了，⭐ 本工具自动跟上
[ -f "$TO/envsetup.sh" ] || die "副本缺 envsetup.sh —— ⭐ 那正是定位库的契约"
in_sdk_env() {                    # in_sdk_env <命令...>：⭐ 在 SDK 环境里跑
  ( set +u
    . "$TO/envsetup.sh" >/dev/null 2>&1
    if [ -n "$VERIFY_HOST_RT_DIR" ]; then
      export LD_LIBRARY_PATH="$VERIFY_HOST_RT_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    fi
    exec "$@"
  )
}
verify_exe() {                    # verify_exe <路径> <是否跑 --version>
  local f="$1" runver="$2"
  [ -f "$f" ] || return 0
  case "$(file -b "$f")" in *ELF*) ;; *) die "$f 不是 ELF";; esac
  local nf
  nf=$(in_sdk_env ldd "$f" 2>&1 | grep -c 'not found' || true)
  if [ "$nf" != 0 ]; then
    in_sdk_env ldd "$f" 2>&1 | grep 'not found'
    die "$f 在 SDK 环境下仍有 $nf 个未解析依赖"
  fi
  if [ "$runver" = 1 ]; then
    in_sdk_env "$f" --version >/dev/null 2>&1 \
      || die "$f --version 非零退出（已 source $TO/envsetup.sh）"
  fi
  printf '  %-34s ELF ✓  ldd ✓%s\n' "${f#$TO/}" "$([ "$runver" = 1 ] && printf '  --version ✓')"
}
for rel in third_party/llvm/bin/llc third_party/llvm/bin/opt tools/bin/cjpm; do
  verify_exe "$TO/$rel" 1
done
# ⚠ ⭐ cjc 只在【宿主】SDK 上跑 --version：⭐ 目标 SDK 的 runtime 着色，⭐ 跑它必崩
[ "$ROLE" = host ] && verify_exe "$TO/bin/cjc" 1 || verify_exe "$TO/bin/cjc" 0

echo "[5/5] 登记"
if [ -n "$LINKNAME" ]; then
  "$CJV" toolchain link "$LINKNAME" "$TO" || die "cjv toolchain link 失败"
  echo "  linked: $LINKNAME -> $TO"
else
  echo "  (未 --link；⭐ 需要时: $CJV toolchain link <名> $TO)"
fi

echo
for rel in bin/cjc third_party/llvm/bin/llc third_party/llvm/bin/opt tools/bin/cjpm; do
  [ -f "$TO/$rel" ] && printf 'SDK-BUILD-SHA %-34s %s\n' "$rel" "$(sha256sum "$TO/$rel" | awk '{print $1}')"
done
echo "SDK-BUILD-OK role=$ROLE from=$BASE to=$TO mask=$MASK"
