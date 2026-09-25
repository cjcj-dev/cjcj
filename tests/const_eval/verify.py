#!/usr/bin/env python3
"""Check byte preservation and exact product-cut failures collected by run.py."""
import argparse
import json
from pathlib import Path
import re


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def rewritten_constants(case, name, count):
    """Read the final product CHIR, not a separately reconstructed interpreter."""
    path = Path(case['log']).parent / 'output_CHIR/3_EraseUselessDebugExpr.chirtxt'
    text = path.read_text()
    marker = f'srcCodeIdentifier: gv$_{name},'
    if marker not in text:
        return False
    body = text.split(marker, 1)[1].split('\n}\n', 1)[0]
    constants = re.findall(r'^  %\d+: .* = Constant\(\) // (.*)$', body, re.M)
    if name == 'pair':
        return constants == ['41i', '41i']
    return len(constants) == count


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('result', type=Path)
    p.add_argument('--target-arm', help='run only the emitted-CHIR target assertions')
    args = p.parse_args()
    data = json.loads(args.result.read_text())
    cases = {(c['arm'], c['name']): c for c in data['cases']}
    if args.target_arm:
        passed = True
        for name, global_name, count in [('core-tuple', 'pair', 2), ('core-nested', 'values', 4)]:
            case = cases[args.target_arm, name]
            ok = case['rc'] == 0 and rewritten_constants(case, global_name, count)
            print(f'TARGET_CHIR {args.target_arm}/{name} rewritten_constants={ok}', flush=True)
            passed = passed and ok
        raise SystemExit(0 if passed else 1)
    names = {c['name'] for c in data['cases'] if c['arm'] == 'baseline'}
    require(bool(names), 'baseline must actually run')
    expected_arms = {'baseline', 'candidate', 'checked', 'restored',
                     'cut-consumer', 'cut-producer', 'cut-result'}
    require(set(data['compilers']) == expected_arms, 'missing compiler arm')
    for arm in expected_arms:
        require({n for a, n in cases if a == arm} == names, f'{arm}: unequal input sets')
    for name in names:
        base = cases['baseline', name]
        require(base['rc'] == 0 and base['outputs'], f'{name}: baseline did not complete')
        for arm in ('candidate', 'checked', 'restored'):
            case = cases[arm, name]
            require(case['rc'] == 0 and case['outputs'], f'{arm}/{name}: did not complete')
            require(case['outputs'] == base['outputs'], f'{arm}/{name}: CHIR changed')
    hashes = {a: c['sha256'] for a, c in data['compilers'].items()}
    require(hashes['checked'] == hashes['restored'], 'green/restored compiler identity differs')
    for arm in ('cut-consumer', 'cut-producer'):
        require(hashes[arm] != hashes['checked'], f'{arm}: product was not changed')
    for name in ('core-tuple', 'core-nested'):
        for arm in ('checked', 'restored'):
            checks = cases[arm, name]['assertions']
            require('CONSTEVAL created members=0 expected=0' in checks, f'{arm}/{name}: producer not observed')
            require('CONSTEVAL inserted members=1 expected=1' in checks, f'{arm}/{name}: consumer not observed')
    require('CONSTEVAL literal-inserted members=1 expected=1' in
            cases['checked', 'core-scalar']['assertions'], 'scalar caller append not observed')
    expected_failures = {'cut-consumer': {'core-tuple', 'core-nested'},
                         'cut-producer': {'core-tuple', 'core-nested', 'core-scalar'}}
    for arm, failures in expected_failures.items():
        actual = {n for n in names if cases[arm, n]['rc'] != 0}
        require(actual == failures, f'{arm}: unexpected failure set {actual}')
        for name in failures:
            case = cases[arm, name]
            checks = case['assertions']
            target = ('inserted' if arm == 'cut-consumer' else
                      'literal-created' if name == 'core-scalar' else 'created')
            expected = 1 if arm == 'cut-consumer' else 0
            observed = 0 if arm == 'cut-consumer' else 1
            require(f'CONSTEVAL {target} members={observed} expected={expected}' in checks,
                    f'{arm}/{name}: did not reach target assertion')
            require(f'CONSTEVAL {target}: block membership mismatch' in Path(case['log']).read_text(),
                    f'{arm}/{name}: failure came from another assertion')
    for name, global_name, count in [('core-tuple', 'pair', 2), ('core-nested', 'values', 4)]:
        for arm in ('baseline', 'candidate', 'restored'):
            require(rewritten_constants(cases[arm, name], global_name, count),
                    f'{arm}/{name}: returned constants not in product CHIR')
        case = cases['cut-result', name]
        require(case['rc'] == 0, f'cut-result/{name}: compiler did not complete')
        require(not rewritten_constants(case, global_name, count),
                f'cut-result/{name}: disconnected return did not falsify target assertion')
    for name in names - {'core-tuple', 'core-nested'}:
        case = cases['cut-result', name]
        require(case['rc'] == 0 and case['outputs'] == cases['candidate', name]['outputs'],
                f'cut-result/{name}: unrelated regression')
    result = {'inputs_per_arm': len(names), 'arms': len(expected_arms),
              'cut_failure_sets': {a: sorted(n) for a, n in expected_failures.items()},
              'cut_result_falsified_targets': ['core-tuple', 'core-nested'],
              'baseline_candidate_same_bytes': sorted(names)}
    args.result.with_name('verified.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
