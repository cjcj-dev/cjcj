#!/usr/bin/env python3
"""Compile real fixtures, then inspect the product CHIR serializer's cast tags."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time


class SerializedPackage:
    # CHIRFlatBufferSchema.cj: expression kind slot 6, package union vectors 18/20.
    def __init__(self, data):
        self.data = data

    def number(self, fmt, offset):
        return struct.unpack_from('<' + fmt, self.data, offset)[0]

    def field(self, table, slot):
        vtable = table - self.number('i', table)
        if slot >= self.number('H', vtable):
            return 0
        relative = self.number('H', vtable + slot)
        return table + relative if relative else 0

    def pointer(self, table, slot):
        offset = self.field(table, slot)
        return offset + self.number('I', offset) if offset else 0

    def cast_tags(self):
        root = self.number('I', 0)
        kinds, expressions = self.pointer(root, 18), self.pointer(root, 20)
        assert kinds and expressions, 'serializer produced no expression vectors'
        count = self.number('I', expressions)
        assert self.number('I', kinds) == count
        tags = []
        for index in range(count):
            union = self.number('B', kinds + 4 + index)
            if union not in (1, 18):
                continue
            offset = expressions + 4 + index * 4
            table = offset + self.number('I', offset)
            base = table if union == 1 else self.pointer(table, 4)
            kind_field = self.field(base, 6)
            kind = self.number('B', kind_field) if kind_field else 0
            if kind in (44, 48):
                tags.append({'index': index, 'union': union, 'kind': kind})
        return tags


def run_case(compiler, fixture, output, jobs):
    output.mkdir(parents=True, exist_ok=True)
    command = [str(compiler), str(fixture), '--emit-chir=raw', '--output-type=staticlib',
               '--dump-chir', '--jobs', str(jobs), '-o', str(output / 'output.chir')]
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    with (output / 'compile.log').open('w') as log:
        run = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=600)
    result = {'command': command, 'rc': run.returncode, 'wall': time.monotonic() - start,
              'uptime_before': before, 'uptime_after': subprocess.check_output(['uptime'], text=True).strip(),
              'assertion_executed': False, 'pass': False}
    if run.returncode:
        return result
    serialized = [p for p in output.glob('*.chir') if p.read_bytes()[:4] != b'ToCH']
    assert len(serialized) == 1, serialized
    data = serialized[0].read_bytes()
    tags = SerializedPackage(data).cast_tags()
    expected = {'class_cast': (1, 44), 'numeric_cast': (18, 48), 'control': None}[fixture.stem]
    actual = [(tag['union'], tag['kind']) for tag in tags]
    result.update(artifact=str(serialized[0]), sha256=hashlib.sha256(data).hexdigest(), tags=tags,
                  assertion_executed=True, expected=expected,
                  **{'pass': (bool(actual) and all(tag == expected for tag in actual))
                     if expected else not actual})
    print(f"ASSERT_SERIALIZED_CAST_TAG {fixture.stem} expected={expected} observed={actual} pass={result['pass']}", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=os.cpu_count())
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    fixtures = [Path(__file__).with_name(name + '.cj') for name in ('class_cast', 'numeric_cast', 'control')]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futures = {p.stem: pool.submit(run_case, args.compiler, p, args.out / p.stem, args.jobs) for p in fixtures}
        cases = {name: future.result() for name, future in futures.items()}
    result = {'compiler': str(args.compiler), 'compiler_sha256': hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
              'affinity': sorted(os.sched_getaffinity(0)), 'cases': cases}
    (args.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if all(case['pass'] for case in cases.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
