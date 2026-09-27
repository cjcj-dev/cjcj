#!/usr/bin/env python3
import concurrent.futures
import difflib
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
seed = out / 'seed'
subprocess.run([sys.executable, str(root / 'ci/release/test_darwin_std.py'), str(seed), '--prepare'], check=True)
product = 'ci/release/darwin_std.mjs'
original = (root / product).read_text()
consumer = '    assert.equal(digest(regular(root, relative)), expected, `COLOUR_RT_STD_FILE_SHA256: ${relative}`);'
assert original.count(consumer) == original.count('  return pin;') == 1
variants = {'candidate': original, 'restored': original,
    'producer-cut': original.replace('  return pin;', "  return {...pin, compiler_sha256: pin.compiler_sha256.split('').reverse().join('')};"),
    'consumer-cut': original.replace(consumer, '    // Fault arm: omit std payload byte comparison.')}
for arm, text in variants.items():
    tree = out / arm / 'src'
    shutil.copytree(root / 'ci', tree / 'ci')
    (tree / product).write_text(text)
    if text != original:
        (out / arm / 'cut.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True),
            text.splitlines(True), fromfile='a/' + product, tofile='b/' + product)))

def run(arm):
    result = subprocess.run([sys.executable, str(out / arm / 'src/ci/release/test_darwin_std.py'),
                             str(out / arm / 'evidence'), str(seed)], capture_output=True, text=True)
    (out / arm / 'test.log').write_text(result.stdout + result.stderr)
    records = json.loads((out / arm / 'evidence/results.json').read_text())
    return arm, {'rc': result.returncode,
        'failed': [r['name'] for r in records if not all(r['checks'].values())],
        'product_sha256': hashlib.sha256((out / arm / 'src' / product).read_bytes()).hexdigest(),
        'test_sha256': hashlib.sha256((out / arm / 'src/ci/release/test_darwin_std.py').read_bytes()).hexdigest()}

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = dict(pool.map(run, variants))
(out / 'results.json').write_text(json.dumps({'arms': results, 'objects': {
    str(p.relative_to(seed)): hashlib.sha256(p.read_bytes()).hexdigest() for p in (seed / 'objects').iterdir() if p.is_file()}}, indent=2))
for arm, r in results.items():
    expected = {'producer-cut': ['producer-identity'], 'consumer-cut': ['changed-std']}.get(arm, [])
    print(f'ASSERT native-std-control arm={arm} rc={r["rc"]} failed={r["failed"]} expected={expected}', flush=True)
    assert r['rc'] == bool(expected) and r['failed'] == expected
    assert r['test_sha256'] == results['candidate']['test_sha256']
assert results['candidate']['product_sha256'] == results['restored']['product_sha256']
for arm in results: shutil.rmtree(out / arm / 'src')
