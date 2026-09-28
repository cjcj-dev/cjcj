#!/usr/bin/env python3
"""Native object fixtures for the real std producer and source-input consumer."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
platform = 'darwin_' + ('aarch64' if os.uname().machine == 'arm64' else 'x86_64')
tuple_name = platform + '_cjnative'
assert os.uname().sysname == 'Darwin', 'native Mach-O fixtures required'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
seed = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 and sys.argv[2] != '--prepare' else out
pin = dict(line.split('=', 1) for line in (root / 'ci/runtime_pin.env').read_text().splitlines()
           if '=' in line and not line.startswith('#'))['RUNTIME_REF']
env = {**os.environ, 'RUNTIME_REF': pin, 'GITHUB_SHA': 'b' * 40, 'GITHUB_RUN_ID': '123',
       'GITHUB_RUN_ATTEMPT': '1', 'COLOUR_RT_RUN_ID': '123', 'COLOUR_RT_RUN_ATTEMPT': '1',
       'RUNNER_TEMP': str(out)}

def run(script, args, product=root):
    return subprocess.run(['node', str(product / 'ci/release' / script), *map(str, args)], env=env,
                          capture_output=True, text=True, errors='backslashreplace')

def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)

if len(sys.argv) > 2 and sys.argv[2] == '--prepare':
    objects = out / 'objects'
    subprocess.run([sys.executable, str(root / 'ci/bootstrap/test_native_sdk.py'), str(objects), '--prepare'], check=True)
    prefix = out / 'prefix'
    host = out / 'host'
    runtime_source = out / 'runtime-source'
    copy(objects / 'std.a', prefix / f'lib/{tuple_name}/libcangjie-std-core.a')
    copy(objects / 'host.dylib', prefix / f'runtime/lib/{tuple_name}/libcangjie-std-core.dylib')
    copy(objects / 'host.dylib', prefix / 'lib/libstdFFI.dylib')
    modules = prefix / 'modules' / tuple_name
    modules.mkdir(parents=True)
    (modules / 'std.core.cjo').write_text('module input fixture\n')
    (prefix / 'std-producer.json').write_text(json.dumps({'compiler_sha256': sha(objects / 'tool')}))
    copy(objects / 'host.dylib', host / f'runtime/lib/{tuple_name}/libcangjie-runtime.dylib')
    # Match the real runtime export contract before exercising the independent std checks.
    colour_source = objects / 'colour.dylib.c'
    with colour_source.open('a') as source:
        source.write('\n' + '\n'.join('void CJ_MCC_PackageInit' + suffix + '(void) {}'
                                    for suffix in ('Begin', 'Complete', 'Fail', 'Abort')))
    subprocess.run(['/usr/bin/clang', '-dynamiclib', str(colour_source), '-o', str(objects / 'colour.dylib')], check=True)
    copy(objects / 'colour.dylib', runtime_source / f'runtime/lib/{tuple_name}/libcangjie-runtime.dylib')
    copy(objects / 'host.dylib', runtime_source / f'runtime/lib/{tuple_name}/libboundscheck.dylib')
    obj = objects / 'runtime.o'
    subprocess.run(['cc', '-c', str(objects / 'colour.dylib.c'), '-o', str(obj)], check=True)
    archive = runtime_source / f'lib/{tuple_name}/libcangjie-runtime.a'
    archive.parent.mkdir(parents=True)
    subprocess.run(['ar', 'rcs', str(archive), str(obj)], check=True)
    (runtime_source / 'SOURCE_SHA').write_text(pin)
    result = run('darwin_runtime.mjs', ['prepare', out / 'runtime', platform, runtime_source])
    assert result.returncode == 0, result.stderr
    env['COLOUR_RT_MANIFEST_SHA256'] = sha(out / 'runtime/manifest.json')
    result = run('darwin_std.mjs', [prefix, out / 'runtime', host, objects / 'tool', platform, out / 'std'])
    (out / 'prepare.log').write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stderr
    sys.exit(0)

prefix, runtime, host, compiler = (seed / 'prefix', seed / 'runtime', seed / 'host', seed / 'objects/tool')
env['COLOUR_RT_MANIFEST_SHA256'] = sha(runtime / 'manifest.json')
identity = json.loads((seed / 'darwin-std-identity.json').read_text())
records = []
# Producer observations stay independent of the pre-produced consumer fixtures.
result = run('darwin_std.mjs', [prefix, runtime, host, compiler, platform, out / 'produced'])
(out / 'producer.log').write_text(result.stdout + result.stderr)
checks = {'status': result.returncode == 0}
if result.returncode == 0:
    manifest = json.loads((out / 'produced/std-manifest.json').read_text())
    checks['compiler-bytes'] = manifest['compiler_sha256'] == sha(compiler)
    checks['emitted-compiler'] = json.loads((out / 'darwin-std-identity.json').read_text())['compiler_sha256'] == sha(compiler)
    checks['std-bytes'] = sha(out / f'produced/lib/{tuple_name}/libcangjie-std-core.a') == sha(prefix / f'lib/{tuple_name}/libcangjie-std-core.a')
records.append({'name': 'producer-identity', 'rc': result.returncode, 'checks': checks})
for name, injected, expect_ok in (
        ('bundled-runtime', f'runtime/lib/{tuple_name}/libcangjie-runtime.dylib', False),
        ('bundled-boundscheck-runtime-dir', f'runtime/lib/{tuple_name}/libboundscheck.dylib', False),
        ('own-boundscheck-lib', f'lib/{tuple_name}/libboundscheck.dylib', True)):
    work_prefix = out / (name + '-prefix')
    shutil.copytree(prefix, work_prefix)
    copy(seed / 'objects/host.dylib', work_prefix / injected)
    result = run('darwin_std.mjs', [work_prefix, runtime, host, compiler, platform, out / (name + '-std')])
    text = result.stdout + result.stderr
    (out / (name + '.log')).write_text(text)
    records.append({'name': name, 'rc': result.returncode,
                    'checks': {'status': (result.returncode == 0) == expect_ok,
                               'target': expect_ok or 'COLOUR_RT_STD_CORE_LIBRARY' in text}})
for name in ('valid', 'changed-std', 'wrong-compiler-pin', 'missing-std'):
    work = out / name
    shutil.copytree(runtime, work)
    shutil.copytree(seed / 'std', work, dirs_exist_ok=True)
    selected = dict(identity)
    if name == 'changed-std':
        with (work / f'lib/{tuple_name}/libcangjie-std-core.a').open('ab') as file: file.write(b'changed')
    elif name == 'wrong-compiler-pin': selected['compiler_sha256'] = '0' * 64
    elif name == 'missing-std': (work / f'lib/{tuple_name}/libcangjie-std-core.a').unlink()
    product = out / (name + '-product')
    shutil.copytree(root / 'ci', product / 'ci')
    release = product / 'ci/colour-runtime/release.json'
    release.write_text(json.dumps({'platforms': {platform: {'std': selected}}}))
    result = run('darwin_runtime.mjs', ['source', work, platform], product)
    text = result.stdout + result.stderr
    (out / (name + '.log')).write_text(text)
    expected = {'valid': 'COLOUR_RT_STD_VERIFIED', 'changed-std': 'COLOUR_RT_STD_FILE_SHA256',
                'wrong-compiler-pin': 'COLOUR_RT_STD_COMPILER_IDENTITY', 'missing-std': 'COLOUR_RT_STD_MISSING'}[name]
    records.append({'name': name, 'rc': result.returncode,
                    'checks': {'status': (result.returncode == 0) == (name == 'valid'), 'target': expected in text}})
for record in records: print('ASSERT native-std-result ' + json.dumps(record), flush=True)
(out / 'results.json').write_text(json.dumps(records, indent=2))
assert all(all(r['checks'].values()) for r in records), records
