#!/usr/bin/env python3
"""Check live virtual getter declarations after the real compiler's dead function pass."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def check(source, compiler, out):
    destination = out / source.stem
    destination.mkdir(parents=True, exist_ok=True)
    # Keep dispatch in CHIR so the declaration/use invariant can be read even
    # when a broken callee user edge would fail the subsequent devirtualizer.
    command = [str(compiler), str(source), '-O2', '--emit-chir=opt',
               '--output-type=exe', '--dump-chir', '--fno-chir-devirtualization',
               '--fno-chir-function-inlining', '--jobs', str(os.cpu_count()),
               '-o', str(destination / 'output.chir')]
    start = time.monotonic()
    with (destination / 'compile.log').open('w') as log:
        try:
            rc = subprocess.run(command, cwd=destination, stdout=log,
                                stderr=subprocess.STDOUT, timeout=180).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    dumps = sorted(destination.glob('**/*RunArrayListConstStartOpt.chirtxt'))
    assertions = []
    if rc == 0 and dumps:
        text = dumps[-1].read_text()
        if source.stem == 'control':
            assertions.append(dict(name='concrete_getter_retained', passed='srcCodeIdentifier: $sizeget,' in text))
        else:
            kind = 'InvokeStatic' if source.stem == 'static' else 'Invoke'
            callees = set(re.findall(r'\b' + kind + r'\([^\n]*?->(@[^,\n]+),', text))
            getters = sorted(name for name in callees if 'sizepg' in name)
            declarations = {}
            for match in re.finditer(r'^.*?\bFunc (@[^\n(]+)\([^\n]*(?:\n.*?)*?\):[^\n]*', text, re.M):
                declarations[match[1]] = match[0]
            assertions.append(dict(name='virtual_getter_executed_in_chir', passed=bool(getters), observed=getters))
            assertions.append(dict(name='live_getter_keeps_declaring_type', passed=bool(getters) and
                                   all('declaredParent:' in declarations.get(name, '') for name in getters),
                                   observed={name: declarations.get(name) for name in getters}))
    record = dict(case=source.stem, command=command, rc=rc, wall=time.monotonic()-start,
                  input_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), assertions=assertions)
    record['passed'] = rc == 0 and bool(assertions) and all(a['passed'] for a in assertions)
    for assertion in assertions:
        print(f"ASSERT {source.stem}:{assertion['name']} {'PASS' if assertion['passed'] else 'FAIL'}", flush=True)
    if not assertions:
        print(f"NOT_RUN {source.stem}: compile_rc={rc} dumps={len(dumps)}", flush=True)
    (destination / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    compiler, out = args.compiler.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    before = subprocess.check_output(['uptime'], text=True).strip()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        cases = list(pool.map(lambda source: check(source, compiler, out),
                              sorted(Path(__file__).resolve().parent.glob('*.cj'))))
    manifest = dict(compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                    affinity=sorted(os.sched_getaffinity(0)), uptime_before=before,
                    uptime_after=subprocess.check_output(['uptime'], text=True).strip(), cases=cases)
    (out / 'result.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return 0 if all(case['passed'] for case in cases) else 1


if __name__ == '__main__':
    raise SystemExit(main())
