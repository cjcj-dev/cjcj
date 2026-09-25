#!/usr/bin/env python3
"""Assert source ranges in real stage1 binary CHIR, without product probes.

Schema anchors: CHIRFlatBufferSchema.cj:730,788,999,1040,1138;
CHIRSerializerImpl.cj:609,966,1138. The shared reader only decodes bytes.
"""
import argparse
import json
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'chir_builder'))
from decoded_compare import Package


def intrinsics(path):
    p = Package(path.read_bytes())
    tags = p.pointer(p.root, 18)
    found = []
    for i, obj in enumerate(p.vector(p.root, 20)):
        if p.data[tags + 4 + i] != 14:
            continue
        kind = p.scalar(obj, 6, 'H')
        if kind not in (59, 60):
            continue
        expr = p.pointer(p.pointer(obj, 4), 4)  # Intrinsic -> FuncCall -> Expression
        loc = p.pointer(p.pointer(expr, 4), 8)  # Expression -> Base -> DebugLocation
        def pos(slot):
            point = p.pointer(loc, slot)
            return [p.scalar(point, 4), p.scalar(point, 6)]
        found.append({'kind': 'get' if kind == 60 else 'set',
                      'file': p.string(loc, 4), 'file_id': p.scalar(loc, 6),
                      'begin': pos(8), 'end': pos(10),
                      'owner': p.scalar(expr, 12)})
    return found


def check(chir, source):
    values = intrinsics(chir)
    compound, ordinary = [], []
    for line, text in enumerate(source.read_text().splitlines(), 1):
        m = re.fullmatch(r'(\s*)(values\[index\] (\S+=) .+)', text)
        if m:
            compound.append({'begin': [line, len(m[1]) + 1], 'end': [line, len(text) + 1]})
        elif re.fullmatch(r'\s*values\[index\] = .+', text):
            ordinary.append({'begin': [line, len(text) - len(text.lstrip()) + 1],
                             'end': [line, len(text) + 1]})
    gets = [v for v in values if v['kind'] == 'get']
    sets = [v for v in values if v['kind'] == 'set']
    def ranges(items):
        return sorted((v['begin'], v['end']) for v in items)
    # Existence is a separate assertion; target evaluation is never short-circuited.
    checks = {
        'intrinsic_counts': len(gets) == len(compound) == 13 and len(sets) == 14,
        'compound_get_assignment_location': ranges(gets) == ranges(compound)
            and all(Path(v['file']) == source.resolve() and v['file_id'] > 0 for v in gets),
        'varray_set_assignment_location': ranges(sets) == ranges(compound + ordinary)
            and all(Path(v['file']) == source.resolve() and v['file_id'] > 0 for v in sets),
    }
    return {'checks': checks, 'observed': values, 'expected_compound': compound,
            'expected_ordinary': ordinary, 'chir': str(chir), 'source': str(source)}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('chir', type=Path)
    p.add_argument('source', type=Path)
    p.add_argument('--json', type=Path)
    a = p.parse_args()
    result = check(a.chir, a.source)
    for name, passed in result['checks'].items():
        print(f"{'PASS' if passed else 'FAIL'} {name}")
    print('OBSERVED ' + json.dumps(result['observed'], sort_keys=True))
    if a.json:
        a.json.write_text(json.dumps(result, indent=2) + '\n')
    return 0 if all(result['checks'].values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
