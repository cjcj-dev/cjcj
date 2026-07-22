#!/usr/bin/env bash
# Build libcangjie-runtime.so from the pinned CangjieFork runtime integration
# commit. The alpha integration line preserves the release SDK's runtime ABI and
# includes the three pinned GC concurrency fixes as normal commits.
#
# Usage: build_patched_runtime.sh <out-dir>
#   Writes the host-arch shared library plus source/SHA-256 provenance files.
# Env:
#   RUNTIME_REF       optional workflow assertion; must equal runtime_pin.env
#   RUNTIME_VERSION   CJ_SDK_VERSION stamped into the build
#   RUNTIME_SRC_URL   CangjieFork runtime repo
set -euo pipefail

OUT="${1:?usage: build_patched_runtime.sh <out-dir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REQUESTED_RUNTIME_REF="${RUNTIME_REF:-}"
# shellcheck source=runtime_pin.env
. "$HERE/runtime_pin.env"
[ -z "$REQUESTED_RUNTIME_REF" ] || [ "$REQUESTED_RUNTIME_REF" = "$RUNTIME_REF" ] || {
    echo "workflow/runtime pin mismatch: $REQUESTED_RUNTIME_REF != $RUNTIME_REF" >&2
    exit 2
}
VERSION="${RUNTIME_VERSION:-1.2.0-alpha.20260619020029}"
SRC_URL="${RUNTIME_SRC_URL:-https://github.com/CangjieFork/cangjie_runtime.git}"

log() { echo "[build_patched_runtime] $*"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "shallow fetch fork commit $RUNTIME_REF"
git -C "$WORK" init -q
git -C "$WORK" remote add origin "$SRC_URL"
git -C "$WORK" fetch --depth 1 origin "$RUNTIME_REF"
git -C "$WORK" checkout -q FETCH_HEAD
test "$(git -C "$WORK" rev-parse HEAD)" = "$RUNTIME_REF"

log "build (native, release)"
# build.py drives cmake with `-S .`, so it must run from the runtime source dir.
( cd "$WORK/runtime" && python3 build.py build --target native --build-type release -v "$VERSION" )

SO="$(find "$WORK/runtime/output" -path '*Release*' -name 'libcangjie-runtime.so' | head -1)"
[ -n "$SO" ] && [ -f "$SO" ] || { log "ERROR: built libcangjie-runtime.so not found"; exit 1; }

mkdir -p "$OUT"
cp "$SO" "$OUT/libcangjie-runtime.so"
printf '%s\n' "$RUNTIME_REF" > "$OUT/SOURCE_SHA"
(cd "$OUT" && sha256sum libcangjie-runtime.so > libcangjie-runtime.so.sha256)
log "wrote $OUT/libcangjie-runtime.so"
# RecomputeBitmapLiveBytes is introduced by the pinned trace-insertion-closure fix
# and retained as a versioned dynamic symbol in native release builds.  Unlike
# .cjmetadata (an application link-script output section), it identifies code that
# is actually present in libcangjie-runtime.so.
GC_FIX_SYMBOL='_ZNK12MapleRuntime8LiveInfo24RecomputeBitmapLiveBytesEv@@CANGJIE'
if ! readelf --dyn-syms --wide "$OUT/libcangjie-runtime.so" |
    grep -F "$GC_FIX_SYMBOL" >/dev/null; then
    log "ERROR: built runtime lacks the pinned GC fix symbol; wrong fork commit"
    exit 1
fi
log "verified: pinned GC fix symbol present"
