#!/usr/bin/env bash
# Repackage the official Cangjie SDK tree as a cjcj release: keep the whole tree,
# remove bin/cjc, add bin/cjcj, rewrite RUNPATH to $ORIGIN-relative, patch envsetup
# completion refs. Output cjcj-<version>-<platform>.(tar.gz|zip) + .sha256.
# Rationale: reports/REPORT-ci-pipelines.md.
#
# Usage:
#   package_sdk.sh --sdk <sdk-dir> --binary <cjcj-bin> --version <ver> \
#                  --platform <linux-x64|linux-aarch64|mac-aarch64|mac-x64|windows-x64> \
#                  --outdir <out-dir>
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

# platform -> (runtime lib dir, archive format, exe suffix)
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

echo "[1/6] copy SDK tree -> $STAGE"
cp -a "$SDK" "$STAGE"
chmod -R u+rwX,go+rX "$STAGE"   # normalize perms (SDK ships some files as -rwxr-x---)
rm -rf "$STAGE/.cjv"            # drop version-manager receipt

echo "[2/6] replace bin/cjc with bin/cjcj"
rm -f "$STAGE/bin/cjc${EXE}"
cp "$BIN" "$STAGE/bin/cjcj${EXE}"
chmod 0755 "$STAGE/bin/cjcj${EXE}"

echo "[3/6] set RUNPATH to \$ORIGIN-relative"
case "$PLATFORM" in
    linux-*)
        if ! command -v patchelf >/dev/null 2>&1; then
            echo "  ERROR: patchelf not found" >&2; exit 3
        fi
        patchelf --set-rpath "\$ORIGIN/../runtime/lib/${RT_DIR}:\$ORIGIN/../third_party/llvm/lib:\$ORIGIN/../tools/lib" "$STAGE/bin/cjcj"
        echo -n "  RUNPATH: "; readelf -d "$STAGE/bin/cjcj" 2>/dev/null | sed -n 's/.*RUNPATH.*\[\(.*\)\]/\1/p'
        ;;
    mac-*)
        echo "  skip: macOS needs install_name_tool (no mac build yet)" ;;
    windows-*)
        echo "  skip: Windows resolves DLLs by dir/PATH (no win build yet)" ;;
esac

echo "[4/6] patch envsetup completion refs cjc -> cjcj"
if [ -f "$STAGE/envsetup.sh" ]; then
    sed -i 's/\bcjc cjc-frontend\b/cjcj cjc-frontend/g' "$STAGE/envsetup.sh"
fi

echo "[5/6] archive"
ARCHIVE_PATH=""
if [ "$ARCHIVE" = "tar" ]; then
    ARCHIVE_PATH="$OUTDIR/${PKGNAME}.tar.gz"
    tar -C "$OUTDIR" -czf "$ARCHIVE_PATH" "$PKGNAME"
else
    ARCHIVE_PATH="$OUTDIR/${PKGNAME}.zip"
    ( cd "$OUTDIR" && zip -qr "${PKGNAME}.zip" "$PKGNAME" )
fi

echo "[6/6] sha256"
( cd "$OUTDIR" && sha256sum "$(basename "$ARCHIVE_PATH")" > "$(basename "$ARCHIVE_PATH").sha256" )

echo "DONE: $ARCHIVE_PATH"
echo "SHA256: $(cat "${ARCHIVE_PATH}.sha256")"
