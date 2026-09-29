#!/usr/bin/env python3
"""Exercise the product CLI; never reconstruct compiler components in the test."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('--compiler', required=True)
p.add_argument('--plugin', required=True)
p.add_argument('--reject-plugin', required=True)
p.add_argument('--missing-free-plugin', required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
root = Path(a.output).resolve()
root.mkdir(parents=True, exist_ok=True)
inputs = Path(__file__).resolve().parent
results = []
received = 'ASSERT plugin received serialized input: true'
freed = 'ASSERT plugin borrowed input survived deserialization: true'
for name in ('main', 'builtin', 'custom'):
    for mode, plugin in (('plain', None), ('pass', a.plugin)):
        results.append((name, mode, plugin))
results += [('main', 'reject', a.reject_plugin), ('main', 'missing-free', a.missing_free_plugin)]
records = []
for name, mode, plugin in results:
    label = name + '-' + mode
    out = root / label
    out.mkdir()  # A stale artifact must never satisfy output-produced.
    cmd = [a.compiler, str(inputs / (name + '.cj')), '-O0', '--output-type=staticlib', '--output-dir', str(out)]
    if plugin:
        cmd += ['--plugin', plugin]
    start = time.monotonic()
    run = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
    log = run.stdout
    (root / (label + '.log')).write_text(log)
    checks = {}
    if mode in ('plain', 'pass'):
        checks['cli-success'] = run.returncode == 0
        checks['output-produced'] = any(f.is_file() and f.stat().st_size > 0 for f in out.glob('*.a'))
    else:
        checks['cli-failure'] = run.returncode != 0
    if mode == 'pass':
        checks['input-valid'] = log.count(received) == 1
        checks['free-once-input-unchanged'] = log.count(freed) == 1
        checks['no-false-assertion'] = ': false' not in log
    elif mode == 'reject':
        checks['input-valid'] = log.count(received) == 1
        checks['no-free-after-rejection'] = 'borrowed input survived' not in log
    elif mode == 'missing-free':
        checks['input-valid'] = log.count(received) == 1
        checks['no-free-export'] = 'borrowed input survived' not in log
    else:
        checks['no-plugin-callback'] = 'ASSERT plugin' not in log
    row = dict(test=label, command=cmd, rc=run.returncode, wall=time.monotonic()-start, assertions=checks)
    records.append(row)
    for key, value in checks.items():
        print(f'ASSERT {label}/{key}: {value}', flush=True)
identity = {str(Path(f).resolve()): hashlib.sha256(Path(f).read_bytes()).hexdigest()
            for f in (a.compiler, a.plugin, a.reject_plugin, a.missing_free_plugin)}
(root / 'results.json').write_text(json.dumps(dict(identity=identity, tests=records), indent=2))
raise SystemExit(0 if all(all(r['assertions'].values()) for r in records) else 1)
