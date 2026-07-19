#!/usr/bin/env bash
# Build libcangjie-runtime.so from the official gitcode runtime source with the
# vendored runtime_patch/ series applied. The patch gates the process-name `cjc`
# GC stack-root exclusion on a Cangjie .cjmetadata section, so a Cangjie-built
# compiler shipped as bin/cjc is scanned correctly instead of GC-corrupted.
# Rationale + provenance: runtime_patch/README.md, reports/REPORT-relmatrix.md.
#
# Usage: build_patched_runtime.sh <out-dir>
#   Writes <out-dir>/libcangjie-runtime.so (host arch).
# Env:
#   RUNTIME_BASE_SHA  pinned official base commit (default below)
#   RUNTIME_VERSION   CJ_SDK_VERSION stamped into the build
#   RUNTIME_SRC_URL   gitcode runtime repo
set -euo pipefail

OUT="${1:?usage: build_patched_runtime.sh <out-dir>}"
BASE_SHA="${RUNTIME_BASE_SHA:-18cd0af893b06bfd0aedcef82aaa9eaf31cc40d2}"
VERSION="${RUNTIME_VERSION:-1.2.0-alpha.20260619020029}"
SRC_URL="${RUNTIME_SRC_URL:-https://gitcode.com/Cangjie/cangjie_runtime.git}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
PATCH_DIR="$REPO/runtime_patch"

log() { echo "[build_patched_runtime] $*"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "shallow fetch $BASE_SHA"
git -C "$WORK" init -q
git -C "$WORK" remote add origin "$SRC_URL"
git -C "$WORK" fetch --depth 1 origin "$BASE_SHA"
git -C "$WORK" checkout -q FETCH_HEAD

log "apply vendored runtime patches"
for p in "$PATCH_DIR"/0*.diff; do
    log "  $(basename "$p")"
    git -C "$WORK" apply "$p"
done

log "build (native, release)"
# build.py drives cmake with `-S .`, so it must run from the runtime source dir.
( cd "$WORK/runtime" && python3 build.py build --target native --build-type release -v "$VERSION" )

SO="$(find "$WORK/runtime/output" -path '*Release*' -name 'libcangjie-runtime.so' | head -1)"
[ -n "$SO" ] && [ -f "$SO" ] || { log "ERROR: built libcangjie-runtime.so not found"; exit 1; }

mkdir -p "$OUT"
cp "$SO" "$OUT/libcangjie-runtime.so"
log "wrote $OUT/libcangjie-runtime.so"
# Fail loudly if the .cjmetadata discriminator (the whole point of the patch) is absent.
# grep -a reads the object directly (no `strings | grep -q`, which trips pipefail via SIGPIPE).
if ! grep -qa '\.cjmetadata' "$OUT/libcangjie-runtime.so"; then
    log "ERROR: built runtime lacks the .cjmetadata discriminator; patch did not take"
    exit 1
fi
log "verified: .cjmetadata discriminator present"
