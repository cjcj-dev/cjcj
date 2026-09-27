#!/usr/bin/env python3
"""Run the real GHA entry in independent baseline/candidate/cut/restored trees."""
import concurrent.futures
import difflib
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
base = sys.argv[2]
os_name = os.uname().sysname
arch = {'arm64': 'aarch64'}.get(os.uname().machine, os.uname().machine)
tuple_name = f'{os_name.lower()}_{arch}_cjnative'
product = Path('ci/bootstrap/bootstrap.sh')
original = (root / product).read_text()
old = subprocess.check_output(['git', 'show', f'{base}:{product}'], cwd=root, text=True)
cut = original.replace('Darwin/arm64) HOST_TUPLE=darwin_aarch64_cjnative; HOST_MULTIARCH=;;',
                       'Darwin/arm64) die "unsupported native host";;').replace(
    'Darwin/x86_64) HOST_TUPLE=darwin_x86_64_cjnative; HOST_MULTIARCH=;;',
    'Darwin/x86_64) die "unsupported native host";;')
assert cut != original
(out / 'cut.diff').write_text(''.join(difflib.unified_diff(
    original.splitlines(True), cut.splitlines(True), fromfile=f'a/{product}', tofile=f'b/{product}')))
# Separate worktrees keep the GHA entry's git/source identity checks real.
for arm in ('baseline', 'candidate', 'cut', 'restored'):
    subprocess.run(['git', 'worktree', 'add', '--detach', str(out / arm / 'src'), 'HEAD'],
                   cwd=root, check=True, stdout=subprocess.DEVNULL)
    (out / arm / 'src' / product).write_text({'baseline': old, 'cut': cut}.get(arm, original))

def run(arm):
    source = out / arm / 'src'
    evidence = out / arm / 'evidence'
    start = time.monotonic()
    result = subprocess.run(['bash', str(source / 'ci/bootstrap/test_native_host.sh'), tuple_name,
                             str(evidence)], text=True, capture_output=True)
    (out / arm / 'test.log').write_text(result.stdout + result.stderr)
    expected = 1 if os_name == 'Darwin' and arm in ('baseline', 'cut') else 0
    record = {'rc': result.returncode, 'expected_rc': expected, 'wall': time.monotonic() - start,
              'sha256': hashlib.sha256((source / product).read_bytes()).hexdigest()}
    record['target_assertion'] = 'ASSERT native-host-route ' in result.stdout
    return arm, record

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = dict(pool.map(run, ('baseline', 'candidate', 'cut', 'restored')))
(out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
print(json.dumps(results, indent=2))
for arm in results:
    subprocess.run(['git', 'worktree', 'remove', '--force', str(out / arm / 'src')], cwd=root, check=True)
assert all(r['rc'] == r['expected_rc'] and r['target_assertion'] for r in results.values())
assert results['candidate']['sha256'] == results['restored']['sha256'] != results['cut']['sha256']
print('ASSERT native-host-controls exact-result-set PASS')
