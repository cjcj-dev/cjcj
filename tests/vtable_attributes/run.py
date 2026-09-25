#!/usr/bin/env python3
"""Compare real CLI VTable attributes with a frozen serial compiler's output.

Only this field family is judged. No FINAL masking or permitted differences:
non-FINAL bits and entry coverage are independent control assertions.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import time

spec = importlib.util.spec_from_file_location(
    'chir_fields', Path(__file__).parents[1] / 'chir_builder/decoded_compare.py')
fields = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fields)
FINAL = 1 << 11


def decode(path):
    pkg = fields.Package(path.read_bytes())
    entries = {}
    for i, definition in enumerate(pkg.defs):
        tag = pkg.data[pkg.def_tags + 4 + i]
        if tag not in (1, 2, 3, 4):
            raise ValueError(f'unsupported definition union {tag}')
        custom = pkg.pointer(definition, 4)
        owner = [pkg.string(custom, 14), pkg.string(custom, 12)]
        for ti, table in enumerate(pkg.vector(custom, 30)):
            for mi, method in enumerate(pkg.vector(table, 6)):
                key = json.dumps([*owner, ti, mi, pkg.string(method, 4)])
                if key in entries:
                    raise ValueError(f'duplicate entry {key}')
                entries[key] = pkg.scalar(method, 12, 'Q')
    return entries


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--reference', type=Path)
    parser.add_argument('--jobs', nargs='+', type=int, default=[1, 192, 192, 192])
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=4)
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.output = args.output.resolve()
    args.output.mkdir(parents=True, exist_ok=True)
    sources = Path(__file__).parents[1] / 'chir_builder'
    record = {'compiler': str(args.compiler), 'elf_sha256': digest(args.compiler),
              'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True),
              'runs': [], 'assertions': []}

    def compile_one(item):
        name, index, jobs = item
        dest = args.output / name / str(index)
        dest.mkdir(parents=True, exist_ok=True)
        src = sources / (name + '.cj')
        cmd = [str(args.compiler), str(src), '--emit-chir=raw',
               '--output-type=staticlib', '-O0', '--jobs', str(jobs),
               '-o', str(dest / 'output.chir')]
        start = time.monotonic()
        with (dest / 'compile.log').open('w') as log:
            try:
                rc = subprocess.run(cmd, cwd=dest, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=600).returncode
            except subprocess.TimeoutExpired:
                rc = 124
        result = {'name': name, 'index': index, 'jobs': jobs, 'command': cmd,
                  'rc': rc, 'wall': time.monotonic() - start,
                  'source_sha256': digest(src)}
        if rc != 0:
            return result
        output = dest / 'output.chir'
        result['chir_sha256'] = digest(output)
        result['attributes'] = decode(output)
        (dest / 'attributes.json').write_text(json.dumps(result['attributes'], indent=2)+'\n')
        return result

    def check(name, passed, **detail):
        row = {'name': name, 'pass': passed, **detail}
        record['assertions'].append(row)
        print(('PASS ' if passed else 'FAIL ') + name + ' ' + json.dumps(detail), flush=True)

    try:
        # At most four real compiler processes per lane; each has a bounded heap.
        work = [(name, i, jobs) for name in ('literal', 'generic_receiver')
                for i, jobs in enumerate(args.jobs)]
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            record['runs'] = list(pool.map(compile_one, work))
        for run in record['runs']:
            label = f"{run['name']}/{run['index']}/j{run['jobs']}"
            check(label + '/compiled', run['rc'] == 0, rc=run['rc'])
            if run['rc'] != 0:
                continue
            actual = run['attributes']
            refdir = args.reference.resolve() if args.reference else args.output
            expected = json.loads((refdir / run['name'] / '0/attributes.json').read_text())
            witness = [k for k in actual if 'Iterator' in k and 'iterator' in k]
            check(label + '/iterator_coverage', bool(witness), entries=len(witness))
            check(label + '/entry_coverage', actual.keys() == expected.keys(),
                  actual=len(actual), expected=len(expected))
            common = actual.keys() & expected.keys()
            nonfinal = [k for k in common if (actual[k] ^ expected[k]) & ~FINAL]
            final = [{'entry': k, 'expected': hex(expected[k]), 'actual': hex(actual[k])}
                     for k in sorted(common) if (actual[k] ^ expected[k]) & FINAL]
            check(label + '/non_final_attributes', not nonfinal, differences=nonfinal)
            check(label + '/final_snapshot', not final, differences=final)
        record['rc'] = int(not all(x['pass'] for x in record['assertions']))
    except Exception as exc:
        record['error'] = repr(exc)
        record['rc'] = 2
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (args.output / 'result.json').write_text(json.dumps(record, indent=2)+'\n')
    return record['rc']


if __name__ == '__main__':
    raise SystemExit(main())
