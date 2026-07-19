#!/usr/bin/env bash
# 把「官方仓颉 SDK 目录树」重打包成 cjcj 发行包:整棵树原样保留,仅
#   - 删除 bin/cjc(官方引导编译器)
#   - 放入 bin/cjcj(本仓自举产出的二进制)
#   - 修正二进制的 RUNPATH 为 $ORIGIN 相对(使发行包自洽、可在任意机器解压即用)
#   - envsetup.sh 里对 cjc 的补全引用改成 cjcj
# 产出 cjcj-<version>-<platform>.(tar.gz|zip) + 同名 .sha256。
#
# 用法:
#   package_sdk.sh --sdk <sdk-dir> --binary <cjcj-bin> --version <ver> \
#                  --platform <linux-x64|linux-aarch64|mac-aarch64|mac-x64|windows-x64> \
#                  --outdir <out-dir>
#
# 设计依据(见 reports/REPORT-ci-pipelines.md):
#   官方 cjc 静态链 LLVM、自洽;本仓 cjcj 动态链 libLLVM-15.so 且带一条指向构建机
#   /root/.cjv/.../0619/.../lib 的绝对 RUNPATH——原样发布会在用户机上找不到 libLLVM。
#   故打包时用 patchelf 把 RUNPATH 改为 $ORIGIN 相对(libLLVM 就在包内
#   third_party/llvm/lib,runtime 库在 runtime/lib/<host>)。
set -euo pipefail

SDK="" BIN="" VERSION="" PLATFORM="" OUTDIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --sdk)      SDK="$2"; shift 2 ;;
        --binary)   BIN="$2"; shift 2 ;;
        --version)  VERSION="$2"; shift 2 ;;
        --platform) PLATFORM="$2"; shift 2 ;;
        --outdir)   OUTDIR="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
: "${SDK:?--sdk required}" "${BIN:?--binary required}" "${VERSION:?--version required}"
: "${PLATFORM:?--platform required}" "${OUTDIR:?--outdir required}"
[ -d "$SDK" ] || { echo "SDK dir not found: $SDK" >&2; exit 2; }
[ -f "$BIN" ] || { echo "cjcj binary not found: $BIN" >&2; exit 2; }

# 平台 → (运行时 host 库目录, 归档格式, 二进制后缀)
case "$PLATFORM" in
    linux-x64)      RT_DIR="linux_x86_64_cjnative";  ARCHIVE="tar";  EXE="" ;;
    linux-aarch64)  RT_DIR="linux_aarch64_cjnative"; ARCHIVE="tar";  EXE="" ;;
    mac-aarch64)    RT_DIR="darwin_aarch64_cjnative";ARCHIVE="tar";  EXE="" ;;
    mac-x64)        RT_DIR="darwin_x86_64_cjnative"; ARCHIVE="tar";  EXE="" ;;
    windows-x64)    RT_DIR="windows_x86_64_cjnative";ARCHIVE="zip";  EXE=".exe" ;;
    *) echo "unsupported --platform: $PLATFORM" >&2; exit 2 ;;
esac

PKGNAME="cjcj-${VERSION}-${PLATFORM}"
STAGE="$OUTDIR/$PKGNAME"
mkdir -p "$OUTDIR"
rm -rf "$STAGE"

echo "[1/6] 复制官方 SDK 目录树 → $STAGE"
cp -a "$SDK" "$STAGE"
# 归一化权限(官方包里 LICENSE 等是 -rwxr-x---,发行前放开只读+可执行)
chmod -R u+rwX,go+rX "$STAGE"
rm -rf "$STAGE/.cjv"   # 去掉版本管理器私有收据

echo "[2/6] 移除 bin/cjc,放入 bin/cjcj"
rm -f "$STAGE/bin/cjc${EXE}"
cp "$BIN" "$STAGE/bin/cjcj${EXE}"
chmod 0755 "$STAGE/bin/cjcj${EXE}"

echo "[3/6] 修正 RUNPATH 为 \$ORIGIN 相对(仅 Linux 用 patchelf)"
case "$PLATFORM" in
    linux-*)
        if ! command -v patchelf >/dev/null 2>&1; then
            echo "  ERROR: patchelf 不可用,无法生成可移植发行包" >&2; exit 3
        fi
        patchelf --set-rpath "\$ORIGIN/../runtime/lib/${RT_DIR}:\$ORIGIN/../third_party/llvm/lib:\$ORIGIN/../tools/lib" "$STAGE/bin/cjcj"
        echo -n "  new RUNPATH: "; readelf -d "$STAGE/bin/cjcj" 2>/dev/null | sed -n 's/.*RUNPATH.*\[\(.*\)\]/\1/p'
        ;;
    mac-*)
        echo "  NOTE: macOS 需用 install_name_tool 处理 @loader_path(当前无 mac 构建,占位)" ;;
    windows-*)
        echo "  NOTE: Windows 靠可执行同目录/PATH 解析 DLL,无 RUNPATH(当前无 win 构建,占位)" ;;
esac

echo "[4/6] 调整 envsetup.sh 对 cjc 的补全引用 → cjcj"
if [ -f "$STAGE/envsetup.sh" ]; then
    # 只改 shell 补全里 'cjc cjc-frontend' 的 cjc(cjc-frontend 保留),不动其它逻辑。
    sed -i 's/\bcjc cjc-frontend\b/cjcj cjc-frontend/g' "$STAGE/envsetup.sh"
fi

echo "[5/6] 打包归档"
ARCHIVE_PATH=""
if [ "$ARCHIVE" = "tar" ]; then
    ARCHIVE_PATH="$OUTDIR/${PKGNAME}.tar.gz"
    tar -C "$OUTDIR" -czf "$ARCHIVE_PATH" "$PKGNAME"
else
    ARCHIVE_PATH="$OUTDIR/${PKGNAME}.zip"
    ( cd "$OUTDIR" && zip -qr "${PKGNAME}.zip" "$PKGNAME" )
fi

echo "[6/6] 计算 sha256"
( cd "$OUTDIR" && sha256sum "$(basename "$ARCHIVE_PATH")" > "$(basename "$ARCHIVE_PATH").sha256" )

echo "DONE: $ARCHIVE_PATH"
echo "SHA256: $(cat "${ARCHIVE_PATH}.sha256")"
