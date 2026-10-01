#!/usr/bin/env bash
# Darwin alt-signal-stack evidence: three arms over the real stage0 product.
#
# Arm A (candidate): rebuild the stage0 product unchanged, run the real driver
#   entry. Arm B (cut): revert packages/utils/src/Signal.cj to the pre-fix
#   Darwin stack size and rebuild the same way. Arm C (restored): restore the
#   candidate source and rebuild the same way.
#
# The build is the same cjpm build entry bootstrap.sh:574 uses, on the same
# stage0 source copy and the same stage0 SDK, so only the constant differs
# between A, B and C. No product hook, no wrapper, no sigaltstack replacement.
set -euo pipefail

root=${GITHUB_WORKSPACE:?}
: "${CANGJIE_WORKSPACE:?CANGJIE_WORKSPACE is required}"
: "${CJCJ_BOOTSTRAP_HOST_RT:?CJCJ_BOOTSTRAP_HOST_RT is required}"
: "${HOST_TUPLE:?HOST_TUPLE is required}"

work="$CANGJIE_WORKSPACE/bootstrap-work"
srcdir="$work/cjcj-src-stage0"
sdk="$work/sdk-stage0"
runtime="$CJCJ_BOOTSTRAP_HOST_RT"
product="$srcdir/target/release/bin/cjcj-stage1"
signal_cj="$srcdir/packages/utils/src/Signal.cj"
signal_cj_candidate="$root/packages/utils/src/Signal.cj"
out="$RUNNER_TEMP/signal-stack-arms"
heap=5376MB
system_path="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

mkdir -p "$out"
[ -x "$product" ] || { echo "stage0 product missing: $product" >&2; exit 1; }
[ -f "$signal_cj" ] || { echo "stage0 source copy missing: $signal_cj" >&2; exit 1; }
[ -d "$sdk/tools/bin" ] || { echo "stage0 SDK missing: $sdk" >&2; exit 1; }

sdkroot=$(xcrun --show-sdk-path)
ld="$runtime/lib/$HOST_TUPLE:$sdk/runtime/lib/$HOST_TUPLE:$sdk/lib/$HOST_TUPLE:$sdk/third_party/llvm/lib"
build_path="$sdk/bin:$sdk/tools/bin:$sdk/third_party/llvm/bin:$system_path"

candidate_sha=$(shasum -a 256 "$signal_cj_candidate" | cut -d' ' -f1)
stage0_sha=$(shasum -a 256 "$product" | cut -d' ' -f1)
echo "EVIDENCE stage0_product_sha256=$stage0_sha"
echo "EVIDENCE candidate_signal_cj_sha256=$candidate_sha"
echo "EVIDENCE sdkroot=$sdkroot"
echo "EVIDENCE uname=$(uname -s)/$(uname -m) macos=$(sw_vers -productVersion)"

# rebuild <label>: same cjpm build entry as bootstrap.sh:574 on the stage0 copy.
rebuild() {
  local label="$1"
  rm -f "$product"
  env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" CANGJIE_HOME="$sdk" SDKROOT="$sdkroot" \
    DYLD_LIBRARY_PATH="$ld" PATH="$build_path" cjHeapSize="$heap" \
    bash -c "cd $(printf '%q' "$srcdir") && $(printf '%q' "$sdk/tools/bin/cjpm") build" \
    >"$out/$label.build.log" 2>&1
  [ -x "$product" ] || { echo "rebuild $label: product missing" >&2; tail -40 "$out/$label.build.log" >&2; exit 1; }
}

# run_product <label>: real driver entry, cjc --version through RunDriverMain.
run_product() {
  local label="$1" sha rc
  sha=$(shasum -a 256 "$product" | cut -d' ' -f1)
  set +e
  env -i HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" CANGJIE_HOME="$sdk" \
    DYLD_LIBRARY_PATH="$ld" PATH="$system_path" \
    "$product" --version >"$out/$label.run.log" 2>&1
  rc=$?
  set -e
  echo "$sha" >"$out/$label.product.sha256"
  echo "$rc" >"$out/$label.run.rc"
  echo "ARM $label product_sha256=$sha run_rc=$rc"
  cat "$out/$label.run.log"
}

