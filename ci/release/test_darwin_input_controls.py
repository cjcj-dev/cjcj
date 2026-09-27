#!/usr/bin/env python3
"""Run the same input-entry tests against baseline/candidate/cut/restored scripts."""
import concurrent.futures
import difflib
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
product = 'ci/release/prepare_bootstrap_inputs.mjs'
original = (root / product).read_text()
before = "if ((process.env.CJCJ_SRCBUILD_TARGET || process.platform).startsWith('darwin')"
after = "if ((process.env.CJCJ_SRCBUILD_TARGET || process.platform).startsWith('unsupported-darwin')"
assert original.count(before) == 1
cut = original.replace(before, after)
base = subprocess.check_output(['git', 'show', f'{sys.argv[2]}:{product}'], cwd=root, text=True)
for arm, content in {'baseline': base, 'candidate': original, 'cut': cut, 'restored': original}.items():
    tree = out / arm / 'src'
    shutil.copytree(root / 'ci', tree / 'ci')
    (tree / product).write_text(content)
(out / 'cut.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True), cut.splitlines(True),
    fromfile='a/' + product, tofile='b/' + product)))

def run(arm):
    tree = out / arm / 'src'
    start = time.monotonic()
    result = subprocess.run(['node', '--test', str(tree / 'ci/release/prepare_llvm_dylib.test.mjs')],
                            capture_output=True, text=True)
    text = result.stdout + result.stderr
    (out / arm / 'test.log').write_text(text)
    return arm, {'rc': result.returncode, 'failed': re.findall(r'^not ok \d+ - (.+)$', text, re.M),
                 'tests': re.findall(r'^# tests (\d+)$', text, re.M), 'wall': time.monotonic() - start,
                 'product_sha256': hashlib.sha256((tree / product).read_bytes()).hexdigest(),
                 'test_sha256': hashlib.sha256((tree / 'ci/release/prepare_llvm_dylib.test.mjs').read_bytes()).hexdigest()}

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = dict(pool.map(run, ('baseline', 'candidate', 'cut', 'restored')))
(out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
for arm, result in results.items():
    expected = [f'{target} requires an explicit colour artifact at the real input entry'
                for target in ('darwin-arm64', 'darwin-x64')] if arm in ('baseline', 'cut') else []
    print(f'ASSERT darwin-input-control arm={arm} rc={result["rc"]} failed={result["failed"]}', flush=True)
    assert result['failed'] == expected
    assert result['rc'] == bool(expected)
    assert result['tests'] and result['tests'] == results['candidate']['tests']
    assert result['test_sha256'] == results['candidate']['test_sha256']
assert results['candidate']['product_sha256'] == results['restored']['product_sha256'] != results['cut']['product_sha256']
for arm in results:
    shutil.rmtree(out / arm / 'src')
