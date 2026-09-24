#!/usr/bin/env python3
"""Exercise compiler text transport and the paired runtime's single parser.

The compiler runs using the caller's loader. Programs use --product-loader.
Invalid soft sizes must compile (VM owns validation), then fail at startup.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('--compiler', required=True)
p.add_argument('--product-loader', required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--n', type=int, default=3)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
# HotSpot parseInteger.hpp:120-176; runtime jvmFlagConstraintsGC.cpp:292.
cases = [('default', None, True), ('valid', '32M', True),
         ('zero', '0', True), ('decimal-leading-zero', '010', True),
         ('hex', '0x2000000', True), ('over-max', '128M', False),
         ('leading-space', ' 32M', False), ('trailing-space', '32M ', False),
         ('internal-space', '32 M', False), ('byte-overflow', '18446744073709551616', False),
         ('scale-overflow', '18446744073709551615K', False), ('old-suffix', '32MB', False)]
source = a.out / 'main.cj'
source.write_text('main(): Int64 {\n    println("SOFT_CONFIG_MAIN_REACHED")\n    return 0\n}\n')
env = dict(os.environ)
for key in ('cjSoftMaxHeapSize', 'cjHeapSize'):
    env.pop(key, None)
product_env = dict(env, LD_LIBRARY_PATH=a.product_loader)
identity = {'compiler': hashlib.sha256(Path(a.compiler).read_bytes()).hexdigest(),
            'product': {str(Path(d)/f): hashlib.sha256((Path(d)/f).read_bytes()).hexdigest()
                        for d in a.product_loader.split(':') for f in ('libcangjie-runtime.so', 'libboundscheck.so')
                        if (Path(d)/f).is_file()}}
(a.out/'identity.json').write_text(json.dumps(identity, indent=2))
subprocess.run(['uptime'], stdout=(a.out/'uptime-before.txt').open('w'))
start = time.monotonic()

def run(case):
    name, value, accepted = case
    dest = a.out/name
    dest.mkdir(exist_ok=True)
    binary = dest/'main'
    cmd = [a.compiler, str(source), '--runtime-config=cjHeapSize=64MB', '-o', str(binary)]
    if value is not None:
        cmd.append('--runtime-config=cjSoftMaxHeapSize='+value)
    with (dest/'compile.log').open('w') as f:
        c = subprocess.run(cmd, env=env, stdout=f, stderr=subprocess.STDOUT, timeout=90)
    result = {'value': value, 'accepted': accepted, 'compile_rc': c.returncode, 'runs': []}
    if c.returncode == 0:
        result['elf_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
        for i in range(a.n):
            r = subprocess.run(['timeout', '30', str(binary)], env=product_env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            (dest/f'run-{i}.log').write_text(r.stdout)
            reached = 'SOFT_CONFIG_MAIN_REACHED' in r.stdout
            # A loader error/timeout is not evidence of runtime argument rejection.
            passed = (r.returncode == 0 and reached) if accepted else (
                r.returncode not in (0, 124, 126, 127) and not reached and
                ('Invalid cjSoftMaxHeapSize' in r.stdout or 'SoftMaxHeapSize' in r.stdout))
            result['runs'].append({'rc': r.returncode, 'main_reached': reached, 'passed': passed})
    result['passed'] = c.returncode == 0 and len(result['runs']) == a.n and all(r['passed'] for r in result['runs'])
    (dest/'result.json').write_text(json.dumps(result, indent=2))
    print('SOFT_TRANSPORT_ASSERT', name, json.dumps(result), flush=True)
    return name, result

with concurrent.futures.ThreadPoolExecutor(max_workers=len(cases)) as pool:
    results = dict(pool.map(run, cases))
(a.out/'result.json').write_text(json.dumps(results, indent=2))
(a.out/'wall.txt').write_text(f'wall={time.monotonic()-start} parallel_cases={len(cases)}\n')
subprocess.run(['uptime'], stdout=(a.out/'uptime-after.txt').open('w'))
raise SystemExit(int(any(not r['passed'] for r in results.values())))
