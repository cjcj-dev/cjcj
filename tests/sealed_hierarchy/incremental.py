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
        # cb97757c consults the cached relation graph: a newly added child
        # is absent. Preserve that upstream behavior (advisor 20260925T124853Z).
        'add_child': (initial, initial + 'class B <: Root {}\n', False),
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
               '--output-type=staticlib', '-o', str(d / 'output.a')]
        for phase, text in [('initial', before), ('changed', after)]:
            source.write_text(text)
            start = time.monotonic()
            with (d / (phase + '.log')).open('w') as log:
                try:
                    rc = subprocess.run(cmd, env=env, cwd=d, stdout=log, stderr=subprocess.STDOUT,
                                        timeout=120).returncode
                except subprocess.TimeoutExpired:
                    rc = 124
            cache_log = '\n'.join(p.read_text() for p in (d / '.cached').rglob('*.log'))
            (d / (phase + '-incremental.log')).write_text(cache_log)
            steps.append(dict(phase=phase, rc=rc, wall=time.monotonic()-start,
                              source_sha256=hashlib.sha256(text.encode()).hexdigest()))
        log = (d / 'changed.log').read_text()
        # The unchanged match must be rechecked after a hierarchy change.
        # Cut-record/cut-fallback must alter this result, otherwise cache fallback
        # elsewhere masked this mechanism and the arm is not valid evidence.
        passed = steps[0]['rc'] == 0 and steps[1]['rc'] == (1 if rollback else 0)
        if rollback:
            passed = passed and ('not exhaustive' in log.lower() or 'non-exhaustive' in log.lower())
            passed = passed and 'changed subtype of sealed type:' in cache_log and 'full sema' in cache_log
        else:
            passed = passed and 'incremental compilation triggered' in cache_log
        passed = passed and 'load cached info failed' not in cache_log
        print(f'ASSERT {name}.upstream_incremental_result {"PASS" if passed else "FAIL"}', flush=True)
        results['cases'][name] = dict(command=cmd, steps=steps, passed=passed, rollback=rollback)
    results['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    results['rc'] = 0 if all(c['passed'] for c in results['cases'].values()) else 1
    (args.out / 'result.json').write_text(json.dumps(results, indent=2) + '\n')
    return results['rc']


if __name__ == '__main__':
    raise SystemExit(main())
