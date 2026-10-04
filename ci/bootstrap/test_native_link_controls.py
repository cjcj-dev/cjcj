#!/usr/bin/env python3
"""Validate the actual CLI's cjpm input; this does not claim compiler execution."""
import concurrent.futures
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tomllib

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
assert os.uname().sysname == 'Darwin'
consumer = 'ci/bootstrap/prepare_native_link.mjs'
producer = 'ci/platform_matrix/link_option.mjs'
original = {f: (root / f).read_text() for f in (consumer, producer)}
cuts = {'producer-cut': (producer, "path.join(llvmDir, 'libLLVM.dylib')", "path.join(llvmDir, 'libLLVM-15.so')"),
        'consumer-cut': (consumer, 'process.platform, sdk)', "'linux', sdk)")}
for arm in ('candidate', 'producer-cut', 'consumer-cut', 'restored'):
    for file, text in original.items():
        path = out / arm / file
        path.parent.mkdir(parents=True, exist_ok=True)
        if arm in cuts and cuts[arm][0] == file:
            _, before, after = cuts[arm]
            assert text.count(before) == 1
            text = text.replace(before, after)
            (out / arm / 'cut.diff').write_text(''.join(difflib.unified_diff(original[file].splitlines(True),
                text.splitlines(True), fromfile='a/' + file, tofile='b/' + file)))
        path.write_text(text)
    target = out / arm / 'input/packages/cjc/cjpm.toml'
    target.parent.mkdir(parents=True)
    shutil.copyfile(root / 'packages/cjc/cjpm.toml', target)

def run(arm):
    here = out / arm
    target = here / 'input/packages/cjc/cjpm.toml'
    before = tomllib.loads(target.read_text())
    sdk = here / 'sdk'
    result = subprocess.run(['node', str(here / consumer), str(here / 'input'), str(sdk)],
                            capture_output=True, text=True)
    after = tomllib.loads(target.read_text())
    option = after['package'].pop('link-option')
    before['package'].pop('link-option')
    expected = str(sdk / 'third_party/llvm/lib/libLLVM.dylib')
    checks = {'native-link': result.returncode == 0 and expected in option and '-lc++' in option
              and '-export_dynamic' in option and 'libLLVM-15.so' not in option and '-lstdc++' not in option,
              'other-fields': before == after}
    record = {'product_rc': result.returncode, 'link_option': option, 'checks': checks}
    (here / 'observed.json').write_text(json.dumps(record, indent=2))
    (here / 'cli.log').write_text(result.stdout + result.stderr)
    # The unchanged target assertions have their own process exit code per arm.
    assertion = subprocess.run([sys.executable, '-c',
        'import json,sys; r=json.load(open(sys.argv[1])); print("ASSERT native-link-result",r); sys.exit(not all(r["checks"].values()))',
        str(here / 'observed.json')], capture_output=True, text=True)
    (here / 'assertions.log').write_text(assertion.stdout + assertion.stderr)
    return arm, {'rc': assertion.returncode, 'failed':[n for n, ok in checks.items() if not ok],
        'product':{f:hashlib.sha256((here / f).read_bytes()).hexdigest() for f in original},
        'test_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = dict(pool.map(run, ('candidate','producer-cut','consumer-cut','restored')))
(out / 'results.json').write_text(json.dumps(results, indent=2))
for arm, result in results.items():
    expected = ['native-link'] if arm in cuts else []
    print(f'ASSERT native-link-control arm={arm} rc={result["rc"]} failed={result["failed"]}', flush=True)
    assert result['failed'] == expected and result['rc'] == bool(expected)
assert results['candidate'] == results['restored']
