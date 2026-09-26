#!/usr/bin/env python3
"""Assert constant propagation from the real compiler's optimized CHIR output."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def function_body(text, name):
    # Match the source identifier, not a substring in an imported function name.
    match = re.search(r'^[^\n]*srcCodeIdentifier: ' + re.escape(name) +
                      r',[^\n]*\n(\{ Block Group:.*?^\})', text, re.M | re.S)
    return match.group(1) if match else ''



def stores_constant(body, value):
    constants = re.findall(r'(%\d+): Int64 = Constant\(' + str(value) + r'i\)', body)
    returns = re.findall(r'\[ret\] (%\d+): Int64& = Allocate\(Int64\)', body)
    return any(f'Store({constant}, {ret})' in body for constant in constants for ret in returns)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    fixture = Path(__file__).with_name('enum_cast.cj').resolve()
    command = [str(args.compiler.resolve()), str(fixture), '--emit-chir=opt',
               '--output-type=staticlib', '-O2', '--jobs', '1', '--dump-chir',
               '-o', str(args.out.resolve() / 'output.chir')]
    result = {'command': command, 'compiler_sha256': sha(args.compiler),
              'fixture_sha256': sha(fixture), 'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True).strip()}
    start = time.monotonic()
    with (args.out / 'compile.log').open('w') as log:
        run = subprocess.run(command, cwd=args.out.resolve(), stdout=log, stderr=subprocess.STDOUT, timeout=600)
    result.update(compile_rc=run.returncode, wall=time.monotonic() - start,
                  uptime_after=subprocess.check_output(['uptime'], text=True).strip(), assertions=[])
    if run.returncode == 0:
        dump = args.out / 'output_Emit_Debug.chirtxt'
        text = dump.read_text()
        result['chir_sha256'] = sha(args.out / 'output.chir')
        bodies = {name: function_body(text, name) for name in
                  ('knownChoice', 'dynamicChoice', 'numericControl')}
        known, dynamic, numeric = bodies.values()
        checks = [
            ('enum_round_trip_propagates', bool(known) and 'MultiBranch(' not in known
             and stores_constant(known, 22)),
            ('unknown_enum_keeps_branch', bool(dynamic) and 'MultiBranch(' in dynamic
             and not stores_constant(dynamic, 22)),
            ('numeric_cast_still_folds', bool(numeric) and stores_constant(numeric, 8)),
        ]
        for name, passed in checks:
            row = {'name': name, 'executed': True, 'pass': passed}
            result['assertions'].append(row)
            print(f'ASSERT {name} pass={passed}', flush=True)
        result['observed_functions'] = bodies
    passed = run.returncode == 0 and all(row['pass'] for row in result['assertions'])
    result['pass'] = passed
    (args.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
