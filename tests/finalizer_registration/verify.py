#!/usr/bin/env python3
"""Assert root-return effects in actual compiler-produced CHIR."""
import argparse
import json
from pathlib import Path
import re


def functions(text):
    result = {}
    for match in re.finditer(r'(?m)^[^\n]*\bFunc (@[^\s(]+)\(', text):
        end = text.find('\n}\n', match.end())
        if end >= 0:
            result[match.group(1)] = text[match.start():end + 3]
    return result


def calls(body):
    return re.findall(r'Apply\([^\n]*?(@[^\s,)]+)', body)


def reaches_registration(name, bodies, visited=None):
    visited = set() if visited is None else visited
    if name in visited or name not in bodies:
        return False
    visited.add(name)
    body = bodies[name]
    return ('Intrinsic(registerFinalizer,' in body or
            any(reaches_registration(callee, bodies, visited) for callee in calls(body)))


def initializer(bodies, name):
    return next(((symbol, body) for symbol, body in bodies.items()
                 if 'srcCodeIdentifier: gv$_' + name + ',' in body), ('', ''))


def check_case(case):
    name = Path(case['source']).stem
    phase = case['phase']
    directory = Path(case['log']).parent / 'output_CHIR'
    matches = sorted(directory.glob('*AST_CHIR.chirtxt' if phase == 'raw'
                                    else '*EraseUselessDebugExpr.chirtxt'))
    label = name + '/' + phase + '/' + case['optimization']
    if case['rc'] != 0 or len(matches) != 1:
        return {'case': label, 'status': 'NOT_RUN', 'compiler_rc': case['rc'],
                'reason': 'compiler must finish and produce the selected CHIR phase'}
    text = matches[0].read_text()
    bodies = functions(text)
    checks = {}
    if name != 'control':
        root = next((body for body in bodies.values()
                     if 'declaredParent: @_CNat6ObjectE, kind: classConstructor' in body), '')
        lines = [line.strip() for line in root.splitlines() if line.strip()]
        exits = [index for index, line in enumerate(lines) if line.startswith('Exit(')]
        checks['root_event_before_normal_exit'] = bool(exits) and all(
            index > 0 and 'Intrinsic(registerFinalizer,' in lines[index - 1] for index in exits)
        constructors = [(symbol, body) for symbol, body in bodies.items()
                        if 'kind: classConstructor' in body and body != root]
        if phase == 'raw':
            checks['one_constructor_edge_per_derived_body'] = bool(constructors) and all(
                len([callee for callee in calls(body) if '<init>' in callee]) == 1
                for _, body in constructors)
        checks['derived_constructor_reaches_root_event'] = bool(constructors) and all(
            reaches_registration(symbol, bodies) for symbol, _ in constructors)
    if phase == 'opt' and name in ('const_finalized', 'const_nested', 'const_temporary'):
        global_name = {'const_finalized': 'instance', 'const_nested': 'nested',
                       'const_temporary': 'answer'}[name]
        symbol, body = initializer(bodies, global_name)
        checks['const_batch_retains_runtime_event'] = bool(body) and reaches_registration(symbol, bodies)
        if name != 'const_temporary':
            _, shared = initializer(bodies, 'shared')
            checks['shared_global_keeps_identity'] = (
                bool(shared) and 'Allocate(Class-' not in shared and
                bool(re.search(r'Load\(@[^\n]*' + global_name, shared)))
    if phase == 'opt' and name == 'const_plain':
        _, body = initializer(bodies, 'instance')
        checks['plain_const_still_materializes'] = (
            'Allocate(Class-' in body and not calls(body) and 'registerFinalizer' not in body)
    if phase == 'opt' and name == 'control':
        checks['scalar_const_still_folds'] = any(
            '= 41i //' in line and 'srcCodeIdentifier: answer,' in line for line in text.splitlines())
    for assertion, passed in checks.items():
        print(f'TARGET {label} {assertion}={"PASS" if passed else "FAIL"}', flush=True)
    return {'case': label, 'status': 'PASS' if all(checks.values()) else 'FAIL',
            'compiler_rc': case['rc'], 'artifact': str(matches[0]), 'checks': checks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('result', type=Path)
    args = parser.parse_args()
    source = json.loads(args.result.read_text())
    results = [check_case(case) for case in source['cases'] if case['phase'] in ('raw', 'opt')]
    target = args.result.with_name('assertions.json')
    target.write_text(json.dumps(results, indent=2) + '\n')
    if not results or any(row['status'] == 'NOT_RUN' for row in results):
        return 2
    return 0 if all(row['status'] == 'PASS' for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
