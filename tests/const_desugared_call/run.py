#!/usr/bin/env python3
"""Check real compiler diagnostics after repeated operator-call desugaring."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
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
    # RunDriverMain selects the real frontend from argv[0]. Keep the complete
    # product ELF and invoke it under its supported frontend entry name.
    bindir = args.out / 'bin'
    bindir.mkdir(exist_ok=True)
    product = bindir / 'cjcj-stage1'
    shutil.copy2(args.compiler, product)
    for name in ('cjc', 'cjc-frontend'):
        alias = bindir / name
        if alias.is_symlink():
            alias.unlink()
        alias.symlink_to('cjcj-stage1')
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
        cmd = [str(bindir / 'cjc-frontend'), str(fixture), '--typecheck']
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
            diagnostics = re.split(r'(?m)(?=^(?:error|warning):)', text)
            array_diagnostics = [d for d in diagnostics
                                 if d.startswith("error: expected 'const' expression")
                                 and "expressions of type 'Array' are not constant" in d]
            checks['array_rejected_as_nonconstant'] = (
                result.returncode == 1 and bool(array_diagnostics))
            # Bind the location to the Array error, not a note or unrelated error.
            locations = [re.search(re.escape(fixture.name) + r':(\d+):(\d+)', d)
                         for d in array_diagnostics]
            checks['diagnostic_on_call_site'] = bool(locations) and all(
                p is not None and int(p[1]) == 9 and int(p[2]) > 0 for p in locations)
            checks['no_internal_error'] = 'Internal Compiler Error' not in text
        for assertion, passed in checks.items():
            print(f'ASSERT {name}.{assertion} {"PASS" if passed else "FAIL"}', flush=True)
        return name, dict(command=cmd, compile_rc=result.returncode,
                          fixture_sha256=sha(fixture), wall=time.monotonic()-start,
                          checks=checks)

    # Validate a real process result before expanding the authorized set.
    # Verdict failures are the observations in baseline/cut arms; a crash stops
    # dependent cases and remains a failure to execute.
    record['cases'] = {}
    for name in ['empty', 'nonempty', 'generic', 'control']:
        key, case = check(name)
        record['cases'][key] = case
        if case['compile_rc'] not in (0, 1):
            record['not_run'] = [n for n in ['empty', 'nonempty', 'generic', 'control']
                                 if n not in record['cases']]
            break
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    record['rc'] = int(not all(all(case['checks'].values())
                               for case in record['cases'].values()))
    (args.out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record['rc']


if __name__ == '__main__':
    raise SystemExit(main())
