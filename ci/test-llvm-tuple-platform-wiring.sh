#!/usr/bin/env bash
# Causal checks for the platform publication/selection scripts, not LLVM behavior.
set -euo pipefail
ulimit -c 0
root=$(cd "$(dirname "$0")/.." && pwd)
work=${1:?usage: test-llvm-tuple-platform-wiring.sh NEW_WORK_DIRECTORY}
mkdir "$work"
work=$(cd "$work" && pwd)
cd "$work"
export TMPDIR=$work/tmp
mkdir tmp logs
uptime > logs/uptime-before.txt
arms=(green restored producer-cut pin-cut manifest-cut publisher-cut fixed-sums-cut darwin-boundary-cut)
for arm in "${arms[@]}"; do
  mkdir -p "$arm/build" "$arm/.github"
  cp -a "$root/ci" "$arm/ci"
  cp -a "$root/build/lib" "$arm/build/lib"
  cp -a "$root/.github/workflows" "$arm/.github/workflows"
  # Preserve the real source commit used by the publisher's recipe field,
  # without copying repository credentials or depending on the parent checkout.
  git -C "$arm" init -q
  sha=$(git -C "$root" cat-file commit HEAD | git -C "$arm" hash-object -t commit -w --stdin)
  git -C "$arm" update-ref refs/heads/snapshot "$sha"
  git -C "$arm" symbolic-ref HEAD refs/heads/snapshot
  printf '%s\n' "$sha" > "logs/$arm.source-commit"
done
python3 - <<'PY'
from pathlib import Path
import difflib
cuts = {
 'darwin-boundary-cut': ('ci/release/prepare_bootstrap_inputs.mjs', 'if (!darwin) {', 'if (true) { // cut: impose Linux static tuple on Darwin'),
 'fixed-sums-cut': ('ci/release/acquire_fixed_tuple.mjs', "  verify(fs.readFileSync(path.join(tuple, 'SHA256SUMS')), sumsSha, 'LLVM_TUPLE_SUMS_SHA');", "  // cut: omit independent reviewed sums verification"),
 'producer-cut': ('ci/llvm-tuple-layout.sh', "printf 'PLATFORM=%s\\n' \"$platform\"", "printf 'PLATFORM=%s\\n' linux_x86_64"),
 'pin-cut': ('ci/release/tuple_platform.mjs', "if (pin.platform !== platform) platformFailure('BOOTSTRAP_TUPLE_PLATFORM_MISMATCH', platform, pin.platform);", "// cut: omit selected pin platform validation"),
 'manifest-cut': ('ci/release/tuple_platform.mjs', "    platformFailure('BOOTSTRAP_TUPLE_PLATFORM_MISMATCH', platform, platforms.join(','));", "  // cut: omit verified MANIFEST platform validation"),
 'publisher-cut': ('ci/release/publish_bootstrap_inputs.mjs', "|| platforms.length !== 1 || platforms[0] !== platform", "|| platforms.length !== 1"),
}
for arm, (file, old, new) in cuts.items():
 p=Path(arm)/file
 s=p.read_text()
 assert s.count(old)==1, (arm, old)
 p.write_text(s.replace(old,new))
 Path('logs', arm+'.diff').write_text(''.join(difflib.unified_diff(s.splitlines(True),p.read_text().splitlines(True),fromfile='a/'+file,tofile='b/'+file)))
PY
files=(ci/llvm-tuple-platform.test.mjs ci/release/prepare_bootstrap_inputs.test.mjs ci/release/publish_bootstrap_inputs.test.mjs ci/release/bootstrap_store.test.mjs ci/release/acquire_fixed_tuple.test.mjs ci/release/prepare_llvm_dylib.test.mjs ci/release-pair-pin.test.mjs)
for arm in "${arms[@]}"; do
  (
    cd "$arm"
    sha256sum ci/release/tuple_platform.mjs ci/release/acquire_fixed_tuple.mjs ci/llvm-tuple-layout.sh ci/release/prepare_bootstrap_inputs.mjs ci/release/publish_bootstrap_inputs.mjs ci/release/prepare_bootstrap_fixture.mjs > "../logs/$arm.sha256"
    sha256sum "${files[@]}" > "../logs/$arm.tests.sha256"
    set +e
    /usr/bin/time -f wall=%e node --test "${files[@]}" > "../logs/$arm.log" 2>&1
    echo $? > "../logs/$arm.rc"
  ) &
done
wait
uptime > logs/uptime-after.txt
for arm in "${arms[@]}"; do
  printf 'PLATFORM_WIRING arm=%s rc=%s\n' "$arm" "$(cat "logs/$arm.rc")"
  grep -E '^(not ok|# tests|# pass|# fail|wall=)' "logs/$arm.log"
  cmp logs/green.tests.sha256 "logs/$arm.tests.sha256"
done
for arm in green restored; do test "$(cat "logs/$arm.rc")" = 0; done
cmp logs/green.sha256 logs/restored.sha256
cuts=(producer-cut pin-cut manifest-cut publisher-cut fixed-sums-cut darwin-boundary-cut)
targets=('tuple producer preserves linux_aarch64 from tools manifest'
  'platform tuple rejects wrong-platform pin with rc 65 before acquisition'
  'platform tuple rejects digest-valid wrong-platform manifest with rc 65'
  'publisher refuses wrong platform before creating a prerelease'
  'fixed release CLI preserves independent sums pin and existing destination on rejection'
  'darwin-arm64 exports the reviewed native dylib and rejects changed bytes')
for i in "${!cuts[@]}"; do
  arm=${cuts[$i]}
  test "$(cat "logs/$arm.rc")" = 1
  expected=1
  if [[ $arm == pin-cut || $arm == manifest-cut || $arm == darwin-boundary-cut ]]; then expected=2; fi
  grep -Fx "# fail $expected" "logs/$arm.log"
  grep -E '^not ok ' "logs/$arm.log" | grep -F -- "${targets[$i]}"
  if [[ $arm == darwin-boundary-cut ]]; then
    grep -E '^not ok ' "logs/$arm.log" | grep -F 'darwin-x64 exports the reviewed native dylib and rejects changed bytes'
  elif [[ $arm == pin-cut ]]; then
    grep -E '^not ok ' "logs/$arm.log" | grep -F 'fixed release CLI rejects wrong-platform pin before download'
  elif [[ $arm == manifest-cut ]]; then
    grep -E '^not ok ' "logs/$arm.log" | grep -F 'fixed release CLI rejects digest-valid foreign MANIFEST before publication'
  fi
  if cmp -s logs/green.sha256 "logs/$arm.sha256"; then
    echo "cut did not change product identity: $arm" >&2
    exit 1
  fi
done
# Logs, hashes and patches retain each fault; the snapshots are reconstructible.
rm -rf "${arms[@]}" tmp
