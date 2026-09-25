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

    def scalar(self, table, slot):
        offset = self.field(table, slot)
        return self.number('I', offset) if offset else 0

    def string(self, table, slot):
        offset = self.pointer(table, slot)
        return self.data[offset + 4:offset + 4 + self.number('I', offset)].decode() if offset else ''

    def cast_tags(self, package_name, function_name, include_box=False):
        root = self.number('I', 0)
        kinds, expressions = self.pointer(root, 18), self.pointer(root, 20)
        assert kinds and expressions, 'serializer produced no expression vectors'
        count = self.number('I', expressions)
        assert self.number('I', kinds) == count
        values = self.pointer(root, 16)

        def value(index):
            assert index > 0
            offset = values + 4 + (index - 1) * 4
            return offset + self.number('I', offset)

        tags = []
        owned_expressions = 0
        for index in range(count):
            union = self.number('B', kinds + 4 + index)
            # Every expression union has Expression as its first base; the
            # only two cast families of interest are plain Expression and NumericCastBase.
            if union not in (1, 18):
                continue
            offset = expressions + 4 + index * 4
            table = offset + self.number('I', offset)
            base = table if union == 1 else self.pointer(table, 4)
            owner = self.scalar(base, 12)
            if not owner:
                continue
            group = value(self.scalar(value(owner), 6))
            function_id = self.scalar(group, 10)
            if not function_id:
                continue
            global_value = self.pointer(value(function_id), 4)
            if (self.string(global_value, 10), self.string(global_value, 6)) != (package_name, function_name):
                continue
            owned_expressions += 1
            kind_field = self.field(base, 6)
            kind = self.number('B', kind_field) if kind_field else 0
            if kind in (44, 48) or (include_box and kind == 45):
                tags.append({'index': index, 'union': union, 'kind': kind})
        return tags, owned_expressions


def run_case(compiler, fixture, output, jobs):
    output.mkdir(parents=True, exist_ok=True)
    phase = 'opt' if fixture.stem == 'closure_cast' else 'raw'
    command = [str(compiler), str(fixture), '--emit-chir=' + phase, '--output-type=staticlib',
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
    target_function = {'class_cast': 'upcast', 'numeric_cast': 'widen', 'control': 'identity', 'closure_cast': 'sortValues'}[fixture.stem]
    tags, owned_expressions = SerializedPackage(data).cast_tags('expression_' + fixture.stem, target_function, include_box=fixture.stem == 'closure_cast')
    assert owned_expressions > 0, f'no product expressions observed in {target_function}'
    expected = {'class_cast': (1, 44), 'numeric_cast': (18, 48), 'control': None, 'closure_cast': (1, 44)}[fixture.stem]
    actual = [(tag['union'], tag['kind']) for tag in tags]
    result.update(artifact=str(serialized[0]), sha256=hashlib.sha256(data).hexdigest(), tags=tags,
                  assertion_executed=True, expected=expected, owned_expressions=owned_expressions,
                  **{'pass': (bool(actual) and all(tag == expected for tag in actual))
                     if expected else not actual})
    print(f"ASSERT_SERIALIZED_CAST_TAG {fixture.stem} expected={expected} observed={actual} pass={result['pass']}", flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=os.cpu_count())
    parser.add_argument('--closure-only', action='store_true', help='check generic closure conversion after optimization')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    names = ('closure_cast',) if args.closure_only else ('class_cast', 'numeric_cast', 'control')
    fixtures = [Path(__file__).with_name(name + '.cj') for name in names]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futures = {p.stem: pool.submit(run_case, args.compiler, p, args.out / p.stem, args.jobs) for p in fixtures}
        cases = {name: future.result() for name, future in futures.items()}
    result = {'compiler': str(args.compiler), 'compiler_sha256': hashlib.sha256(args.compiler.read_bytes()).hexdigest(),
              'affinity': sorted(os.sched_getaffinity(0)), 'cases': cases}
    (args.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if all(case['pass'] for case in cases.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
