#!/usr/bin/env bash
# Recipe contract plus the dynamic-section check. Fixture text is not a linker.
set -euo pipefail
export LC_ALL=C

root=$(cd "$(dirname "$0")/.." && pwd)
work=${1:?usage: test-colour-libxml2.sh EMPTY_WORK_DIRECTORY [BAD_LD_LLD] [GOOD_LD_LLD]}
bad=${2:-}
good=${3:-}
mkdir "$work"
cd "$root"

yml=.github/workflows/build-llvm-tools.yml
src=tools/srcbuild_kkk2.sh
checker=ci/assert_no_libxml2_needed.sh
token='-DLLVM_ENABLE_LIBXML2=OFF'

cp "$yml" "$work/yml.saved"
cp "$src" "$work/src.saved"
cp "$checker" "$work/checker.saved"
restore() {
    cp "$work/yml.saved" "$yml"
    cp "$work/src.saved" "$src"
    cp "$work/checker.saved" "$checker"
}
trap restore EXIT

recipe_ok() {
    python3 - "$token" "$yml" "$src" ci/platform_tuples/build_tuple.sh <<'PY'
import sys
from pathlib import Path
token, yml, src, anchor = sys.argv[1:]
anchor_text = Path(anchor).read_text()
if token not in anchor_text:
    raise SystemExit("MISSING_LIBXML2_OFF anchor")
for path in (yml, src):
    text = Path(path).read_text()
    if token not in text:
        raise SystemExit(f"MISSING_LIBXML2_OFF {path}")
    if "assert_no_libxml2_needed.sh" not in text:
        raise SystemExit(f"MISSING_NEEDED_CHECK {path}")
print("RECIPE_LIBXML2_OFF_PRESENT")
PY
}

recipe_ok > "$work/recipe-green.log"
sha256sum "$yml" "$src" "$checker" > "$work/green.sha256"

drop_token() {
    python3 - "$1" "$token" <<'PY'
import sys
from pathlib import Path
path, token = sys.argv[1:]
file = Path(path)
lines = file.read_text().splitlines(keepends=True)
kept = [line for line in lines if token not in line]
if len(kept) == len(lines):
    raise SystemExit(f"token not found in {path}")
file.write_text(''.join(kept))
PY
}

drop_token "$yml"
diff -u "$work/yml.saved" "$yml" > "$work/yml-cut.diff" || test "$?" -eq 1
set +e
recipe_ok > "$work/recipe-yml-cut.log" 2>&1
yml_cut_rc=$?
set -e
test "$yml_cut_rc" -ne 0
grep -F "MISSING_LIBXML2_OFF $yml" "$work/recipe-yml-cut.log"
restore

drop_token "$src"
diff -u "$work/src.saved" "$src" > "$work/src-cut.diff" || test "$?" -eq 1
set +e
recipe_ok > "$work/recipe-src-cut.log" 2>&1
src_cut_rc=$?
set -e
test "$src_cut_rc" -ne 0
grep -F "MISSING_LIBXML2_OFF $src" "$work/recipe-src-cut.log"
restore
recipe_ok > "$work/recipe-restored.log"
cmp "$work/recipe-green.log" "$work/recipe-restored.log"

bad_rc=skipped
bad_cut_rc=skipped
good_rc=skipped
if [[ -n $bad ]]; then
    set +e
    bash "$checker" "$bad" > "$work/bad.log" 2>&1
    bad_rc=$?
    set -e
    test "$bad_rc" -eq 1
    grep -F "DT_NEEDED libxml2 in $bad" "$work/bad.log"
    python3 - "$checker" <<'PY'
import sys
from pathlib import Path
file = Path(sys.argv[1])
text = file.read_text()
old = '''if printf '%s\\n' "$deps" | grep -F libxml2 >/dev/null; then
    echo "DT_NEEDED libxml2 in $tool" >&2
    printf '%s\\n' "$deps" >&2
    exit 1
fi
'''
if old not in text:
    raise SystemExit("checker rejection block missing")
file.write_text(text.replace(old, "", 1))
PY
    diff -u "$work/checker.saved" "$checker" > "$work/checker-cut.diff" || test "$?" -eq 1
    set +e
    bash "$checker" "$bad" > "$work/bad-cut.log" 2>&1
    bad_cut_rc=$?
    set -e
    test "$bad_cut_rc" -eq 0
    grep -F "NO_LIBXML2" "$work/bad-cut.log"
    restore
    set +e
    bash "$checker" "$bad" > "$work/bad-restored.log" 2>&1
    bad_restored_rc=$?
    set -e
    test "$bad_restored_rc" -eq 1
    grep -F "DT_NEEDED libxml2 in $bad" "$work/bad-restored.log"
fi
if [[ -n $good ]]; then
    bash "$checker" "$good" > "$work/good.log"
    good_rc=0
    grep -F "NO_LIBXML2" "$work/good.log"
fi
sha256sum "$yml" "$src" "$checker" > "$work/restored.sha256"
cmp "$work/green.sha256" "$work/restored.sha256"
printf 'libxml2 recipe green=0 yml_cut=%s src_cut=%s restored=0 bad=%s bad_cut=%s good=%s\n' \
    "$yml_cut_rc" "$src_cut_rc" "$bad_rc" "$bad_cut_rc" "$good_rc"
