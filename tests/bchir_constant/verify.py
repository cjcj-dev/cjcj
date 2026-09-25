#!/usr/bin/env python3
"""Check product-emitted final CHIR, independently of compiler exit status.

Print every target observation, including failure. A missing dump or unsuccessful
compiler invocation is reported separately and is not counted as a valid cut.
"""
import argparse
import json
from pathlib import Path
import re


def check(path, name):
    text = path.read_text()
    functions = re.split(r'(?=^.*\bFunc @)', text, flags=re.M)
    body = next((f for f in functions if 'srcCodeIdentifier: gv$_pair,' in f), '')
    definitions = dict(re.findall(r'^\s*(%\w+):.*? = (.*)$', body, re.M))
    tuples = re.findall(r'= Tuple\(([^\n]*)\)', body)
    args = tuples[-1].split(', ') if tuples else []
    expressions = [definitions.get(arg, '') for arg in args]
    # Source literal text is present either as the operand (upstream layout) or
    # in the old diagnostic comment. Check value and producer, never line count.
    expected = {'literals': ['41', 'true'], 'load_control': ['41', '41'],
                'scalars': ['-17', '2.5', "'x'", '29'], 'enum': ['1', '1']}[name]
    values = []
    for expr in expressions:
        if name == 'enum' and expr.startswith('TypeCast('):
            ref = re.search(r'TypeCast\((%\w+)', expr)
            expr = definitions.get(ref[1], '') if ref else ''
        match = re.search(r'Constant\(([^)]*)\)(?:\s*//\s*(.*))?', expr)
        value = (match[1] or match[2] or '').strip() if match else None
        if value is not None and re.fullmatch(r'-?[0-9]+(?:\.[0-9]+)?[iuf]', value):
            value = value[:-1]
        values.append(value)
    ok = len(values) == len(expected) and all(
        v is not None and (v == e or (name == 'scalars' and e == '2.5' and float(v) == 2.5))
        for v, e in zip(values, expected))
    if name == 'enum':
        ok = ok and 'Load(@_CNat6chosenE)' not in body
    print('TARGET_LITERAL', json.dumps(dict(name=name, values=values, expected=expected,
                                            passed=ok, path=str(path))))
    return ok


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('root', type=Path)
    args = p.parse_args()
    results = []
    for name in ['enum', 'literals', 'scalars', 'load_control']:
        directory = args.root / ('core-' + name)
        record = json.loads((directory / 'result.json').read_text())
        dump = directory / 'output_CHIR/3_EraseUselessDebugExpr.chirtxt'
        if record['rc'] != 0 or not dump.exists():
            print('ENTRY_FAILURE', name, 'compiler_rc=', record['rc'], 'dump=', dump.exists())
            results.append(False)
        else:
            results.append(check(dump, name))
    raise SystemExit(0 if all(results) else 1)


if __name__ == '__main__':
    main()
