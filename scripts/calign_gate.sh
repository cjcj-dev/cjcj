#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="${1:-$ROOT/target/release/bin/cjcj::cjc}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

: "${CANGJIE_HOME:=/root/.cjv/toolchains/nightly-1.2.0-alpha.20260721165458}"
export CANGJIE_HOME
export LD_LIBRARY_PATH="$CANGJIE_HOME/third_party/llvm/lib:$CANGJIE_HOME/runtime/lib/linux_x86_64_cjnative:$CANGJIE_HOME/tools/lib:${LD_LIBRARY_PATH:-}"
export cjHeapSize="${cjHeapSize:-12GB}"

"$SELF" "$ROOT/test/calign_layout.cj" -o "$WORK/calign" --set-runtime-rpath
"$WORK/calign" | grep -qx 'calign layout ok'

for source in "$ROOT"/test/calign_invalid_*.cj; do
    name="$(basename "$source" .cj)"
    if "$SELF" "$source" -o "$WORK/$name" --set-runtime-rpath >"$WORK/$name.log" 2>&1; then
        echo "FAIL: $name unexpectedly compiled" >&2
        exit 1
    fi
    grep -q '@C' "$WORK/$name.log"
done

echo "calign: PASS layout=1 diagnostics=5"
