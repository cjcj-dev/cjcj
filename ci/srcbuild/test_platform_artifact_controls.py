#!/usr/bin/env python3
"""Exercise artifact enumeration against real workflow uploads in isolated trees."""
import concurrent.futures
import difflib
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
product = Path('.github/workflows/build-llvm-tools.yml')
test = Path('ci/srcbuild/tests/platform-contract.test.mjs')
original = (root / product).read_text()
start = original.index('      - name: Upload LLVM tools\n')
end = original.index('\n  static-tuple:', start)
upload = original[start:end]
assert upload.count('uses: actions/upload-artifact@') == 1
variants = {
    'candidate': original,
    'same-job-cut': original[:end] + '\n' + upload + original[end:],
    'cross-job-cut': original + '\n  duplicate-artifact:\n    runs-on: ubuntu-22.04\n    steps:\n'
        + upload.replace('${{ matrix.platform }}', 'linux_x86_64'),
    'restored': original,
}
for arm, content in variants.items():
    tree = out / arm / 'src'
    for directory in ('.github', 'ci', 'build', 'scripts'):
        shutil.copytree(root / directory, tree / directory)
    (tree / product).write_text(content)
    if content != original:
        (out / arm / 'cut.diff').write_text(''.join(difflib.unified_diff(
            original.splitlines(True), content.splitlines(True), fromfile='a/' + str(product), tofile='b/' + str(product))))

def run(arm):
    tree = out / arm / 'src'
    result = subprocess.run(['node', '--test', str(tree / test)], capture_output=True, text=True)
    log = result.stdout + result.stderr
    (out / arm / 'test.log').write_text(log)
    return arm, {'rc': result.returncode, 'failed': re.findall(r'^not ok \d+ - (.+)$', log, re.M),
                 'tests': re.findall(r'^# tests (\d+)$', log, re.M),
                 'test_sha256': hashlib.sha256((tree / test).read_bytes()).hexdigest(),
                 'workflow_sha256': hashlib.sha256((tree / product).read_bytes()).hexdigest()}

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = dict(pool.map(run, variants))
(out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
for arm, result in results.items():
    expected = ['runnable source produces every package artifact exactly once'] if arm.endswith('-cut') else []
    print(f'ASSERT artifact-uniqueness arm={arm} rc={result["rc"]} failed={result["failed"]}', flush=True)
    assert result['rc'] == bool(expected) and result['failed'] == expected
    assert result['test_sha256'] == results['candidate']['test_sha256']
    assert result['tests'] == results['candidate']['tests']
assert results['candidate']['workflow_sha256'] == results['restored']['workflow_sha256']
for arm in ('same-job-cut', 'cross-job-cut'):
    assert results[arm]['workflow_sha256'] != results['candidate']['workflow_sha256']
for arm in variants:
    shutil.rmtree(out / arm / 'src')
