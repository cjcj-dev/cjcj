#!/usr/bin/env bash
set -euo pipefail
out=$(mkdir -p "$1" && cd "$1" && pwd)
product=ci/release/darwin_runtime.mjs
# Each arm gets its own tree: darwin_runtime.mjs is the product under test and
# it reaches ./colour_runtime.mjs, ./darwin_std.mjs, ../colour-runtime/*.txt
# and ../bootstrap/std_runtime_colour.py relative to its own location, so the
# arm copy has to see the same repo layout it sees in the tree.
for arm in candidate producer-cut consumer-cut; do
  mkdir -p "$out/$arm/release" "$out/$arm/colour-runtime" "$out/$arm/bootstrap"
  cp ci/release/colour_runtime.mjs "$out/$arm/release/colour_runtime.mjs"
  cp ci/release/darwin_std.mjs "$out/$arm/release/darwin_std.mjs"
  cp ci/colour-runtime/darwin_required_exports.txt "$out/$arm/colour-runtime/darwin_required_exports.txt"
  cp ci/colour-runtime/release.json "$out/$arm/colour-runtime/release.json"
  cp ci/bootstrap/std_runtime_colour.py "$out/$arm/bootstrap/std_runtime_colour.py"
  cp "$product" "$out/$arm/release/darwin_runtime.mjs"
done
python3 - "$out" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
for name, old, new in [
    ('producer-cut', 'fs.copyFileSync(input, output);',
     'fs.copyFileSync(path.join(source, `runtime/lib/${tuple}/libboundscheck.dylib`), output);'),
    ('consumer-cut', 'assert.equal(digest(path.join(root, relative)), manifest.files[relative], `COLOUR_RT_FILE_SHA256_MISMATCH: ${relative}`);',
     'void manifest.files[relative];'),
]:
    p = root / name / 'release' / 'darwin_runtime.mjs'
    s = p.read_text()
    assert s.count(old) == 1
    p.write_text(s.replace(old, new))
PY
for arm in candidate producer-cut consumer-cut; do
  (set +e
   DARWIN_RT_PRODUCT="$out/$arm/release/darwin_runtime.mjs" node --test ci/release/darwin_runtime.test.mjs > "$out/$arm.log" 2>&1
   echo "$?" > "$out/$arm.rc") &
done
wait
cp -R "$out/candidate" "$out/restored"
set +e
DARWIN_RT_PRODUCT="$out/restored/release/darwin_runtime.mjs" node --test ci/release/darwin_runtime.test.mjs > "$out/restored.log" 2>&1
echo "$?" > "$out/restored.rc"
set -e
for arm in candidate producer-cut consumer-cut restored; do
  echo "ARM=$arm RC=$(cat "$out/$arm.rc")"
  grep -E '^(ℹ|#) (tests|pass|fail)|^not ok |^✖ |^ASSERT |^  [A-Za-z]*Error' "$out/$arm.log" || true
done
test "$(cat "$out/candidate.rc")" = 0
test "$(cat "$out/restored.rc")" = 0
test "$(cat "$out/producer-cut.rc")" != 0
test "$(cat "$out/consumer-cut.rc")" != 0
grep -q 'PRODUCER_BYTES:' "$out/producer-cut.log"
grep -q 'CONSUMER_REJECTS_CHANGED_BYTES' "$out/consumer-cut.log"
# Exactly one failure per cut, and it is the assertion that carries the cut.
# node prints TAP on the GHA runners and the spec reporter on a terminal, so
# read both: "# fail <n>" / "not ok <i> - <title>" and "ℹ fail <n>" / "✖ <title>".
fails() { awk '/^(#|ℹ) fail /{print $3; exit}' "$1"; }
for arm in candidate restored; do
  test "$(fails "$out/$arm.log")" = 0
done
test "$(fails "$out/producer-cut.log")" = 1
test "$(fails "$out/consumer-cut.log")" = 1
grep -qE '^(not ok [0-9]+ - |✖ )producer copies exactly the three native source libraries' "$out/producer-cut.log"
grep -qE '^(not ok [0-9]+ - |✖ )consumer rejects changed library bytes after authentic manifest verification' "$out/consumer-cut.log"
cmp "$out/candidate/release/darwin_runtime.mjs" "$out/restored/release/darwin_runtime.mjs"
find "$out" -name '*.mjs' -print0 | xargs -0 shasum -a 256 > "$out/scripts.sha256"
for arm in candidate producer-cut consumer-cut restored; do
  echo "ARM=$arm RC=$(cat "$out/$arm.rc")"
  grep -E '^(ℹ|#) (tests|pass|fail)|^not ok |^✖ |^ASSERT |^  [A-Za-z]*Error' "$out/$arm.log" || true
done
