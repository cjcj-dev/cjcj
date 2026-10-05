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


def classify(text, rc, fixture):
    """Keep diagnostic identity, execution status and location independent."""
    text = re.sub(r'\x1b\[[0-9;]*m', '', text)
    if rc not in (0, 1) or re.search(r'Internal Compiler Error|Segmentation fault|Assertion.*failed|terminate called', text, re.I):
        return 'INTERNAL_OR_EXECUTION_FAILURE', []
    if re.search(r"invalid option:|Invalid options\.|'main' is missing", text):
        return 'ENTRY_FAILURE', []
    if rc == 0:
        return 'COMPILE_SUCCESS', []
    blocks = [b for b in re.split(r'(?m)(?=^(?:error|warning):)', text)
              if b.startswith('error:')]
    targets = []
    for block in blocks:
        if not block.startswith("error: expected 'const' expression\n"):
            continue
        normal = ("expressions of type 'Array' are not constant" in block and
                  re.search(re.escape(fixture) + r':\d+:\d+:', block))
        zero = (re.search(r'(?m)^\s*==> :0:0:', block) and
                re.search(r"note: consider add type annotation 'VArray<Int64, \$\d+>' to use value array", block))
        if normal or zero:
            targets.append(block)
    count = re.search(r'(\d+) errors? generated, (\d+) errors? printed\.', text)
    if not targets or len(targets) != len(blocks) or not count or any(int(v) != len(targets) for v in count.groups()):
        return 'UNKNOWN_FAIL', []
    bad = any(re.search(r'(?m)^\s*==> :0:0:', b) for b in targets)
    return ('TARGET_CONST_BAD_LOCATION' if bad else 'TARGET_CONST'), targets


def const_checks(text, rc, fixture, name):
    classification, targets = classify(text, rc, fixture)
    if name == 'control':
        checks = {'ordinary_const_accepted': classification == 'COMPILE_SUCCESS'}
    else:
        locations = [re.search(re.escape(fixture) + r':(\d+):(\d+):', b) for b in targets]
        checks = {
            'array_rejected_as_nonconstant': classification in ('TARGET_CONST', 'TARGET_CONST_BAD_LOCATION'),
            'diagnostic_on_call_site': bool(locations) and all(
                p is not None and int(p[1]) == 9 and int(p[2]) > 0 for p in locations),
            'no_internal_error': classification != 'INTERNAL_OR_EXECUTION_FAILURE',
        }
    return classification, checks


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--observe-failures', action='store_true',
                        help='Continue target assertion failures in baseline/cut arms only')
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
        cmd = [str(bindir / 'cjc-frontend'), str(fixture), '--emit-chir=raw',
               '--output-type=staticlib', '-o', str(out / 'output.chir')]
        start = time.monotonic()
        with (out / 'compile.log').open('w') as log:
            result = subprocess.run(cmd, cwd=out, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=180)
        text = re.sub(r'\x1b\[[0-9;]*m', '', (out / 'compile.log').read_text())
        classification, checks = const_checks(text, result.returncode, fixture.name, name)
        entry_failure = classification in ('ENTRY_FAILURE', 'INTERNAL_OR_EXECUTION_FAILURE', 'UNKNOWN_FAIL')
        for assertion, passed in checks.items():
            print(f'ASSERT {name}.{assertion} {"PASS" if passed else "FAIL"}', flush=True)
        return name, dict(command=cmd, compile_rc=result.returncode,
                          fixture_sha256=sha(fixture), wall=time.monotonic()-start,
                          entry_failure=entry_failure, classification=classification,
                          checks=checks)

    # Validate a real process result before expanding the authorized set.
    # Verdict failures are the observations in baseline/cut arms; a crash stops
    # dependent cases and remains a failure to execute.
    record['cases'] = {}
    for name in ['empty', 'nonempty', 'generic', 'control']:
        key, case = check(name)
        record['cases'][key] = case
        if case['entry_failure'] or (not args.observe_failures and
                                     not all(case['checks'].values())):
            record['not_run'] = [n for n in ['empty', 'nonempty', 'generic', 'control']
                                 if n not in record['cases']]
            break
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    record['rc'] = int(bool(record.get('not_run')) or not all(not case['entry_failure'] and all(case['checks'].values())
                               for case in record['cases'].values()))
    (args.out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record['rc']


if __name__ == '__main__':
    raise SystemExit(main())
