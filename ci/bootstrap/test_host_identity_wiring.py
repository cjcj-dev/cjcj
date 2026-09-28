#!/usr/bin/env python3
"""Run native host identity apparatus arms with the same tests and real inputs."""
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    root = Path(__file__).resolve().parent
    out = Path(sys.argv[1]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    for name in ('HOST_IDENTITY_SDK', 'HOST_IDENTITY_LLVM'):
        if not os.environ.get(name):
            raise RuntimeError(f'{name} is required; real input tests must not skip')
    runner = root / 'stage1_host_runner.sh'
    identities = root / 'stage1_host_identities.txt'
    test = root / 'test_host_identities.py'
    platform = 'linux_' + os.uname().machine
    original = runner.read_text()
    call = 'check_sha "$hrt/libcangjie-runtime.so" "$decl_runtime"\n'
    assert original.count(call) == 1
    cut = original.replace(call, '')
    (out / 'runner-cut.sh').write_text(cut)
    (out / 'cut.diff').write_text(''.join(difflib.unified_diff(
        original.splitlines(True), cut.splitlines(True),
        fromfile='a/ci/bootstrap/stage1_host_runner.sh', tofile='b/ci/bootstrap/stage1_host_runner.sh')))
    lines = identities.read_text().splitlines(True)
    changed = 0
    for i, line in enumerate(lines):
        if line.startswith(platform + ' libcangjie-runtime.so '):
            fields = line.split()
            fields[2] = ('0' if fields[2][0] != '0' else '1') + fields[2][1:]
            lines[i] = ' '.join(fields) + '\n'
            changed += 1
    assert changed == 1
    (out / 'pin-cut.txt').write_text(''.join(lines))
    (out / 'producer-cut.diff').write_text(''.join(difflib.unified_diff(
        identities.read_text().splitlines(True), lines,
        fromfile='a/ci/bootstrap/stage1_host_identities.txt', tofile='b/ci/bootstrap/stage1_host_identities.txt')))
    before = {str(p): digest(p) for p in (runner, identities, test)}
    arms = [('candidate', {}),
            ('consumer-cut', {'STAGE1_RUNNER_PRODUCT': str(out / 'runner-cut.sh')}),
            ('producer-cut', {'STAGE1_PIN_PRODUCT': str(out / 'pin-cut.txt')}),
            ('restored', {})]
    processes = []
    for name, extra in arms:
        env = {**os.environ, 'TMPDIR': str(out), **extra}
        log = (out / (name + '.log')).open('w')
        start = time.monotonic()
        proc = subprocess.Popen([sys.executable, str(test)], env=env, stdout=log, stderr=subprocess.STDOUT)
        processes.append((name, proc, log, start))
    results = {}
    for name, proc, log, start in processes:
        rc = proc.wait()
        log.close()
        text = (out / (name + '.log')).read_text()
        count = re.search(r'^Ran (\d+) tests? in ', text, re.M)
        results[name] = {'rc': rc, 'wall': round(time.monotonic() - start, 3),
                         'tests': int(count[1]) if count else 0,
                         'failures': re.findall(r'^FAIL: (\w+)', text, re.M),
                         'errors': re.findall(r'^ERROR: (\w+)', text, re.M),
                         'skipped': 'skipped=' in text}
        print(name, results[name], flush=True)
    identity = {'platform': platform, 'sources': before,
                'consumer-cut': digest(out / 'runner-cut.sh'), 'producer-cut': digest(out / 'pin-cut.txt')}
    (out / 'arms.json').write_text(json.dumps({'arms': results, 'identity': identity}, indent=2) + '\n')
    assert before == {str(p): digest(p) for p in (runner, identities, test)}
    expected = {'candidate': [], 'consumer-cut': ['test_hrt_runtime_bytes'],
                'producer-cut': ['test_fixed_release_triple'], 'restored': []}
    for name, failures in expected.items():
        result = results[name]
        assert result['failures'] == failures, (name, result)
        assert result['rc'] == (1 if failures else 0), (name, result)
        assert result['tests'] > 0 and not result['errors'] and not result['skipped'], (name, result)
        assert result['tests'] == results['candidate']['tests'], (name, result)
        print('ASSERT exact-failure-set', name, failures, flush=True)


if __name__ == '__main__':
    main()
