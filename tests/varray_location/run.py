#!/usr/bin/env python3
"""Compile the fixture with a real stage1, then assert its serialized locations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--sdk', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--fixture', type=Path, default=Path(__file__).with_name('compound.cj'))
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CANGJIE_HOME=str(a.sdk), cjHeapSize='32GB')
    env['LD_LIBRARY_PATH'] = ':'.join(str(a.sdk / part) for part in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    result = {'compiler': str(a.compiler), 'compiler_sha256': sha(a.compiler),
              'fixture_sha256': sha(a.fixture), 'checker_sha256': sha(Path(__file__).with_name('check.py')),
              'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True),
              'libraries': {str(f): sha(f) for f in sorted(
                  (a.sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))}}
    chir = a.out / 'output.chir'
    command = [str(a.compiler), str(a.fixture.resolve()), '--emit-chir=raw',
               '--output-type=staticlib', '--jobs', str(os.cpu_count()), '-o', str(chir)]
    result['command'] = command
    start = time.monotonic()
    with (a.out / 'compile.log').open('w') as log:
        result['compile_rc'] = subprocess.run(command, env=env, stdout=log,
                                               stderr=subprocess.STDOUT, timeout=300).returncode
    if result['compile_rc'] == 0:
        result['chir_sha256'] = sha(chir)
        with (a.out / 'check.log').open('w') as log:
            result['check_rc'] = subprocess.run(
                ['python3', str(Path(__file__).with_name('check.py')), str(chir), str(a.fixture),
                 '--json', str(a.out / 'checks.json')], stdout=log, stderr=subprocess.STDOUT).returncode
    result['wall'] = time.monotonic() - start
    result['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (a.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, sort_keys=True))
    return result['compile_rc'] or result['check_rc']


if __name__ == '__main__':
    raise SystemExit(main())
