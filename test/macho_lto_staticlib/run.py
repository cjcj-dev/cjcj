#!/usr/bin/env python3
"""Link the fixture against the built product archives, then inspect real commands.

The SDK compiles the observer; --product contains the unmodified production build.
This tests command construction, not execution of an Apple-platform archive.
"""
import argparse
import concurrent.futures
import hashlib
import itertools
import json
import os
from pathlib import Path
import subprocess

p = argparse.ArgumentParser()
p.add_argument('--sdk', type=Path, required=True)
p.add_argument('--product', type=Path, required=True)
p.add_argument('--llvm-library', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
sdk = a.sdk.resolve()
product = a.product.resolve()
env = dict(os.environ, CANGJIE_HOME=str(sdk))
env['LD_LIBRARY_PATH'] = ':'.join(str(sdk/x) for x in (
    'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
    'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
binary = a.out.resolve()/'commands'
cmd = [str(sdk/'bin/cjc'), str(Path(__file__).with_name('commands.cj').resolve()), '-O1', '-o', str(binary)]
archives = []
for d in sorted((product/'target/release').glob('*@cjcj')):
    cmd += ['--import-path', str(d), '-L', str(d)]
    archives.extend(d.glob('*.a'))
cmd += ['--link-option=--start-group'] + [str(f) for f in archives] + ['--link-option=--end-group']
cmd += [str(product/'runtime_shim/cjselfhost_llvmshim.o'), str(product/'runtime_shim/cjc_runtime_config.o'),
        '--link-option=' + str(a.llvm_library.resolve()), '-lstdc++', '--link-option=--export-dynamic']
(a.out/'compile-command.json').write_text(json.dumps(cmd, indent=2))
with (a.out/'compile.log').open('w') as out:
    rc = subprocess.run(cmd, env=env, stdout=out, stderr=subprocess.STDOUT).returncode
(a.out/'compile.rc').write_text(str(rc))
if rc:
    raise SystemExit(rc)
identity = {str(f): hashlib.sha256(f.read_bytes()).hexdigest() for f in [binary, *archives]}
(a.out/'identity.json').write_text(json.dumps(identity, indent=2))

def run(case):
    d = a.out.resolve()/"-".join(case)
    d.mkdir(exist_ok=True)
    with (d/'run.log').open('w') as out:
        rc = subprocess.run([str(binary), str(sdk), *case], cwd=d, env=dict(env, LD_LIBRARY_PATH=str(a.llvm_library.resolve().parent)+':'+env['LD_LIBRARY_PATH']),
                            stdout=out, stderr=subprocess.STDOUT).returncode
    (d/'run.rc').write_text(str(rc))
    return (d.name, rc)
cases = list(itertools.product(("device", "simulator"), ("static", "dynamic"),
                               ("full", "thin"), ("normal", "incremental"), ("native", "bitcode")))
cases += [(plat, "dynamic", "full", "normal", "shared") for plat in ("device", "simulator")]
cases += [("darwin-component", std, mode, "normal", "native") for std in ("static", "dynamic") for mode in ("full", "thin")]
with concurrent.futures.ThreadPoolExecutor(max_workers=32) as pool:
    results = dict(pool.map(run, cases))
(a.out/'results.json').write_text(json.dumps(results, indent=2))
print(json.dumps(results))
raise SystemExit(int(any(results.values())))
