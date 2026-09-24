#!/usr/bin/env python3
"""Build declaration-only ObjC imports, then compile real source with a stage1 ELF.

The fixture does not execute Objective-C calls; assertions consume AST, CHIR and
pre-optimization LLVM from the compiler, before optimizers can infer nounwind.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

p = argparse.ArgumentParser()
p.add_argument('--compiler', type=Path, required=True)
p.add_argument('--sdk', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--imports', type=Path, help='reuse the same physically copied declaration artifacts across arms')
a = p.parse_args()
a.compiler = a.compiler.resolve()
a.sdk = a.sdk.resolve()
a.out = a.out.resolve()
a.out.mkdir(parents=True, exist_ok=True)
source = Path(__file__).resolve().parent
env = os.environ.copy()
env['CANGJIE_HOME'] = str(a.sdk)
env['LD_LIBRARY_PATH'] = ':'.join(str(a.sdk / s) for s in ['runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative', 'third_party/llvm/lib', 'tools/lib']) + ':/usr/lib/x86_64-linux-gnu'
env['PATH'] = ':'.join(str(a.sdk / s) for s in ['bin', 'tools/bin', 'third_party/llvm/bin']) + ':/usr/bin:/bin'
identities = {}
for file in [a.compiler, a.sdk/'bin/cjc', a.sdk/'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so', a.sdk/'runtime/lib/linux_x86_64_cjnative/libboundscheck.so', a.sdk/'third_party/llvm/lib/libLLVM-15.so', source/'finalizers.cj', source/'check.py']:
    digest = hashlib.sha256()
    with file.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    identities[str(file)] = digest.hexdigest()
(a.out / 'identities.json').write_text(json.dumps(identities, indent=2)+'\n')
(a.out / 'uptime.before').write_text(subprocess.check_output(['uptime'], text=True))
(a.out / 'affinity.txt').write_text(str(sorted(os.sched_getaffinity(0)))+'\n')

def run(name, cmd):
    start = time.monotonic()
    with (a.out / (name+'.log')).open('w') as log:
        log.write('COMMAND '+json.dumps([str(v) for v in cmd])+'\n'); log.flush()
        rc = subprocess.run([str(v) for v in cmd], cwd=a.out, env=env, stdout=log, stderr=subprocess.STDOUT).returncode
    (a.out / (name+'.rc')).write_text(str(rc)+'\n')
    print(name, 'rc='+str(rc), 'wall='+str(round(time.monotonic()-start, 2)), flush=True)
    return rc

imports = a.imports.resolve() if a.imports else a.out/'imports'
if not a.imports:
    (imports/'objc').mkdir(parents=True, exist_ok=True)
    for name in ['internal', 'lang']:
        rc = run('stub-'+name, [a.sdk/'bin/cjc', source/(name+'.cj'), '--import-path', imports, '--output-type=staticlib', '--output-dir', imports/'objc', '-o', name+'.a'])
        if rc: raise SystemExit(2)
rc = run('compile', [a.compiler, source/'finalizers.cj', '--import-path', imports, '--output-type=staticlib', '--save-temps='+str(a.out), '--dump-ast', '--dump-chir', '-O0', '-j', str(os.cpu_count()), '-o', a.out/'fixture.a'])
if rc: raise SystemExit(2)
for bc in sorted(a.out.glob('*-nothrow_fixture.bc')):
    if run('disassemble-'+bc.stem, [a.sdk/'third_party/llvm/bin/llvm-dis', bc, '-o', bc.with_suffix('.ll')]):
        raise SystemExit(2)
rc = run('check', [sys.executable, source/'check.py', a.out])
(a.out / 'uptime.after').write_text(subprocess.check_output(['uptime'], text=True))
print((a.out/'check.log').read_text())
raise SystemExit(rc)
