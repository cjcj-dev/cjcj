#!/usr/bin/env python3
"""Assert registration in IR emitted by the real compiler frontend."""
import argparse
import json
from pathlib import Path
import re


def functions(text):
    return {match.group(1).strip('"'): match.group(0) for match in re.finditer(
        r'^define [^\n]*@("[^"]+"|[^\s(]+)\([^\n]*\{\n.*?^}', text, re.M | re.S)}


def reaches_bridge(name, bodies, visited=None):
    visited = set() if visited is None else visited
    if name in visited or name not in bodies:
        return False
    visited.add(name)
    body = bodies[name]
    return ('@CJ_MCC_OnFinalizerCreated(' in body or any(
        reaches_bridge(callee.strip('"'), bodies, visited)
        for callee in re.findall(r'\b(?:call|invoke) [^\n]*?@("[^"]+"|[^\s(]+)\(', body)))


def check_case(case):
    directory = Path(case['directory'])
    paths = sorted(directory.rglob('*.ll'))
    label = directory.parent.name + '/' + case['optimization']
    if case['rc'] != 0 or not paths:
        return {'case': label, 'status': 'NOT_RUN', 'compiler_rc': case['rc']}
    texts = [path.read_text() for path in paths]
    bodies = {}
    for text in texts:
        bodies.update(functions(text))
    root = bodies.get('_CNat6Object6<init>Hv', '')
    checks = {
        'root_dynamic_registration': root.count('@CJ_MCC_OnFinalizerCreated(') == 1
        and 'finalizer.required' in root and bool(re.search(r'and i8 [^\n]+, 2\b', root))
        and bool(re.search(r'load %TypeInfo\*', root)),
        'finalizable_allocation_keeps_type_attribute': any(
            '"HasFinalizer"' in text for text in texts),
    }
    bridge_attributes = []
    for text in texts:
        for declaration in re.finditer(
                r'^declare [^\n]*@CJ_MCC_OnFinalizerCreated\([^\n]+', text, re.M):
            group = re.search(r'#(\d+)', declaration.group())
            attributes = ''
            if group:
                definition = re.search(r'^attributes #' + group.group(1) + r' = \{([^\n]+)', text, re.M)
                attributes = definition.group(1) if definition else ''
            bridge_attributes.append(declaration.group() + attributes)
    checks['bridge_managed_nonleaf'] = bool(bridge_attributes) and all(
        'i8 addrspace(1)* @CJ_MCC_OnFinalizerCreated(i8 addrspace(1)*)' in declaration
        and '"cj-runtime"' in declaration
        and not any(forbidden in declaration for forbidden in (
            'gc-leaf-function', 'readnone', 'readonly', 'argmemonly', 'nounwind', 'nocapture', 'noalias'))
        for declaration in bridge_attributes)
    finalized = bodies.get('_CNat25registrationMakeFinalizedHv', '')
    allocations = [line for line in finalized.splitlines() if '@llvm.cj.malloc.object(' in line]
    checks['allocation_has_no_registration_tag'] = bool(allocations) and all(
        '!MallocType' not in line for line in allocations)
    checks['constructed_object_reaches_registration'] = reaches_bridge(
        '_CNat25registrationMakeFinalizedHv', bodies)
    if case['optimization'] == 'O2':
        plain = bodies.get('_CNat21registrationMakePlainHv', '')
        checks['inlined_finalized_keeps_one_event'] = finalized.count('@CJ_MCC_OnFinalizerCreated(') == 1
        checks['plain_allocation_has_no_registration_cost'] = (
            bool(plain) and '@llvm.cj.malloc.object(' in plain
            and 'CJ_MCC_OnFinalizerCreated' not in plain and 'finalizer.flags' not in plain
            and '<init>' not in plain)
    caught = bodies.get('_CNat18registrationCaughtHv', '')
    checks['constructor_exception_edge_retained'] = (
        bool(caught) and bool(re.search(r'invoke [^\n]*RegistrationFinalized[^\n]*<init>', caught))
        and 'unwind label' in caught and reaches_bridge('_CNat18registrationCaughtHv', bodies))
    for assertion, passed in checks.items():
        print(f'TARGET {label} {assertion}={"PASS" if passed else "FAIL"}', flush=True)
    return {'case': label, 'status': 'PASS' if all(checks.values()) else 'FAIL', 'checks': checks}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('result', type=Path)
    args = parser.parse_args()
    results = [check_case(case) for case in json.loads(args.result.read_text())['cases']]
    args.result.with_name('assertions.json').write_text(json.dumps(results, indent=2) + '\n')
    if not results or any(row['status'] == 'NOT_RUN' for row in results):
        return 2
    return 0 if all(row['status'] == 'PASS' for row in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
