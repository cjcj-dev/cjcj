#!/usr/bin/env python3
"""Assert diagnostics from a real stage1 CLI, without recreating semantic analysis."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import time


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--sdk', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CANGJIE_HOME=str(args.sdk), cjHeapSize='32GB')
    env['LD_LIBRARY_PATH'] = ':'.join(str(args.sdk / p) for p in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    result = dict(compiler=str(args.compiler), compiler_sha256=sha(args.compiler),
                  runner_sha256=sha(Path(__file__)), affinity=sorted(os.sched_getaffinity(0)),
                  uptime_before=subprocess.check_output(['uptime'], text=True),
                  libraries={str(p): sha(p) for p in
                             (args.sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so')})
    cases = {'closed': 'accept', 'interface': 'accept', 'tuple': 'accept',
             'missing': 'nonexhaustive', 'open_leaf': 'nonexhaustive',
             'nested': 'nonexhaustive', 'selectorless': 'two_unreachable', 'control': 'accept'}

    def run(item):
        name, expectation = item
        fixture = Path(__file__).with_name(name + '.cj').resolve()
        out = args.out / name
        out.mkdir(exist_ok=True)
        cmd = [str(args.compiler), str(fixture), '--emit-chir=raw',
               '--output-type=staticlib', '--jobs', str(os.cpu_count()), '-o', str(out / 'output.chir')]
        start = time.monotonic()
        with (out / 'compile.log').open('w') as log:
            try:
                rc = subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120).returncode
            except subprocess.TimeoutExpired:
                rc = 124
        text = re.sub(r'\x1b\[[0-9;]*m', '', (out / 'compile.log').read_text())
        # Semantic rejection is a product result, not a compiler build/loading failure.
        if expectation == 'accept':
            passed = rc == 0 and (out / 'output.chir').is_file() and 'unreachable' not in text.lower()
        elif expectation == 'nonexhaustive':
            passed = rc == 1 and ('not exhaustive' in text.lower() or 'non-exhaustive' in text.lower())
        else:
            passed = rc == 0 and text.lower().count('warning: unreachable') == 2
        print(f'ASSERT {name}.{expectation} {"PASS" if passed else "FAIL"} compiler_rc={rc}', flush=True)
        return name, dict(command=cmd, fixture_sha256=sha(fixture), rc=rc,
                          wall=time.monotonic()-start, assertion=expectation, passed=passed)

    with ThreadPoolExecutor(max_workers=4) as pool:
        result['cases'] = dict(pool.map(run, cases.items()))
    result['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    result['rc'] = 0 if all(c['passed'] for c in result['cases'].values()) else 1
    (args.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return result['rc']


if __name__ == '__main__':
    raise SystemExit(main())
