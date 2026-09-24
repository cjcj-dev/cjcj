#!/usr/bin/env python3
"""Exercise the product CJO writer and reader, using upstream PackageTest mutations."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import time


def run(cmd, cwd, log):
    start = time.monotonic()
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    log.write_bytes(p.stdout)
    return {'command': [str(x) for x in cmd], 'rc': p.returncode,
            'wall': time.monotonic() - start, 'log': str(log)}, p.stdout.decode(errors='replace')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--fixture-cjo', type=Path, help='Reuse identical product-written CJO across reader arms')
    args = ap.parse_args()
    compiler, out = args.compiler.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).resolve().parent / 'cjo_version_fixtures'
    result = {'compiler': str(compiler), 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'cases': []}
    if args.fixture_cjo:
        data = args.fixture_cjo.read_bytes()
    else:
        producer = out / 'producer'
        producer.mkdir(exist_ok=True)
        invocation, output = run([compiler, fixtures / 'vercheck.cj', '--output-type=staticlib',
                                  '-o', producer / 'libvercheck.a'], producer, out / 'producer.log')
        result['producer'] = invocation
        if invocation['rc'] != 0:
            (out / 'result.json').write_text(json.dumps(result, indent=2))
            print('INFRA producer failed; no version assertion executed')
            return 2
        data = (producer / 'vercheck.cjo').read_bytes()
    (out / 'fixture.cjo').write_bytes(data)
    root = struct.unpack_from('<I', data)[0]
    vtable = root - struct.unpack_from('<i', data, root)[0]
    offset = struct.unpack_from('<H', data, vtable + 6)[0]
    if not offset:
        raise RuntimeError('product writer omitted version')
    version = list(data[root + offset:root + offset + 3])
    writer_ok = version == [0, 1, 0]
    result['writer'] = {'version': version, 'pass': writer_ok}
    print(f"{'PASS' if writer_ok else 'FAIL'} WriterVersion observed={version}", flush=True)
    variants = {'current': (0, 1, 0), 'older_minor': (0, 0, 0), 'patch': (0, 1, 255),
                'major': (1, 1, 0), 'newer_minor': (0, 2, 0), 'missing': None}
    tasks = []
    for name, triplet in variants.items():
        for entry in ('import', 'depinfo'):
            case = out / f'{entry}-{name}'
            case.mkdir(exist_ok=True)
            changed = bytearray(data)
            if triplet is None:
                struct.pack_into('<H', changed, vtable + 6, 0)
            else:
                changed[root + offset:root + offset + 3] = bytes(triplet)
            (case / 'vercheck.cjo').write_bytes(changed)
            tasks.append((entry, name, case))

    def check(task):
        entry, name, case = task
        cmd = ([compiler, fixtures / 'use.cj', '--output-type=staticlib', '-o', case / 'libuseversion.a', '--import-path', case]
               if entry == 'import' else [compiler, case / 'vercheck.cjo', '--scan-dependency'])
        invocation, output = run(cmd, case, case / 'compile.log')
        accepted = name in ('current', 'older_minor', 'patch')
        # Do not turn an arbitrary compiler failure into a successful rejection.
        mismatch = "is incompatible: compiled with cjc" in output
        passed = (invocation['rc'] == 0 and not mismatch) if accepted else (
            invocation['rc'] == 1 and mismatch and 'vercheck' in output)
        if accepted and entry == 'depinfo':
            passed = passed and 'vercheck' in output
        record = dict(invocation, name=f'{entry}-{name}', expected_accept=accepted,
                      diagnostic=mismatch, **{'pass': passed})
        print(f"{'PASS' if passed else 'FAIL'} {record['name']} rc={invocation['rc']} "
              f"expected_accept={accepted} mismatch={mismatch}", flush=True)
        return record

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(tasks)) as pool:
        result['cases'] = list(pool.map(check, tasks))
    result['fixture_sha256'] = hashlib.sha256(data).hexdigest()
    result['pass'] = writer_ok and all(c['pass'] for c in result['cases'])
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if result['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
