#!/usr/bin/env python3
"""Check real DWARF RawArray members (upstream DIBuilder.cpp:804-836)."""
import argparse
import json
from pathlib import Path
import re


def arrays(text):
    roots, stack, current = [], {}, None
    for line in text.splitlines():
        match = re.match(r'\s*<(\d+)><([0-9a-f]+)>:.*?(DW_TAG_\w+)', line)
        if match:
            depth, offset, tag = match.groups()
            depth = int(depth)
            current = {'offset': offset, 'tag': tag, 'attrs': {}, 'children': []}
            if depth - 1 in stack:
                stack[depth - 1]['children'].append(current)
            else:
                roots.append(current)
            stack = {d: value for d, value in stack.items() if d < depth}
            stack[depth] = current
            continue
        if re.match(r'\s*<\d+><[0-9a-f]+>:', line):
            current = None
        match = re.search(r'DW_AT_(\w+)\s*:\s*(.*)', line)
        if current is not None and match:
            key, value = match.groups()
            current['attrs'][key] = re.sub(r'^\([^)]*\):\s*', '', value)
    result = []
    def visit(node):
        name = node['attrs'].get('name', '')
        if node['tag'] == 'DW_TAG_structure_type' and name.startswith('RawArray<'):
            result.append({'name': name, 'die': node['offset'],
                           'byte_size': node['attrs'].get('byte_size'),
                           'members': {c['attrs'].get('name'): c['attrs'].get('data_member_location')
                                       for c in node['children'] if c['tag'] == 'DW_TAG_member'}})
        for child in node['children']:
            visit(child)
    for root in roots:
        visit(root)
    return result


def check(text):
    observed = arrays(text)
    generic = [a for a in observed if a['name'] == 'RawArray<$G_T>']
    concrete = [a for a in observed if a['name'] in ('RawArray<Int64>', 'RawArray<UInt64>', 'RawArray<UInt8>')]
    # Evaluate every assertion: a presence failure must not hide the target shape assertion.
    checks = {
        'generic_rawarray_present': bool(generic),
        'unsized_rawarray_ti_only': all(a['members'] == {'$ti': '0'} for a in generic),
        'concrete_rawarray_present': bool(concrete),
        # {ArrayBase={i64}, [0 x scalar]} behind the 8-byte object header.
        'sized_rawarray_members_match_layout': all(
            a['members'] == {'$ti': '0', 'size': '8', 'elements': '16'} for a in concrete),
    }
    return {'checks': checks, 'observed': observed}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('debug', type=Path)
    parser.add_argument('--json', type=Path)
    args = parser.parse_args()
    result = check(args.debug.read_text())
    for name, passed in result['checks'].items():
        print(f"{'PASS' if passed else 'FAIL'} {name}")
    print('OBSERVED ' + json.dumps(result['observed'], sort_keys=True))
    if args.json:
        args.json.write_text(json.dumps(result, indent=2) + '\n')
    return 0 if all(result['checks'].values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
