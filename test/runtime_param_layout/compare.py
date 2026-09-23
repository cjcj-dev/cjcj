#!/usr/bin/env python3
"""Compare observed candidate layouts with runtime C++ offsetof/sizeof."""
import json
import sys
from pathlib import Path
root = Path(sys.argv[1])
manifest = json.loads((root/'manifest.json').read_text())['fields']
expected = {}
for line in (root/'cpp-layout.txt').read_text().splitlines():
    kind, key, *nums = line.split()
    expected[kind, key] = tuple(map(int, nums))
observed = {}
sizes = {}
for line in (root/'cj-layout.txt').read_text().splitlines():
    kind, key, *nums = line.split()
    if kind == 'SIZE':
        observed[kind, key] = tuple(map(int, nums))
    elif kind == 'FIELD_SIZE':
        sizes[key] = int(nums[0])
    elif kind == 'BYTES':
        values = bytes(map(int, nums[0].rstrip(',').split(',')))
        pattern = bytes(manifest[key]['pattern'])
        matches = [i for i in range(len(values)-len(pattern)+1) if values[i:i+len(pattern)] == pattern]
        if len(matches) != 1:
            print('FAIL marker occurrence', key, matches)
            sys.exit(2)
        observed['FIELD', key] = (matches[0], sizes[key])
failed = []
layout_failed = []
alignment_failed = []
for (kind, key), want in expected.items():
    got = observed.get((kind, key))
    target = want
    passed = got == target
    print(('PASS' if passed else 'FAIL'), kind, key, 'expected=', target, 'actual=', got)
    if not passed:
        failed.append(key)
        if kind == 'SIZE' and got is not None and got[0] == want[0]:
            alignment_failed.append(key)
        else:
            layout_failed.append(key)
extra = sorted(set(observed)-set(expected))
if extra: print('FAIL unexpected rows', extra)
print('ASSERTIONS', len(expected), 'FAILED', len(failed)+len(extra))
(root/'comparison.json').write_text(json.dumps({'assertions':len(expected), 'layout_failed':layout_failed, 'alignment_failed':alignment_failed, 'extra':extra}, indent=2)+'\n')
# Keep the aggregate failure visible. Separate results let the caller cite the
# offset/size contract without claiming that alignOf passed (cjcj#125).
layout_rc = int(bool(layout_failed or extra))
alignment_rc = int(bool(alignment_failed or any(
    observed.get(k, (None, None))[1] != v[1]
    for k, v in expected.items() if k[0] == 'SIZE')))
(root/'layout-contract.rc').write_text(str(layout_rc)+'\n')
(root/'alignment-contract.rc').write_text(str(alignment_rc)+'\n')
print('LAYOUT_ASSERT rc=', layout_rc, 'ALIGNMENT_ASSERT rc=', alignment_rc)
sys.exit(bool(failed or extra))
