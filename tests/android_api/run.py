#!/usr/bin/env python3
"""Observe Android target parsing through the product compiler CLI.

No source file is intentional: option parsing runs before the missing-input
error, so these checks require neither an Android SDK nor cross-linking.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--compiler', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
a.compiler = a.compiler.resolve()
a.output.mkdir(parents=True, exist_ok=True)
record = {'compiler': str(a.compiler),
          'sha256': hashlib.sha256(a.compiler.read_bytes()).hexdigest(),
          'uptime_before': subprocess.check_output(['uptime'], text=True),
          'affinity': sorted(os.sched_getaffinity(0)), 'cases': {}}
cases = [
    ('default_api', 'android', 'Use API level 23 by default.'),
    ('explicit_minimum', 'android23', None),
    ('explicit_26', 'android26', None),
    ('below_minimum', 'android22', 'The Android API level is not supported in the target.'),
    ('above_maximum', 'android10001', 'The Android API level is not supported in the target.'),
    ('illegal_api', 'android999999999999999999999999',
     'The Android API level is illegal. Please use a valid API level which is greater than or equal to 23.'),
]
try:
    for name, suffix, expected in cases:
        cmd = [str(a.compiler), '--target=aarch64-linux-' + suffix]
        start = time.monotonic()
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=60)
        log = result.stdout
        (a.output / (name + '.log')).write_text(log)
        # These conditions distinguish a completed option parse from a launch failure.
        if result.returncode != 1 or 'expected at least one source code file when compiling source code' not in log:
            raise RuntimeError(f'{name}: option parsing did not complete: rc={result.returncode}: {log}')
        ok = (expected in log if expected else 'Android API level' not in log)
        if name == 'illegal_api':
            ok = ok and '26' not in log
        record['cases'][name] = {'pass': ok, 'command': cmd, 'rc': result.returncode,
                                 'observed': log, 'wall': time.monotonic() - start}
        print(('PASS ' if ok else 'FAIL ') + name + ': ' + json.dumps(log), flush=True)
    record['rc'] = int(not all(x['pass'] for x in record['cases'].values()))
except (OSError, RuntimeError, subprocess.TimeoutExpired) as exc:
    record['error'] = str(exc)
    record['rc'] = 2
finally:
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (a.output / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
raise SystemExit(record['rc'])
