#!/usr/bin/env python3
"""Preserve raw binary/text differences and isolate Constant print layout changes."""
import argparse
import difflib
import json
from pathlib import Path
import re

LITERAL = r'''(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|[-+]?[0-9.eE]+[iuf]|true|false|null|unit)'''
OLD_CONSTANT = re.compile(r'^(.*\bConstant)\(\) // (?:(.*), )?(' + LITERAL + r')$')


def normalize(text):
    result = []
    for line in text.splitlines(keepends=True):
        m = OLD_CONSTANT.fullmatch(line.rstrip('\n'))
        if m:
            line = m[1] + '(' + m[3] + ')' + (' // ' + m[2] if m[2] else '') + '\n'
        result.append(line)
    return ''.join(result)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('baseline', type=Path)
    p.add_argument('candidate', type=Path)
    p.add_argument('out', type=Path)
    args = p.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    records = []
    for directory in sorted(args.baseline.iterdir()):
        if not directory.is_dir():
            continue
        other = args.candidate / directory.name
        a = json.loads((directory / 'result.json').read_text())
        b = json.loads((other / 'result.json').read_text())
        paths = sorted({str(f.relative_to(directory)) for f in directory.rglob('*.chirtxt')} |
                       {str(f.relative_to(other)) for f in other.rglob('*.chirtxt')})
        record = dict(case=directory.name, baseline_rc=a['rc'], candidate_rc=b['rc'],
                      binary_equal=a['outputs'] == b['outputs'], text=[])
        for rel in paths:
            left, right = directory / rel, other / rel
            old = left.read_text() if left.exists() else ''
            new = right.read_text() if right.exists() else ''
            normalized = normalize(old)
            category = 'identical' if old == new else ('literal-layout' if normalized == new else 'semantic-diff')
            item = dict(path=rel, category=category)
            if category == 'semantic-diff':
                dest = args.out / directory.name / (Path(rel).name + '.diff')
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_text(''.join(difflib.unified_diff(normalized.splitlines(True), new.splitlines(True),
                                                          fromfile=str(left), tofile=str(right))))
                item['diff'] = str(dest)
            record['text'].append(item)
        records.append(record)
    (args.out / 'result.json').write_text(json.dumps(records, indent=2) + '\n')
    for record in records:
        print(record['case'], 'rc=', (record['baseline_rc'], record['candidate_rc']),
              'binary_equal=', record['binary_equal'],
              'text=', sorted({item['category'] for item in record['text']}))


if __name__ == '__main__':
    main()
