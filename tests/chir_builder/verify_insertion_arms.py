#!/usr/bin/env python3
"""Verify compiler-produced #200 evidence; does not synthesize CHIR input.

The runner must retain each compiler and record its SHA256 at build/run time.
See instrument_head_insertion.py for the temporary diagnostic source patch.
"""
import argparse
import difflib
import hashlib
import json
import re
from pathlib import Path

SITES = ('lambda-debug', 'env-allocate', 'wrapper-allocate',
         'constructor-store', 'constructor-false')


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def load(root, arm):
    result = json.loads((root / f'fixtures-{arm}-opt/result.json').read_text())
    require(hashlib.sha256(Path(result['elf']).read_bytes()).hexdigest() == result['sha256'],
            f'compiler artifact changed since execution: {arm}')
    result['by_input'] = {Path(case['input']).name: case for case in result['cases']}
    return result


def same_inputs(left, right):
    require(left['by_input'].keys() == right['by_input'].keys(), 'fixture sets differ')
    for name, case in left['by_input'].items():
        require(case['input_sha256'] == right['by_input'][name]['input_sha256'],
                f'fixture source differs: {name}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('evidence', type=Path)
    parser.add_argument('--json', type=Path, required=True)
    args = parser.parse_args()
    green = load(args.evidence, 'checked')
    restored = load(args.evidence, 'restored')
    same_inputs(green, restored)
    require(green['sha256'] == restored['sha256'], 'diagnostic green/restored ELF differ')
    for name, case in green['by_input'].items():
        other = restored['by_input'][name]
        require(case['rc'] == other['rc'] == 0, f'green/restored compile failed: {name}')
        require(bool(case['outputs']) and case['outputs'] == other['outputs'],
                f'green/restored CHIR differs: {name}')
    report = {'diagnostic_sha256': green['sha256'], 'sites': {}}
    for site in SITES:
        cut = load(args.evidence, 'cut-' + site)
        same_inputs(green, cut)
        require(cut['sha256'] != green['sha256'], f'knife ELF unchanged: {site}')
        expected = {name for name, case in green['by_input'].items()
                    if f'HEAD_INSERT {site} member=false' in case['assertions']}
        require(bool(expected), f'product branch never reached: {site}')
        failed = {name for name, case in cut['by_input'].items() if case['rc'] != 0}
        require(failed == expected, f'imprecise failing set: {site}: {failed} vs {expected}')
        for name, case in cut['by_input'].items():
            if name in expected:
                require(f'HEAD_INSERT {site} member=true' in case['assertions'],
                        f'target membership assertion not reached: {site}/{name}')
                require(all(f'HEAD_INSERT {site} ' in line for line in case['assertions']
                            if 'member=true' in line), f'other branch failed: {site}/{name}')
            else:
                require(case['outputs'] == green['by_input'][name]['outputs'],
                        f'unrelated CHIR changed: {site}/{name}')
        report['sites'][site] = {'failed': sorted(failed), 'n': len(cut['cases']),
                                 'cut_sha256': cut['sha256']}

    formal = load(args.evidence, 'finaltrim')
    formal_restore = load(args.evidence, 'restoretrim')
    consumer = load(args.evidence, 'consumertrim')
    same_inputs(formal, formal_restore)
    same_inputs(formal, consumer)
    require(formal['sha256'] == formal_restore['sha256'], 'formal restored ELF differs')
    require(formal['sha256'] != consumer['sha256'], 'consumer knife ELF unchanged')
    require(formal['sha256'] != green['sha256'], 'formal compiler includes diagnostic patch')
    changed = set()
    for name, case in formal['by_input'].items():
        restored_case = formal_restore['by_input'][name]
        cut_case = consumer['by_input'][name]
        require(case['rc'] == restored_case['rc'] == cut_case['rc'] == 0,
                f'consumer arm failed before producing CHIR: {name}')
        require(bool(case['outputs']) and case['outputs'] == restored_case['outputs'],
                f'formal restored CHIR differs: {name}')
        if case['outputs'] != cut_case['outputs']:
            changed.add(name)
    require(changed == {'head_finalizer.cj'}, f'consumer changed unrelated fixtures: {changed}')
    relative = 'head_finalizer/output_CHIR/0_AST_CHIR.chirtxt'
    before = (args.evidence / 'fixtures-finaltrim-opt' / relative).read_text()
    after = (args.evidence / 'fixtures-consumertrim-opt' / relative).read_text()
    # UpdateMemberVarPath assigns fresh result IDs after translating field names.
    # Ignore only these definitions' numeric IDs for this secondary diagnostic;
    # all operands/order remain exact. Raw binary equality above is never normalized.
    normalize = lambda text: re.sub(r'(?m)^(\s*)%\d+(:)', r'\1%RESULT\2', text).splitlines()
    delta = list(difflib.ndiff(normalize(before), normalize(after)))
    removed = [line[2:] for line in delta if line.startswith('- ')]
    added = [line[2:] for line in delta if line.startswith('+ ')]
    require(len(removed) == 1 and 'StoreElementRef(' in removed[0] and not added,
            f'consumer changed more than one store (apart from result numbering): {removed}/{added}')
    operand = re.search(r'StoreElementRef\((%\d+),', removed[0])
    require(operand is not None and operand[1] + ': Bool = Constant() // false' in before,
            'removed store does not consume the constructor false constant')
    report['consumer'] = {'changed': sorted(changed), 'removed_expression': removed[0],
                          'formal_sha256': formal['sha256'], 'cut_sha256': consumer['sha256'],
                          'restored_sha256': formal_restore['sha256'], 'n': len(formal['cases'])}
    # The const-literal probe has not reached its consumer in real fixtures.
    # Its lack of a failure is intentionally not an acceptance condition.
    report['const_literal'] = 'NOT_REACHED; not passed; follow-up cjcj#224'
    report['ok'] = True
    args.json.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
