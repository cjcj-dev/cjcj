#!/usr/bin/env bash
# Complete the unchanged runtime gate with the published language inputs.
set -euo pipefail
ulimit -c 0
source_root=$(realpath "${1:?runtime checkout}")
tuple=$(realpath "${2:?verified tuple}")
active=$(realpath -m "${3:?new private SDK directory}")
installed=$(realpath "${4:?runtime install root}")
repo=$(cd "$(dirname "$0")/../.." && pwd)
pin="$repo/ci/h48_language_tuple_pin.json"

# Select the build that produced the installed SO, then let its own resolver
# validate both published files. No other configuration may satisfy the gate.
installed_sha=$(sha256sum "$installed/runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so" | cut -d' ' -f1)
manifests=()
for manifest in "$source_root"/runtime/output/temp/*/runtime-build-config.txt; do
  [[ -f "$manifest" ]] || continue
  if [[ $(sed -n 's/^RUNTIME_SHA256=//p' "$manifest") == "$installed_sha" ]]; then
    manifests+=("$manifest")
  fi
done
if [[ ${#manifests[@]} != 1 ]]; then
  echo "COLOUR_RT_GATE_BUILD_IDENTITY count=${#manifests[@]}" >&2
  exit 2
fi
manifest=${manifests[0]}
export GCV2_RUNTIME_CONFIG
GCV2_RUNTIME_CONFIG=$(sed -n 's/^CONFIG_ID=//p' "$manifest")
target=$(bash "$source_root/runtime/build/resolve_runtime_output.sh" "$source_root/runtime" "$GCV2_RUNTIME_CONFIG")
python3 "$repo/ci/release/language_tuple.py" activate \
  --root "$tuple" --manifest-sha256 "$(jq -r .manifest_sha256 "$pin")" \
  --compiler-sha256 "$(jq -r .compiler_sha256 "$pin")" \
  --target "$target" --target-runtime-sha256 "$installed_sha" \
  --target-boundscheck-sha256 "$(sed -n 's/^BOUNDSCHECK_SHA256=//p' "$manifest")" \
  --output "$active" > "$active.env"
source "$active.env"
export GC_UNIT_GATE_LANGUAGE_TESTS=all
# This is the original complete gate, including its C++ cache qualification and
# language result assertions; deferred status alone never reaches packaging.
bash "$source_root/runtime/tests/gc_unit/gate_gc_unit.sh"
