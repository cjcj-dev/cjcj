#!/usr/bin/env python3
"""Read accessor annotation results and factory definitions from product CHIR.

Uses CHIRFlatBufferSchema.cj slots for Function/GlobalValue/AnnoInfo. No model
of the translator is compiled or injected into the compiler.
"""
import argparse
import json
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'chir_builder'))
from decoded_compare import Package


def inspect(path):
    p = Package(path.read_bytes())
    tags = p.pointer(p.root, 14)
    result = []
    for i, table in enumerate(p.vector(p.root, 16)):
        if p.data[tags + 4 + i] != 11:  # ValueElem.Function
            continue
        glob = p.pointer(table, 4)
        value = p.pointer(glob, 4)
        info = p.pointer(glob, 16)
        instances = []
        for instance in p.vector(info, 6) if info else []:
            params = p.pointer(instance, 6)
            strings = []
            if params:
                for j in range(p.number('I', params)):
                    entry = params + 4 + 4 * j
                    text = entry + p.number('I', entry)
                    strings.append(p.data[text+4:text+4+p.number('I', text)].decode())
            instances.append({'class': p.string(instance, 4), 'params': strings})
        result.append({'id': p.string(value, 8), 'source': p.string(glob, 6),
                       'factory': p.string(info, 4) if info else '',
                       'instances': instances})
    return result


def verify(path, literal):
    functions = inspect(path)
    accessors = [f for f in functions if f['factory'] not in ('', 'none')]
    checks = {}
    # Keep presence separate; report every predicate even when one fails.
    checks['accessors_present'] = len(accessors) == 2
    names = [f['factory'] for f in accessors]
    checks['accessors_share_name'] = len(names) == 2 and names[0] == names[1]
    factories = [f for f in functions if f['source'] in names]
    checks['accessors_share_one_factory'] = len(factories) == 1
    checks['literal_instances' if literal else 'nonliteral_instances_empty'] = (
        len(accessors) == 2 and all(
            len(f['instances']) == 1 and f['instances'][0]['params'] == ['3']
            if literal else f['instances'] == [] for f in accessors))
    return {'path': str(path), 'accessors': accessors, 'factories': factories, 'checks': checks}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('chir', type=Path)
    parser.add_argument('--literal', action='store_true')
    args = parser.parse_args()
    result = verify(args.chir, args.literal)
    print(json.dumps(result, indent=2))
    for name, passed in result['checks'].items():
        print(('PASS ' if passed else 'FAIL ') + name)
    sys.exit(0 if all(result['checks'].values()) else 1)
