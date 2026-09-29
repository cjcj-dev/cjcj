#!/usr/bin/env python3
"""Read initialization dependencies from a real compiler's CJMP common CJO.

Schema: ModuleFormatSchema.cj Package.allDecls=20, Decl.dependencies=40,
FullId={pkgId=4, decl=6, index=8}. Compare FullId values, never table offsets.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import time


class Cjo:
    def __init__(self, data):
        self.data = data

    def number(self, fmt, at):
        return struct.unpack_from('<' + fmt, self.data, at)[0]

    def field(self, table, slot):
        vt = table - self.number('i', table)
        offset = self.number('H', vt + slot) if slot < self.number('H', vt) else 0
        return table + offset if offset else None

    def pointer(self, at):
        return at + self.number('I', at) if at is not None else None

    def string(self, at):
        pos = self.pointer(at)
        return self.data[pos + 4:pos + 4 + self.number('I', pos)].decode() if pos else ''

    def vector(self, table, slot):
        pos = self.pointer(self.field(table, slot))
        return [self.pointer(pos + 4 + 4 * i) for i in range(self.number('I', pos))] if pos else []

    def full_id(self, table):
        pkg, index = self.field(table, 4), self.field(table, 8)
        return (self.number('i', pkg) if pkg else 0,
                self.string(self.field(table, 6)), self.number('I', index) if index else 0)

    def declarations(self):
        rows = []
        for table in self.vector(self.number('I', 0), 20):
            deps = [self.full_id(dep) for dep in self.vector(table, 40)]
            rows.append({'name': self.string(self.field(table, 18)), 'dependencies': deps,
                         'duplicates': len(deps) - len(set(deps))})
        return rows


def fixture():
    # Shared global leaf reached through many local constants. The reader sees
    # the serialized result, without constructing ASTs or calling writer helpers.
    lines = ['package depcheck', 'public const leaf: Int64 = 1',
             'public func diamond(): Int64 {']
    for i in range(64):
        lines += [f'    const left{i}: Int64 = leaf + {i}',
                  f'    const right{i}: Int64 = leaf + {i + 1}',
                  f'    const joined{i}: Int64 = left{i} + right{i}']
    lines += ['    return ' + ' + '.join(f'joined{i}' for i in range(64)), '}',
              'public func direct(): Int64 { return leaf }']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    compiler, out = args.compiler.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    source = out / 'depcheck.cj'
    source.write_text(fixture())
    command = [str(compiler), str(source), '--experimental', '--output-type=chir',
               '-o', str(out / 'depcheck.chir')]
    start = time.monotonic()
    with (out / 'compile.log').open('wb') as log:
        run = subprocess.run(command, cwd=out, stdout=log, stderr=subprocess.STDOUT, timeout=900)
    result = {'command': command, 'compile_rc': run.returncode, 'wall': time.monotonic() - start,
              'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'fixture_sha256': hashlib.sha256(source.read_bytes()).hexdigest()}
    status = 2
    if run.returncode == 0:
        data = (out / 'depcheck.cjo').read_bytes()
        result['cjo_sha256'] = hashlib.sha256(data).hexdigest()
        rows = Cjo(data).declarations()
        result['declarations'] = rows
        duplicates = sum(row['duplicates'] for row in rows)
        # Always evaluate uniqueness, even when the independent coverage check fails.
        print(f"ASSERT DependenciesUnique {'PASS' if duplicates == 0 else 'FAIL'} duplicates={duplicates}", flush=True)
        observed = {row['name']: row['dependencies'] for row in rows}
        covered = all(observed.get(name) for name in ('diamond', 'direct'))
        print(f"ASSERT DependenciesObserved {'PASS' if covered else 'FAIL'}", flush=True)
        result.update(duplicates=duplicates, covered=covered)
        status = 0 if covered and duplicates == 0 else 1
    else:
        print('NOT_RUN: compiler failed before dependency assertions', flush=True)
    result['rc'] = status
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return status


if __name__ == '__main__':
    raise SystemExit(main())
