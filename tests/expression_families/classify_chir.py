#!/usr/bin/env python3
"""List CHIR differences; never rewrite or normalize Function.localId cursors."""
import argparse
import json
from pathlib import Path
import re


def differences(left, right, path=''):
    if type(left) is not type(right):
        yield path, left, right
    elif isinstance(left, dict):
        for key in sorted(left.keys() | right.keys()):
            if key not in left or key not in right:
                yield path + '/' + key, left.get(key), right.get(key)
            else:
                yield from differences(left[key], right[key], path + '/' + key)
    elif isinstance(left, list):
        if len(left) != len(right):
            yield path + '/length', len(left), len(right)
        else:
            for index, (a, b) in enumerate(zip(left, right)):
                yield from differences(a, b, path + '/' + str(index))
    elif left != right:
        yield path, left, right


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('comparison', type=Path)
    args = p.parse_args()
    manifest = json.loads((args.comparison / 'result.json').read_text())
    report = {'cases': [], 'all_completed': True, 'all_differences_classified': True}
    for index, case in enumerate(manifest['cases']):
        row = {'source': case['source'], 'index': index}
        left, right = (Path(case.get(arm, {}).get('artifact_dir', str(args.comparison / str(index) / arm))) / 'canonical.json' for arm in ('baseline', 'candidate'))
        if not left.exists() or not right.exists():
            row['status'] = 'NOT_COMPLETE'
            report['all_completed'] = report['all_differences_classified'] = False
        else:
            a, b = json.loads(left.read_text()), json.loads(right.read_text())
            diff = list(differences(a, b))
            expected, unexpected = [], []
            for path, av, bv in diff:
                match = re.fullmatch(r'/values/(\d+)/localId', path)
                if match and a['values_type'][int(match[1])] == b['values_type'][int(match[1])] == 'Function':
                    expected.append({'path': path, 'baseline': av, 'candidate': bv,
                                     'function': a['values'][int(match[1])]['base']['rawMangledName']})
                else:
                    unexpected.append({'path': path, 'baseline': av, 'candidate': bv})
            row.update(status='ran', expected_local_id_differences=expected, unexpected_differences=unexpected,
                       same_normalized_bytes=not diff, only_expected_differences=not unexpected)
            if unexpected:
                report['all_differences_classified'] = False
            # Full original decoded trees and both unchanged canonical byte streams remain on disk.
            (args.comparison / str(index) / 'differences.json').write_text(json.dumps(diff, indent=2) + '\n')
            del a, b, diff
            print(f"CHIR_DIFF {case['source']} localId={len(expected)} unexpected={len(unexpected)}", flush=True)
        report['cases'].append(row)
        (args.comparison / 'classified.json').write_text(json.dumps(report, indent=2) + '\n')
    return 0 if report['all_completed'] and report['all_differences_classified'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
