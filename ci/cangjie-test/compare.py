#!/usr/bin/env python3
"""Compare case identities, counts and statuses from two runs of the same recipe."""
import argparse
import json
from pathlib import Path
from run import dump


def compare(left, right):
    identities = [json.loads((root / 'identity.json').read_text()) for root in (left, right)]
    for key in ('pins', 'jobs', 'recipe_sha256'):
        if identities[0][key] != identities[1][key]:
            raise ValueError('different comparison recipe: ' + key)
    result = {'same_sdk': all(identities[0][key] == identities[1][key]
                            for key in ('compiler_sha256', 'runtime_sha256')), 'suites': {}}
    for suite in ('Conformance', 'HLT', 'LLT'):
        summaries = [json.loads((root / suite / 'summary.json').read_text()) for root in (left, right)]
        if any(s['status'] != 'ran' for s in summaries):
            raise ValueError(suite + ': missing run; comparison unavailable')
        arms = [json.loads((root / suite / 'cases.json').read_text()) for root in (left, right)]
        index = [{row['name']: row for row in arm} for arm in arms]
        names = [set(arm) for arm in index]
        failures = [{name for name, row in arm.items() if row['category'] in ('fail', 'not_run')}
                    for arm in index]
        result['suites'][suite] = {
            'counts': [s['counts'] for s in summaries],
            'counts_equal': summaries[0]['counts'] == summaries[1]['counts'],
            'left_only_cases': sorted(names[0] - names[1]),
            'right_only_cases': sorted(names[1] - names[0]),
            'left_only_failures': sorted(failures[0] - failures[1]),
            'right_only_failures': sorted(failures[1] - failures[0]),
            'common_failures': sorted(failures[0] & failures[1]),
            'status_changes': [{'name': name, 'left': index[0][name]['status'],
                                'right': index[1][name]['status']}
                               for name in sorted(names[0] & names[1])
                               if index[0][name]['status'] != index[1][name]['status']]}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('left', type=Path)
    parser.add_argument('right', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--repeat', action='store_true', help='require identical SDK, counts and case set')
    args = parser.parse_args()
    result = compare(args.left, args.right)
    dump(args.output, result)
    if args.repeat:
        return int(not result['same_sdk'] or any(not s['counts_equal'] or s['left_only_cases']
                   or s['right_only_cases'] for s in result['suites'].values()))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
