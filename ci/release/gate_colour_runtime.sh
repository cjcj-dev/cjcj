#!/usr/bin/env bash
# Complete the unchanged runtime gate with the published language inputs.
set -euo pipefail
ulimit -c 0
source_root=$(realpath "${1:?runtime checkout}")
tuple=$(realpath "${2:?verified tuple}")
active=$(realpath -m "${3:?new private SDK directory}")
installed=$(realpath "${4:?runtime install root}")
build_sdk=$(realpath "${5:?SDK selected for the runtime build}")
repo=$(cd "$(dirname "$0")/../.." && pwd)
pin="$repo/ci/qualified_language_tuple_pin.json"

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
# Qualification binds the SDK's original runtime and wrappers. The same-build
# pair under test remains a separate input; never install it over those bytes.
python3 - "$repo" "$tuple" "$pin" <<'PY'
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / 'ci/release'))
from qualified_language_tuple import verify
pin = json.loads(Path(sys.argv[3]).read_text())
verify(Path(sys.argv[2]), pin['manifest_sha256'], pin['compiler_sha256'])
PY
test ! -e "$active"
mkdir -p "$active"
cp -a "$tuple/sdk" "$active/sdk"
cp "$source_root/runtime/tests/gc_unit/language_toolchain_qualification.json" "$active/qualification.json"
cp "$repo/ci/bootstrap/std_runtime_colour.py" "$active/std_runtime_colour.py"
cp "$tuple/colour-host-runtime.so" "$active/colour-host-runtime.so"
export GC_UNIT_BUILD_SDK="$build_sdk"
export GC_UNIT_LANGUAGE_SDK="$active/sdk"
export GC_UNIT_CJC_RUNTIME_LIB_DIR="$active/sdk/host/compiler"
export GC_UNIT_LANGUAGE_QUALIFICATION="$active/qualification.json"
export GC_UNIT_COLOUR_CHECKER="$active/std_runtime_colour.py"
export GC_UNIT_COLOUR_HOST_RUNTIME="$active/colour-host-runtime.so"
export GCV2_RUNTIME_LIB_DIR="$target"
export CJC="$active/sdk/bin/cjc"
export CANGJIE_HOME="$active/sdk"
# Preserve the existing downstream handoff without replacing qualified bytes.
python3 - "$active.env" <<'PY'
import os, shlex, sys
from pathlib import Path
names = ('CJC', 'CANGJIE_HOME', 'GCV2_RUNTIME_LIB_DIR', 'GC_UNIT_CJC_RUNTIME_LIB_DIR')
Path(sys.argv[1]).write_text(''.join(f'export {name}={shlex.quote(os.environ[name])}\n' for name in names))
PY
export GC_UNIT_GATE_LANGUAGE_TESTS=all
# This is the original complete gate, including its C++ cache qualification and
# language result assertions; deferred status alone never reaches packaging.
bash "$source_root/runtime/tests/gc_unit/gate_gc_unit.sh"
