#!/usr/bin/env python3
"""Observe actual native runner processes; fixtures are inputs, never runner copies."""
import concurrent.futures
import difflib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
assert os.uname().sysname == 'Darwin'
platform = 'darwin_' + ('aarch64' if os.uname().machine == 'arm64' else 'x86_64')
tuple_name = platform + '_cjnative'
seed = out / 'objects'
subprocess.run([sys.executable, str(root / 'test_native_sdk.py'), str(seed), '--prepare'], check=True)
source = seed / 'observe.c'
source.write_text('#include <stdio.h>\n#include <stdlib.h>\nint main(void) { const char *p=getenv("DYLD_LIBRARY_PATH"); puts(p?p:"MISSING"); return 0; }\n')
compiler = seed / 'observe'
subprocess.run(['cc', str(source), '-o', str(compiler)], check=True)
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
original = (root / 'stage1_host_runner.sh').read_text()
compiler_call = 'write_runner "$target/bin/cjc" "$target/bin/cjcj-stage1" "$compiler_ld"'
backend_call = 'write_runner "$target/third_party/llvm/bin/$name" "$target/third_party/llvm/bin/$name-stage1" "$target_ld"'
assert original.count(compiler_call) == original.count(backend_call) == 1
variants = {'candidate': original, 'restored': original,
    'compiler-cut': original.replace(compiler_call, compiler_call.replace('$compiler_ld', '$target_ld')),
    'backend-cut': original.replace(backend_call, backend_call.replace('$target_ld', '$host_ld'))}

def copy(src, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dest)
    dest.chmod(src.stat().st_mode)

for arm, product in variants.items():
    here = out / arm
    here.mkdir()
    for helper in ('host_tools.sh', 'host_nm.py'):
        copy(root / helper, here / helper)
    (here / 'stage1_host_runner.sh').write_text(product)
    if product != original:
        (here / 'cut.diff').write_text(''.join(difflib.unified_diff(original.splitlines(True), product.splitlines(True),
            fromfile='a/ci/bootstrap/stage1_host_runner.sh', tofile='b/ci/bootstrap/stage1_host_runner.sh')))
    for sdk in ('host', 'run', 'target'):
        for entry in ('bin/cjc', 'tools/bin/cjpm', 'third_party/llvm/bin/llc', 'third_party/llvm/bin/opt'):
            copy(compiler, here / sdk / entry)
        for name in ('libcangjie-runtime.dylib', 'libboundscheck.dylib'):
            copy(seed / 'host.dylib', here / sdk / f'runtime/lib/{tuple_name}' / name)
        copy(seed / ('host.dylib' if sdk == 'host' else 'colour.dylib'), here / sdk / 'third_party/llvm/lib/libLLVM.dylib')
    (here / 'identities').write_text(''.join(f'{platform} {name} {sha(seed / "host.dylib")}\n'
        for name in ('libcangjie-runtime.dylib', 'libboundscheck.dylib', 'libLLVM.dylib')))

def run(arm):
    here = out / arm
    env = {**os.environ, 'STAGE1_HOST_IDENTITIES': str(here / 'identities')}
    env.pop('DYLD_LIBRARY_PATH', None)
    command = ['bash', str(here / 'stage1_host_runner.sh'), str(here / 'target'), str(here / 'host'),
        str(here / 'host'), sha(seed / 'host.dylib'), str(compiler), sha(compiler), str(here / 'run'), sha(seed / 'colour.dylib')]
    result = subprocess.run(command, env=env, capture_output=True, text=True, errors='backslashreplace')
    (here / 'assembly.log').write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stderr
    host = f'{here}/host/runtime/lib/{tuple_name}:{here}/host/lib/{tuple_name}'
    expected = {'cjc': f'{host}:{here}/run/third_party/llvm/lib:{here}/host/tools/lib',
        'cjpm': f'{host}:{here}/host/third_party/llvm/lib:{here}/host/tools/lib'}
    target = f'{here}/target/runtime/lib/{tuple_name}:{here}/target/lib/{tuple_name}:{here}/target/third_party/llvm/lib:{here}/target/tools/lib'
    expected.update(llc=target, opt=target)
    records = []
    for name, entry in [('cjc','bin/cjc'), ('cjpm','tools/bin/cjpm'), ('llc','third_party/llvm/bin/llc'), ('opt','third_party/llvm/bin/opt')]:
        observed = subprocess.run([str(here / 'target' / entry)], env=env, capture_output=True, text=True)
        records.append({'name':name, 'rc':observed.returncode, 'actual':observed.stdout.strip(),
                        'expected':expected[name], 'pass':observed.returncode == 0 and observed.stdout.strip() == expected[name]})
    (here / 'observations.json').write_text(json.dumps(records, indent=2))
    return arm, {'failed':[r['name'] for r in records if not r['pass']],
        'product_sha256':sha(here / 'stage1_host_runner.sh'), 'compiler_sha256':sha(compiler)}

with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    results = dict(pool.map(run, variants))
(out / 'results.json').write_text(json.dumps(results, indent=2))
for arm, record in results.items():
    expected = {'compiler-cut':['cjc'], 'backend-cut':['llc','opt']}.get(arm, [])
    print(f'ASSERT native-runner-binding arm={arm} failed={record["failed"]} expected={expected}', flush=True)
    assert record['failed'] == expected
assert results['candidate'] == results['restored']
