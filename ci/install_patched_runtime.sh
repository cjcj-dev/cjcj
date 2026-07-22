#!/usr/bin/env bash
# Verify and install a source-built runtime into this job's SDK tree. This is run
# after restoring/saving the pristine SDK cache, so a runtime pin never mutates a
# cache entry shared with another revision.
set -euo pipefail

DIST="${1:?usage: install_patched_runtime.sh <runtime-artifact-dir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REQUESTED_RUNTIME_REF="${RUNTIME_REF:-}"
# shellcheck source=runtime_pin.env
. "$HERE/runtime_pin.env"
[ -z "$REQUESTED_RUNTIME_REF" ] || [ "$REQUESTED_RUNTIME_REF" = "$RUNTIME_REF" ] || {
    echo "workflow/runtime pin mismatch: $REQUESTED_RUNTIME_REF != $RUNTIME_REF" >&2
    exit 2
}
: "${CANGJIE_HOME:?CANGJIE_HOME is required}"

SO="$DIST/libcangjie-runtime.so"
test -f "$SO"
test "$(cat "$DIST/SOURCE_SHA")" = "$RUNTIME_REF"
(cd "$DIST" && sha256sum -c libcangjie-runtime.so.sha256)

case "$(uname -s)/$(uname -m)" in
    Linux/x86_64)  RT_DIR=linux_x86_64_cjnative ;;
    Linux/aarch64) RT_DIR=linux_aarch64_cjnative ;;
    *) echo "patched runtime install unsupported on $(uname -s)/$(uname -m)" >&2; exit 2 ;;
esac

DEST="$CANGJIE_HOME/runtime/lib/$RT_DIR/libcangjie-runtime.so"
test -f "$DEST"
install -m0755 "$SO" "$DEST.new"
mv -f "$DEST.new" "$DEST"
test "$(sha256sum "$DEST" | awk '{print $1}')" = "$(sha256sum "$SO" | awk '{print $1}')"
echo "[install_patched_runtime] installed $RUNTIME_REF -> $DEST"
