#!/usr/bin/env python3
"""Observe retained interface declarations in product-emitted final CHIR."""
import argparse
import json
from pathlib import Path
import re

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('root', type=Path)
args = p.parse_args()
directory = args.root / 'ordinary-04_iface_enum'
record = json.loads((directory / 'result.json').read_text())
dump = directory / 'output_CHIR/3_EraseUselessDebugExpr.chirtxt'
if record['rc'] != 0 or not dump.exists():
    print('ENTRY_FAILURE declarations compiler_rc=', record['rc'], 'dump=', dump.exists())
    raise SystemExit(2)
text = dump.read_text()
abstract = re.findall(r'^.*\[abstract\].* Func @_CN7default5Shape4areaHv\(', text, re.M)
concrete = re.findall(r'^.* Func @_CN7default6Circle4areaHv\(', text, re.M)
print('TARGET_DECLARATION', json.dumps(dict(abstract=abstract, concrete=concrete,
    passed=len(abstract) == 1 and len(concrete) == 1, path=str(dump))))
raise SystemExit(0 if len(abstract) == 1 and len(concrete) == 1 else 1)
