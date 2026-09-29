#!/usr/bin/env python3
"""Check real compiler diagnostics after repeated operator-call desugaring."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--sdk', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CANGJIE_HOME=str(args.sdk), cjHeapSize='32GB')
    env['LD_LIBRARY_PATH'] = ':'.join(str(args.sdk / p) for p in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib'))
    record = dict(compiler=str(args.compiler), compiler_sha256=sha(args.compiler),
                  affinity=sorted(os.sched_getaffinity(0)),
                  uptime_before=subprocess.check_output(['uptime'], text=True),
                  libraries={str(p): sha(p) for p in sorted(
                      (args.sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))})
    here = Path(__file__).resolve().parent

    def check(name):
        fixture = here / (name + '.cj')
        out = args.out / name
        out.mkdir(exist_ok=True)
        cmd = [str(args.compiler), str(fixture), '--output-type=staticlib',
               '-o', str(out / 'fixture.a')]
        start = time.monotonic()
        with (out / 'compile.log').open('w') as log:
            result = subprocess.run(cmd, cwd=out, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=180)
        text = re.sub(r'\x1b\[[0-9;]*m', '', (out / 'compile.log').read_text())
        checks = {}
        if name == 'control':
            checks['ordinary_const_accepted'] = result.returncode == 0
        else:
            # Separate verdict and location assertions: neither masks the other.
            checks['array_rejected_as_nonconstant'] = (
                result.returncode == 1 and "expected 'const' expression" in text
                and "expressions of type 'Array' are not constant" in text)
            positions = re.findall(re.escape(fixture.name) + r':(\d+):(\d+)', text)
            checks['diagnostic_on_call_site'] = any(
                int(line) == 9 and int(column) > 0 for line, column in positions)
            checks['no_internal_error'] = 'Internal Compiler Error' not in text
        for assertion, passed in checks.items():
            print(f'ASSERT {name}.{assertion} {"PASS" if passed else "FAIL"}', flush=True)
        return name, dict(command=cmd, compile_rc=result.returncode,
                          fixture_sha256=sha(fixture), wall=time.monotonic()-start,
                          checks=checks)

    # Independent output directories avoid shared compiler-output state.
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        record['cases'] = dict(pool.map(check, ['empty', 'nonempty', 'generic', 'control']))
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    record['rc'] = int(not all(all(case['checks'].values())
                               for case in record['cases'].values()))
    (args.out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record['rc']


if __name__ == '__main__':
    raise SystemExit(main())
