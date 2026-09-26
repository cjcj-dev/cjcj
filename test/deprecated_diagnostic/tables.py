#!/usr/bin/env python3
"""All ordinal-indexed refactor tables must describe the same diagnostic set."""
import re
import sys
from pathlib import Path
root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[2]
text = (root / 'packages/basic/src/DiagnosticTables.cj').read_text()
def array(name):
    return text.split('public let ' + name + ':', 1)[1].split('\n]', 1)[0].splitlines()[1:]
names = re.findall(r'"(\w+)"', '\n'.join(array('RE_DIAG_KIND_STR')))
indices = [(n, int(i)) for n, i in re.findall(r'case DiagKindRefactor\.(\w+) => (\d+)', text)]
checks = {'ordinal-order': indices == list(zip(names, range(len(names))))}
for name in ('errorData', 'rDiagSeveritys', 'rWarnGroups'):
    checks[name + '-coverage'] = len(array(name)) == len(names)
for name, severity, group in [('sema_deprecated_error', 'DS_ERROR', 'NONE'),
                               ('sema_deprecated_warning', 'DS_WARNING', 'DEPRECATED')]:
    index = names.index(name)
    checks[name + '-severity'] = re.search(r'DiagSeverity\.(\w+)', array('rDiagSeveritys')[index])[1] == severity
    checks[name + '-group'] = re.search(r'WarnGroup\.(\w+)', array('rWarnGroups')[index])[1] == group
for name, passed in checks.items():
    print(('PASS ' if passed else 'FAIL ') + name)
raise SystemExit(0 if all(checks.values()) else 1)