stack_error_count() {
  /usr/bin/grep -c 'Failed to create a backup stack for the thread' "$1" || true
}

cut_source() {
  python3 - "$signal_cj" <<'PY'
import sys
path = sys.argv[1]
text = open(path, encoding='utf-8').read()
old = 'private let SIGNAL_STACK_SIZE: Int64 = 131072'
new = 'private let SIGNAL_STACK_SIZE: Int64 = 8192'
if text.count(old) != 1:
    raise SystemExit(f'CUT_TARGET_NOT_UNIQUE: {text.count(old)}')
open(path, 'w', encoding='utf-8').write(text.replace(old, new))
PY
}

restore_source() {
  cp "$signal_cj_candidate" "$signal_cj"
  local now
  now=$(shasum -a 256 "$signal_cj" | cut -d' ' -f1)
  [ "$now" = "$candidate_sha" ] || { echo "RESTORE_SHA_MISMATCH: $now != $candidate_sha" >&2; exit 1; }
}

# Arm A: candidate source, rebuilt with this arm's own environment.
rebuild arm_a
run_product arm_a
# Arm B: the one product line under test reverted to the pre-fix Darwin size.
cut_source
echo "CUT signal_cj_sha256=$(shasum -a 256 "$signal_cj" | cut -d' ' -f1) (candidate=$candidate_sha)"
rebuild arm_b
run_product arm_b
# Arm C: candidate source restored, rebuilt with the same environment as A.
restore_source
rebuild arm_c
run_product arm_c

sha_a=$(cat "$out/arm_a.product.sha256")
sha_b=$(cat "$out/arm_b.product.sha256")
sha_c=$(cat "$out/arm_c.product.sha256")
rc_a=$(cat "$out/arm_a.run.rc")
rc_b=$(cat "$out/arm_b.run.rc")
rc_c=$(cat "$out/arm_c.run.rc")
red_a=$(stack_error_count "$out/arm_a.run.log")
red_b=$(stack_error_count "$out/arm_b.run.log")
red_c=$(stack_error_count "$out/arm_c.run.log")

cat >"$out/arms.json" <<JSON
{
  "target": "$HOST_TUPLE",
  "runner": "$(uname -s)/$(uname -m) macos $(sw_vers -productVersion)",
  "sdkroot": "$sdkroot",
  "entry": "packages/driver/src/Main.cj RunDriverMain -> CreateAltSignalStack",
  "product_under_test": "$product",
  "stage0_product_sha256": "$stage0_sha",
  "candidate_signal_cj_sha256": "$candidate_sha",
  "arms": {
    "a_candidate":  {"product_sha256": "$sha_a", "run_rc": $rc_a, "stack_error_lines": $red_a},
    "b_cut":        {"product_sha256": "$sha_b", "run_rc": $rc_b, "stack_error_lines": $red_b},
    "c_restored":   {"product_sha256": "$sha_c", "run_rc": $rc_c, "stack_error_lines": $red_c}
  }
}
JSON
cat "$out/arms.json"

fail() { echo "EVIDENCE_FAILED: $1" >&2; exit 1; }
[ "$red_a" = 0 ] || fail "arm A reports the alt-stack installation error"
[ "$rc_a" = 0 ] || fail "arm A driver entry rc=$rc_a"
[ "$red_c" = 0 ] || fail "arm C reports the alt-stack installation error"
[ "$rc_c" = 0 ] || fail "arm C driver entry rc=$rc_c"
[ "$red_b" -ge 1 ] || fail "cut arm did not report the alt-stack installation error"
[ "$rc_b" != 0 ] || fail "cut arm driver entry rc=0, the cut is not causal"
[ "$sha_b" != "$sha_a" ] || fail "cut arm product is byte-identical to the candidate arm"
[ "$sha_c" = "$sha_a" ] || fail "restored arm product differs from the candidate arm: $sha_c != $sha_a"
echo "EVIDENCE_OK candidate=$sha_a cut=$sha_b restored=$sha_c"
