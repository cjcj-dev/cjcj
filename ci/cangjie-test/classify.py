#!/usr/bin/env python3
"""Read-only seven-way triage of upstream results. Original verdicts stay intact."""
import argparse
import json
from pathlib import Path
import re
from compare import compare
from run import dump

CATEGORIES = ('B_only', 'O_only', 'common', 'timeout', 'nondeterministic',
              'tool_not_ready', 'environment')
SUITES = ('Conformance', 'HLT', 'LLT')
TOOL_PATHS = {'cjlsp': 'LSPServer', 'cjdb': 'cjdb', 'cjpm': 'cjpm', 'cjfmt': 'cjfmt',
              'cjlint': 'cjlint', 'cjcov': 'cjcov', 'cjcompat': 'cjcompat', 'hle': 'hle',
              'cjtrace-recover': 'cjtrace-recover'}


def load(root):
    result = {}
    for suite in SUITES:
        summary = json.loads((root / suite / 'summary.json').read_text())
        if summary['status'] != 'ran':
            raise ValueError(suite + ': no run; classification unavailable')
        for row in json.loads((root / suite / 'cases.json').read_text()):
            key = (suite, row['name'])
            if key in result:
                raise ValueError('duplicate case: ' + repr(key))
            result[key] = row
    environment = root / 'environment.json'
    return result, json.loads(environment.read_text()) if environment.is_file() else {}


def tool_reasons(row, environment):
    detail, name = row.get('error_summary', ''), row['name']
    reasons = []
    for directory, tool in TOOL_PATHS.items():
        state = environment.get('tools', {}).get(tool)
        referenced = f'/Tools/{directory}/' in name or re.search(
            r'(?:/|\b)' + re.escape(tool) + r'(?:\s|["\']|$)', detail)
        if state and not state['ready'] and referenced:
            reasons.append(tool + ': ' + state['reason'])
    for dependency, signature in (('stdx', r"(?:-lstdx\.|package ['\"]stdx\.)"),
                                  ('JDK', r'(?:javac|java: command not found|JAVA_HOME)')):
        state = environment.get('readiness', {}).get(dependency)
        if state and not state['ready'] and re.search(signature, detail):
            reasons.append(dependency + ': ' + state['reason'])
    return reasons


def classify(official, bootstrap=None, repeat_official=None, repeat_bootstrap=None):
    roots = {'O': official}
    if bootstrap:
        compare(official, bootstrap)  # same pins/recipe, complete suites, original raw sets
        roots['B'] = bootstrap
    for label, original, repeat in (('O2', official, repeat_official),
                                     ('B2', bootstrap, repeat_bootstrap)):
        if repeat:
            if not original:
                raise ValueError(label + ': missing first run')
            result = compare(original, repeat)
            if not result['same_sdk']:
                raise ValueError(label + ': repeated SDK identity differs')
            roots[label] = repeat
    loaded = {arm: load(root) for arm, root in roots.items()}
    names = set.union(*(set(rows) for rows, _ in loaded.values()))
    result = {'comparison_available': bootstrap is not None,
              'repeat_evidence_available': {'O': bool(repeat_official), 'B': bool(repeat_bootstrap)},
              'categories': {name: [] for name in CATEGORIES}, 'unexecuted': [],
              'unpaired_failures': [], 'case_set_differences': [], 'raw_failure_counts': {}}
    for arm, (rows, _) in loaded.items():
        result['raw_failure_counts'][arm] = sum(row['category'] == 'fail' for row in rows.values())
    for key in sorted(names):
        records = {arm: rows[key] for arm, (rows, _) in loaded.items() if key in rows}
        entry = {'suite': key[0], 'name': key[1], 'records': records,
                 'sources': {arm: str(roots[arm] / key[0] / 'cases.json') for arm in records}}
        failures = {arm: row for arm, row in records.items() if row['category'] == 'fail'}
        if len(records) != len(roots):
            result['case_set_differences'].append(entry)
        if any(row['category'] == 'not_run' for row in records.values()):
            result['unexecuted'].append(entry)
        changed = any(second in loaded and (first not in records or second not in records or
                      records[first]['status'] != records[second]['status'])
                      for first, second in (('O', 'O2'), ('B', 'B2')))
        if changed:
            bucket = 'nondeterministic'
        elif not failures:
            continue
        elif any(row.get('timeout_failure') for row in failures.values()):
            bucket = 'timeout'
        else:
            reasons = {arm: tool_reasons(row, loaded[arm][1]) for arm, row in failures.items()}
            environment = {arm: row.get('environment_hints', []) for arm, row in failures.items()}
            if any(reasons.values()):
                bucket = 'tool_not_ready'
                entry['reasons'] = reasons
            elif any(environment.values()):
                bucket = 'environment'
                entry['hints'] = environment  # hints, not causal proof or exemptions
            elif 'O' in failures and 'B' in failures:
                bucket = 'common'
            elif 'B' in failures and records.get('O', {}).get('category') == 'pass':
                bucket = 'B_only'
            elif 'O' in failures and records.get('B', {}).get('category') == 'pass':
                bucket = 'O_only'
            else:
                result['unpaired_failures'].append(entry)
                continue
        result['categories'][bucket].append(entry)
    result['counts'] = {name: len(entries) for name, entries in result['categories'].items()}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('official', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--bootstrap', type=Path)
    parser.add_argument('--repeat-official', type=Path)
    parser.add_argument('--repeat-bootstrap', type=Path)
    args = parser.parse_args()
    result = classify(args.official, args.bootstrap, args.repeat_official, args.repeat_bootstrap)
    dump(args.output, result)
    print(json.dumps({'counts': result['counts'], 'comparison_available': result['comparison_available'],
                      'unpaired_failures': len(result['unpaired_failures']),
                      'unexecuted': len(result['unexecuted'])}, sort_keys=True))


if __name__ == '__main__':
    main()
