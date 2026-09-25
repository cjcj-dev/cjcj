#!/usr/bin/env python3
"""Observe generic-call target selection through the product compiler CLI."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).with_name('override_resolver_fixtures')

    def check(name):
        source = fixtures / (name + '.cj')
        destination = args.out / name
        destination.mkdir(exist_ok=True)
        # The text dump is the criterion: inspect the actual instantiated call target.
        command = [str(args.compiler), str(source.resolve()), '-O2', '--emit-chir=raw',
                   '--output-type=staticlib', '--dump-chir', '--jobs', str(os.cpu_count()),
                   '--diagnostic-format=noColor', '-o', str(destination / 'result.chir')]
        start = time.monotonic()
        with (destination / 'compile.log').open('w') as log:
            rc = subprocess.call(command, cwd=destination, stdout=log, stderr=subprocess.STDOUT)
        dump = destination / 'result_Emit_Debug.chirtxt'
        text = dump.read_text() if dump.exists() else ''
        blocks = re.split(r'(?m)(?=^\[.*\] Func )', text)
        target_function = 'invoke' if name == 'generic_override' else 'main'
        selected = [block for block in blocks if
                    f'srcCodeIdentifier: {target_function},' in block.split('{', 1)[0]
                    and 'packageName: resolver_fixture' in block.split('{', 1)[0]
                    and (name != 'generic_override' or '[generic_instantiated]' in block.split('\n', 1)[0])]
        calls = [line.strip() for block in selected for line in block.splitlines()
                 if re.search(r'\b(?:Apply|Invoke)\(', line) and '3fooH' in line]
        expected = '@_CN16resolver_fixture1C3fooHv'
        target_ok = len(selected) == 1 and len(calls) == 1 and expected in calls[0]
        passed = rc == 0 and target_ok
        record = {'name': name, 'command': command, 'rc': rc,
                  'source_sha256': digest(source), 'wall': time.monotonic() - start,
                  'function_count': len(selected), 'calls': calls, 'expected_target': expected,
                  'assertion_executed': True, 'target_ok': target_ok, 'pass': passed,
                  'dump_sha256': digest(dump) if dump.exists() else None,
                  'chir_sha256': digest(destination / 'result.chir') if (destination / 'result.chir').exists() else None}
        print(f"{'PASS' if passed else 'FAIL'} {name} rc={rc} target_ok={target_ok} calls={calls}", flush=True)
        return record

    manifest = {'compiler': str(args.compiler), 'compiler_sha256': digest(args.compiler),
                'affinity': sorted(os.sched_getaffinity(0)),
                'uptime_before': subprocess.check_output(['uptime'], text=True).strip()}
    with ThreadPoolExecutor(max_workers=2) as pool:
        manifest['cases'] = list(pool.map(check, ['generic_override', 'direct_member']))
    manifest['uptime_after'] = subprocess.check_output(['uptime'], text=True).strip()
    (args.out / 'result.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return 0 if all(case['pass'] for case in manifest['cases']) else 1


if __name__ == '__main__':
    raise SystemExit(main())
