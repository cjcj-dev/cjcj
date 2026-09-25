#!/usr/bin/env python3
"""Observe sealed-hierarchy rollback through the real incremental compiler CLI."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


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
    initial = '''package sealed_incremental
sealed abstract class Root {}
class A <: Root {}
func use(x: Root): Int64 {
    match (x) {
        case _: A => 1
    }
}
'''
    cases = {
        'add_child': (initial, initial + 'class B <: Root {}\n', True),
        'open_child': (initial, initial.replace('class A', 'open class A'), True),
        'add_unrelated': (initial, initial + 'class Other {}\n', False),
        'change_body': (initial, initial.replace('=> 1', '=> 3'), False),
    }
    results = dict(compiler_sha256=hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
                   affinity=sorted(os.sched_getaffinity(0)),
                   uptime_before=subprocess.check_output(['uptime'], text=True), cases={})
    # Each pair shares its own on-disk compiler cache and must execute in order.
    for name, (before, after, rollback) in cases.items():
        d = args.out / name
        d.mkdir(exist_ok=True)
        source = d / 'input.cj'
        steps = []
        cmd = [str(args.compiler), str(source), '--experimental', '--incremental-compile',
               '--emit-chir=raw', '--output-type=staticlib', '-o', str(d / 'output.chir')]
        for phase, text in [('initial', before), ('changed', after)]:
            source.write_text(text)
            start = time.monotonic()
            with (d / (phase + '.log')).open('w') as log:
                try:
                    rc = subprocess.run(cmd, env=env, cwd=d, stdout=log, stderr=subprocess.STDOUT,
                                        timeout=120).returncode
                except subprocess.TimeoutExpired:
                    rc = 124
            steps.append(dict(phase=phase, rc=rc, wall=time.monotonic()-start,
                              source_sha256=hashlib.sha256(text.encode()).hexdigest()))
        log = (d / 'changed.log').read_text()
        # The unchanged match must be rechecked after a hierarchy change.
        # Cut-record/cut-fallback must alter this result, otherwise cache fallback
        # elsewhere masked this mechanism and the arm is not valid evidence.
        passed = steps[0]['rc'] == 0 and steps[1]['rc'] == (1 if rollback else 0)
        if rollback:
            passed = passed and ('not exhaustive' in log.lower() or 'non-exhaustive' in log.lower())
        print(f'ASSERT {name}.hierarchy_rollback {"PASS" if passed else "FAIL"}', flush=True)
        results['cases'][name] = dict(command=cmd, steps=steps, passed=passed, rollback=rollback)
    results['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    results['rc'] = 0 if all(c['passed'] for c in results['cases'].values()) else 1
    (args.out / 'result.json').write_text(json.dumps(results, indent=2) + '\n')
    return results['rc']


if __name__ == '__main__':
    raise SystemExit(main())
