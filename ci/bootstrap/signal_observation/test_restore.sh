#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
root=$(cd "$(dirname "$0")" && pwd)
out=$1
mkdir -p "$out"
uptime > "$out/uptime-before.txt"
cp "$root/calibrate.c" "$root/test_calibrate.c" "$out/"
cp "$out/calibrate.c" "$out/candidate.c"
python3 - "$out" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1])
s=(p/'candidate.c').read_text()
(p/'cut.c').write_text(s.replace('restore_request = valid;', 'restore_request = original_old;'))
PY
diff -u "$out/candidate.c" "$out/cut.c" > "$out/cut.diff" || test "$?" = 1
for arm in candidate cut restored; do
  mkdir -p "$out/$arm"
  cp "$out/test_calibrate.c" "$out/$arm/"
  if [[ $arm == cut ]]; then cp "$out/cut.c" "$out/$arm/calibrate.c"; else cp "$out/candidate.c" "$out/$arm/calibrate.c"; fi
  (
    cc -O0 -g -fdebug-prefix-map="$out/$arm"=/offline "$out/$arm/test_calibrate.c" -o "$out/$arm/test"
    sha256sum "$out/$arm/test" "$out/$arm/calibrate.c" > "$out/$arm/hashes.txt"
    for scenario in 0 1 2 3 4 5; do
      (set +e; "$out/$arm/test" "$scenario" > "$out/$arm/$scenario.log"; echo "$?" > "$out/$arm/$scenario.rc") &
    done
    wait
  ) &
done
wait
python3 - "$out" <<'PY'
import pathlib, sys, json
p=pathlib.Path(sys.argv[1]); result={}
for arm in ('candidate', 'cut', 'restored'):
    result[arm]={str(i):int((p/arm/f'{i}.rc').read_text()) for i in range(6)}
assert result['candidate']==result['restored']=={str(i):0 for i in range(6)}, result
assert result['cut']=={str(i):int(i==0) for i in range(6)}, result
(p/'results.json').write_text(json.dumps(result,indent=2)); print(result)
PY
for arm in candidate cut restored; do
  mkdir -p "$out/observer-$arm"
  cp "$root"/*.py "$out/observer-$arm/"
  if [[ $arm == cut ]]; then
    python3 - "$out/observer-$arm/observer.py" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1]); p.write_text(p.read_text().replace("raise RuntimeError('CALIBRATION_RESTORE_STATE')", "pass # cut restore-state consumer rejection"))
PY
  fi
  (set +e; python3 -m unittest discover -s "$out/observer-$arm" -p 'test_*.py' -v > "$out/observer-$arm.log" 2>&1; echo "$?" > "$out/observer-$arm.rc") &
done
wait
python3 - "$out" <<'PY'
import pathlib, sys, re
p=pathlib.Path(sys.argv[1])
assert (p/'observer-candidate.rc').read_text().strip()=='0'
assert (p/'observer-restored.rc').read_text().strip()=='0'
assert (p/'observer-cut.rc').read_text().strip()=='1'
fails=re.findall(r'^FAIL: (\w+)', (p/'observer-cut.log').read_text(), re.M)
assert fails==['test_postquery_enabled'], fails
print('CONSUMER_CUT', fails)
PY
uptime > "$out/uptime-after.txt"
# Executables are intermediate artifacts; keep logs, source, hashes and results.
rm "$out/candidate/test" "$out/cut/test" "$out/restored/test"
