#!/usr/bin/env bash
set -euo pipefail
out="$RUNNER_TEMP/signal-observation"
work="$CANGJIE_WORKSPACE/bootstrap-work"
srcdir="$work/cjcj-src-stage0"
sdk="$work/sdk-stage0"
mkdir -p "$out/keep/candidate"
resolve_product() {
  product=''
  for file in "$srcdir/target/release/bin/cjc@cjcj" "$srcdir/target/release/bin/cjcj::cjc"; do
    [ -f "$file" ] || continue
    [ -z "$product" ] || { echo 'product not unique' >&2; exit 1; }
    product="$file"
  done
  [ -n "$product" ] && [ -x "$product" ]
}
resolve_product
# Preserve the actual product/SDK entities, not just their historical hashes.
cp "$product" "$out/keep/candidate/cjc"
cp "$srcdir/packages/utils/src/Signal.cj" "$out/keep/candidate/Signal.cj"
cp -R "$sdk" "$out/keep/sdk-stage0"
cp -R "$CJCJ_BOOTSTRAP_HOST_RT" "$out/keep/host-runtime"
cp -R "$work/sdk-stage0-run" "$out/keep/sdk-stage0-run"
find "$out/keep" -type f -exec shasum -a 256 {} + > "$out/keep.sha256"
file "$out/keep/candidate/cjc" > "$out/product.file"
otool -L "$out/keep/candidate/cjc" > "$out/product.dependencies"
nm --defined-only "$out/keep/candidate/cjc" > "$out/product.symbols"
git -C "$GITHUB_WORKSPACE" rev-parse HEAD > "$out/candidate-source.sha"
# The preserved binary is itself the launch target; loader inputs are recorded
# at launch and actual loaded module hashes are checked by the observer.
set +e
python3 "$GITHUB_WORKSPACE/ci/bootstrap/signal_observation/run.py" product "$out/keep/candidate/cjc" 131072
rc=$?
set -e
echo "$rc" > "$out/candidate-observer.rc"
[ "$rc" -eq 0 ] || { echo 'STOP: candidate did not qualify for the old-size arm'; exit 0; }
# One old-size build, only after the candidate's actual successful installation.
python3 - "$srcdir/packages/utils/src/Signal.cj" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1]); s = p.read_text()
old = 'private let SIGNAL_STACK_SIZE: Int64 = 131072'
assert s.count(old) == 1
p.write_text(s.replace(old, 'private let SIGNAL_STACK_SIZE: Int64 = 8192'))
PY
sdkroot=$(xcrun --show-sdk-path)
ld="$CJCJ_BOOTSTRAP_HOST_RT/lib/$HOST_TUPLE:$sdk/runtime/lib/$HOST_TUPLE:$sdk/lib/$HOST_TUPLE:$sdk/third_party/llvm/lib"
rm "$product"
env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" CANGJIE_HOME="$sdk" SDKROOT="$sdkroot" \
  DYLD_LIBRARY_PATH="$ld" PATH="$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  cjHeapSize=5376MB bash -c "cd $(printf '%q' "$srcdir") && $(printf '%q' "$sdk/tools/bin/cjpm") build" \
  > "$out/old-build.log" 2>&1
resolve_product
mkdir -p "$out/keep/old8192"
cp "$product" "$out/keep/old8192/cjc"
cp "$srcdir/packages/utils/src/Signal.cj" "$out/keep/old8192/Signal.cj"
shasum -a 256 "$out/keep/old8192/"* > "$out/old8192.sha256"
set +e
python3 "$GITHUB_WORKSPACE/ci/bootstrap/signal_observation/run.py" product "$out/keep/old8192/cjc" 8192
rc=$?
set -e
echo "$rc" > "$out/old-observer.rc"
# No restoration build or extra product launch is authorized this round.
