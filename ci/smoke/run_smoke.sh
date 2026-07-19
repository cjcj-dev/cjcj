#!/usr/bin/env bash
# cjcj 冒烟测试驱动。用已部署的 cjcj 二进制编译并运行 ci/smoke 下的样本,逐个比对期望输出。
#
# 用法:  run_smoke.sh <cjcj-binary> [workdir]
#   <cjcj-binary>  必须是「已部署布局」下的二进制:其 ../runtime 存在(宏引擎在进程内按
#                  <bin>/../runtime/lib/<host> 解析运行时;缺失会导致宏静默跳过 → 见
#                  runtime_shim/build_shim.sh 顶部注释)。release 包里的 bin/cjcj 天然满足。
#   [workdir]      中间产物目录,默认 mktemp;结束后不自动删除(CI 里由 runner 回收)。
#
# 需要调用方已导出的环境:CANGJIE_HOME / LD_LIBRARY_PATH / cjHeapSize(见 ci/setup_sdk.sh)。
# 任一样本编译失败或输出不符即以非零退出,并打印 diff。
set -uo pipefail

CJCJ="${1:?usage: run_smoke.sh <cjcj-binary> [workdir]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${2:-$(mktemp -d)}"
mkdir -p "$WORK"

if [ ! -x "$CJCJ" ]; then
    echo "FATAL: cjcj binary not executable: $CJCJ" >&2
    exit 2
fi

pass=0
fail=0

# 单文件样本 → 期望首行(用 '|' 分隔多行期望)。
declare -A EXPECT=(
    ["01_hello"]="hello from cjcj"
    ["02_generics"]="42 hi 7"
    ["03_closures"]="30"
    ["04_iface_enum"]="12.560000 3"
    ["05_ffi"]="7"
)

run_one() {
    local name="$1" expect="$2"
    local src="$HERE/${name}.cj" exe="$WORK/${name}"
    echo "--- smoke: ${name} ---"
    if ! "$CJCJ" "$src" -o "$exe" >"$WORK/${name}.build.log" 2>&1; then
        echo "  COMPILE FAIL:"; sed 's/^/    /' "$WORK/${name}.build.log"; fail=$((fail+1)); return
    fi
    local got; got="$("$exe" 2>"$WORK/${name}.run.log")"
    if [ "$got" = "$expect" ]; then
        echo "  OK  -> [$got]"; pass=$((pass+1))
    else
        echo "  OUTPUT MISMATCH: expected [$expect] got [$got]"; fail=$((fail+1))
    fi
}

for name in 01_hello 02_generics 03_closures 04_iface_enum 05_ffi; do
    run_one "$name" "${EXPECT[$name]}"
done

# 宏样本:两步编译(--compile-macro 产出 .so/.cjo,再 --import-path 消费),验证进程内宏引擎。
echo "--- smoke: 06_macro ---"
MDIR="$HERE/macro_demo"
MBUILD="$WORK/macro_demo"; rm -rf "$MBUILD"; cp -r "$MDIR" "$MBUILD"
macro_ok=1
if ! ( cd "$MBUILD/mymacros" && "$CJCJ" --compile-macro def.cj ) >"$WORK/macro.build.log" 2>&1; then
    echo "  MACRO-PKG COMPILE FAIL:"; sed 's/^/    /' "$WORK/macro.build.log"; macro_ok=0
fi
if [ "$macro_ok" = 1 ]; then
    if ! ( cd "$MBUILD/app" && "$CJCJ" main.cj --import-path "$MBUILD/mymacros" -o "$MBUILD/app/app" ) >"$WORK/macro.app.log" 2>&1; then
        echo "  MACRO-APP COMPILE FAIL:"; sed 's/^/    /' "$WORK/macro.app.log"; macro_ok=0
    fi
fi
if [ "$macro_ok" = 1 ]; then
    got="$("$MBUILD/app/app" 2>"$WORK/macro.run.log")"
    want="$(printf 'tick\ntick')"
    if [ "$got" = "$want" ]; then echo "  OK  -> [${got//$'\n'/\\n}]"; pass=$((pass+1)); else
        echo "  OUTPUT MISMATCH: expected [tick\\ntick] got [${got//$'\n'/\\n}]"; fail=$((fail+1)); fi
else
    fail=$((fail+1))
fi

echo "==================================="
echo "smoke summary: pass=$pass fail=$fail (workdir=$WORK)"
[ "$fail" -eq 0 ]
