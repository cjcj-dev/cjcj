#!/usr/bin/env python3
"""Check inheritance diagnostics through the real compiler CLI."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

INTERFACE = "cannot override implemented interface function 'f' with abstract function"
CLASS = "cannot override non-abstract function 'f' with abstract function"
EXPECTED = {'indirect_abstract': INTERFACE, 'direct_abstract': INTERFACE,
            'class_abstract': CLASS, 'concrete_override': None, 'inherited_default': None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).with_name('abstract_redeclaration_fixtures')

    def check(item):
        name, expected = item
        dest = args.out / name
        dest.mkdir(exist_ok=True)
        command = [str(args.compiler.resolve()), str(fixtures / (name + '.cj')),
                   '--emit-chir=raw', '--dump-chir', '-o', str(dest / 'output.chir')]
        start = time.monotonic()
        process = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, timeout=180, cwd=dest)
        (dest / 'compile.log').write_text(process.stdout)
        errors = [line.strip() for line in process.stdout.splitlines() if line.startswith('error:')]
        passed = ((process.returncode == 1 and errors == ['error: ' + expected]) if expected else
                  (process.returncode == 0 and not errors and (dest / 'output.chir').exists()))
        result = {'name': name, 'command': command, 'rc': process.returncode, 'errors': errors,
                  'expected': expected, 'pass': passed, 'assertion_executed': True,
                  'wall': time.monotonic() - start,
                  'outputs': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in dest.glob('*.chir')}}
        print(f"{'PASS' if passed else 'FAIL'} {name} rc={process.returncode} errors={errors} assertion_executed=true", flush=True)
        return result

    before = subprocess.check_output(['uptime'], text=True).strip()
    with ThreadPoolExecutor(max_workers=len(EXPECTED)) as pool:
        results = list(pool.map(check, EXPECTED.items()))
    manifest = {'compiler': str(args.compiler), 'compiler_sha256': hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
                'affinity': sorted(os.sched_getaffinity(0)), 'uptime_before': before,
                'uptime_after': subprocess.check_output(['uptime'], text=True).strip(), 'cases': results}
    (args.out / 'result.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return 0 if all(case['pass'] for case in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
