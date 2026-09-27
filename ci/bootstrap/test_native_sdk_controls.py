#!/usr/bin/env python3
"""Native script controls. Every arm consumes identical compiled fixture bytes."""
import concurrent.futures
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
fixtures = out / 'fixtures'
subprocess.run([sys.executable, str(root / 'ci/bootstrap/test_native_sdk.py'), str(fixtures), '--prepare'], check=True)
# Producer and consumer independently carry the native linker selection.
cuts = {
    'copy-cut': ('ci/bootstrap/sdk_build.sh', 'cp -aL "$BASE/." "$TO/"', 'cp -a "$BASE/." "$TO/"'),
    'producer-cut': ('ci/bootstrap/sdk_build.sh',
                     'for rel in MANIFEST bin/llc bin/opt bin/${HOST_LINKER} lib/STATIC_LLVM.txt',
                     'for rel in MANIFEST bin/llc bin/opt bin/ld.lld lib/STATIC_LLVM.txt'),
    'consumer-cut': ('ci/bootstrap/sdk_verify.py',
                     'linker = "ld64.lld" if darwin else "ld.lld"', 'linker = "ld.lld"'),
    'pair-cut': ('ci/bootstrap/std_runtime_colour.py',
                 'if bool(rt_hits) != bool(std_hits):', 'if not bool(rt_hits) and bool(std_hits):'),
}
arms = ['candidate', *cuts, 'restored']
for arm in arms:
    tree = out / arm / 'src'
    shutil.copytree(root / 'ci', tree / 'ci')
    if arm in cuts:
        file, before, after = cuts[arm]
        path = tree / file
        original = path.read_text()
        assert original.count(before) == 1, (arm, before)
        changed = original.replace(before, after)
        path.write_text(changed)
        (out / arm / 'cut.diff').write_text(''.join(difflib.unified_diff(
            original.splitlines(True), changed.splitlines(True), fromfile='a/' + file, tofile='b/' + file)))

def run(arm):
    evidence = out / arm / 'evidence'
    start = time.monotonic()
    result = subprocess.run([sys.executable, str(out / arm / 'src/ci/bootstrap/test_native_sdk.py'),
                             str(evidence), str(fixtures)], capture_output=True, text=True)
    (out / arm / 'test.log').write_text(result.stdout + result.stderr)
    records = json.loads((evidence / 'results.json').read_text())
    failed = [r['name'] for r in records['results'] if not all(r['checks'].values())]
    return arm, {'rc': result.returncode, 'failed': failed, 'objects': records['objects'],
                 'product': records['product'], 'wall': time.monotonic() - start}

with concurrent.futures.ThreadPoolExecutor(max_workers=len(arms)) as pool:
    results = dict(pool.map(run, arms))
(out / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
for arm, result in results.items():
    expected = ['official-std'] if arm == 'pair-cut' else (
        ['native-layout'] if os.uname().sysname == 'Darwin' and arm in cuts else [])
    print(f'ASSERT native-sdk-control arm={arm} rc={result["rc"]} failed={result["failed"]} expected={expected}', flush=True)
    assert result['failed'] == expected
    assert result['rc'] == (1 if expected else 0)
    assert result['objects'] == results['candidate']['objects']
assert results['candidate']['product'] == results['restored']['product']
for arm in arms:
    shutil.rmtree(out / arm / 'src')
print('ASSERT native-sdk-controls exact-failure-sets PASS')
