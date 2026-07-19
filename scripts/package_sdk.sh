#!/usr/bin/env bash
# Repackage the official Cangjie SDK tree as a cjcj release. The layout stays
# byte-identical to the official SDK except: bin/cjc is our Cangjie-built compiler
# (identity shows in `cjc -v`), and runtime/lib/<plat>/libcangjie-runtime.so is the
# patched runtime that scans a Cangjie-built cjc for GC stack roots (see
# runtime_patch/README.md). RUNPATH is rewritten $ORIGIN-relative so the package is
# relocatable. Output cjcj-<version>-<platform>.(tar.gz|zip) + .sha256.
# Rationale: reports/REPORT-relmatrix.md, reports/REPORT-ci-pipelines.md.
#
# Usage:
#   package_sdk.sh --sdk <sdk-dir> --binary <cjc-bin> --version <ver> \
#                  --platform <linux-x64|linux-aarch64|mac-aarch64|mac-x64|windows-x64> \
#                  --outdir <out-dir> [--runtime-so <patched-libcangjie-runtime.so>]
set -euo pipefail

SDK="" BIN="" VERSION="" PLATFORM="" OUTDIR="" RTSO=""
while [ $# -gt 0 ]; do
    case "$1" in
        --sdk)        SDK="$2"; shift 2 ;;
        --binary)     BIN="$2"; shift 2 ;;
        --version)    VERSION="$2"; shift 2 ;;
        --platform)   PLATFORM="$2"; shift 2 ;;
        --outdir)     OUTDIR="$2"; shift 2 ;;
        --runtime-so) RTSO="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
: "${SDK:?--sdk required}" "${BIN:?--binary required}" "${VERSION:?--version required}"
: "${PLATFORM:?--platform required}" "${OUTDIR:?--outdir required}"
[ -d "$SDK" ] || { echo "SDK dir not found: $SDK" >&2; exit 2; }
[ -f "$BIN" ] || { echo "cjc binary not found: $BIN" >&2; exit 2; }
[ -z "$RTSO" ] || [ -f "$RTSO" ] || { echo "runtime .so not found: $RTSO" >&2; exit 2; }

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

echo "[2/6] install our compiler as bin/cjc"
cp "$BIN" "$STAGE/bin/cjc${EXE}"
chmod 0755 "$STAGE/bin/cjc${EXE}"

echo "[3/6] swap in patched runtime"
if [ -n "$RTSO" ]; then
    DEST="$STAGE/runtime/lib/${RT_DIR}/libcangjie-runtime.so"
    [ -f "$DEST" ] || { echo "  ERROR: $DEST missing in SDK tree" >&2; exit 3; }
    cp "$RTSO" "$DEST"
    echo "  replaced $DEST"
else
    echo "  skip: no --runtime-so (stock runtime; only safe if cjc name exclusion is inapplicable)"
fi

echo "[4/6] set RUNPATH to \$ORIGIN-relative"
case "$PLATFORM" in
    linux-*)
        if ! command -v patchelf >/dev/null 2>&1; then
            echo "  ERROR: patchelf not found" >&2; exit 3
        fi
        patchelf --set-rpath "\$ORIGIN/../runtime/lib/${RT_DIR}:\$ORIGIN/../third_party/llvm/lib:\$ORIGIN/../tools/lib" "$STAGE/bin/cjc"
        echo -n "  RUNPATH: "; readelf -d "$STAGE/bin/cjc" 2>/dev/null | sed -n 's/.*RUNPATH.*\[\(.*\)\]/\1/p'
        ;;
    mac-*)
        echo "  skip: macOS needs install_name_tool (no mac build yet)" ;;
    windows-*)
        echo "  skip: Windows resolves DLLs by dir/PATH (no win build yet)" ;;
esac

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
