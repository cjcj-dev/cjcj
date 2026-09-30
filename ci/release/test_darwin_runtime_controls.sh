#!/usr/bin/env bash
set -euo pipefail
out=$(mkdir -p "$1" && cd "$1" && pwd)
product=ci/release/darwin_runtime.mjs
cp "$product" "$out/candidate.mjs"
cp ci/release/colour_runtime.mjs "$out/colour_runtime.mjs"
cp "$product" "$out/producer-cut.mjs"
cp "$product" "$out/consumer-cut.mjs"
python3 - "$out" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
for name, old, new in [
    ('producer-cut', 'fs.copyFileSync(input, output);',
     'fs.copyFileSync(path.join(source, `runtime/lib/${tuple}/libboundscheck.${extension}`), output);'),
    ('consumer-cut', 'assert.equal(digest(path.join(root, relative)), manifest.files[relative], `COLOUR_RT_FILE_SHA256_MISMATCH: ${relative}`);',
     'void manifest.files[relative];'),
]:
    p = root / (name + '.mjs')
    s = p.read_text()
    assert s.count(old) == 1
    p.write_text(s.replace(old, new))
PY
for arm in candidate producer-cut consumer-cut; do
  (set +e
   DARWIN_RT_PRODUCT="$out/$arm.mjs" node --test ci/release/darwin_runtime.test.mjs > "$out/$arm.log" 2>&1
   echo "$?" > "$out/$arm.rc") &
done
wait
cp "$out/candidate.mjs" "$out/restored.mjs"
DARWIN_RT_PRODUCT="$out/restored.mjs" node --test ci/release/darwin_runtime.test.mjs > "$out/restored.log" 2>&1
echo 0 > "$out/restored.rc"
test "$(cat "$out/candidate.rc")" = 0
test "$(cat "$out/producer-cut.rc")" != 0
test "$(cat "$out/consumer-cut.rc")" != 0
grep -q 'PRODUCER_BYTES:' "$out/producer-cut.log"
grep -q 'CONSUMER_REJECTS_CHANGED_BYTES' "$out/consumer-cut.log"
for arm in producer-cut consumer-cut; do
  test "$(grep -c '^not ok ' "$out/$arm.log")" = 1
done
cmp "$out/candidate.mjs" "$out/restored.mjs"
shasum -a 256 "$out"/*.mjs > "$out/scripts.sha256"
for arm in candidate producer-cut consumer-cut restored; do
  echo "ARM=$arm RC=$(cat "$out/$arm.rc")"
  grep -E '^# (tests|pass|fail)|^not ok |^# ASSERT' "$out/$arm.log"
done
