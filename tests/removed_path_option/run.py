#!/usr/bin/env python3
"""Check removed source identity options through the product CLI."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--compiler', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
results = []
for name, flags, rejected in [
    ('help', ['--help'], False),
    ('trimpath', ['--trimpath=/source', '--help'], False),
    ('removed-equals', ['--path-prefix-map=/source=/stable', '--help'], True),
    ('removed-separated', ['--path-prefix-map', '/source=/stable', '--help'], True),
]:
    r = subprocess.run([str(a.compiler), *flags], capture_output=True, text=True)
    output = r.stdout + r.stderr
    (a.out / (name + '.log')).write_text(output)
    ok = (r.returncode != 0 and 'invalid option' in output and '--path-prefix-map' in output) if rejected else r.returncode == 0
    results.append(dict(name=name, rc=r.returncode, passed=ok))
    print(f'TARGET {name}: {"PASS" if ok else "FAIL"} rc={r.returncode}', flush=True)
record = dict(compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest(), results=results)
(a.out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
