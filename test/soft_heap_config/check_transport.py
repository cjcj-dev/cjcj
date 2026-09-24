#!/usr/bin/env python3
"""Check actual compiler IR text transport, independently of VM startup.

This is a producer-only check. Until cjcj#115 supplies the product entry,
linking may fail with that exact missing symbol; no startup claim is made.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('--compiler', required=True)
p.add_argument('--llvm-dis', required=True)
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
source = a.out/'main.cj'
source.write_text('main(): Int64 { return 0 }\n')
cases = [('valid', '32M'), ('over-max', '128M'), ('leading', ' 32M'),
         ('trailing', '32M '), ('internal', '32 M'), ('decimal', '010')]
(a.out/'compiler.sha256').write_text(hashlib.sha256(Path(a.compiler).read_bytes()).hexdigest()+'\n')
subprocess.run(['uptime'], stdout=(a.out/'uptime-before.txt').open('w'))
start = time.monotonic()

def run(case):
    name, value = case
    dest = a.out/name
    dest.mkdir(exist_ok=True)
    cmd = [a.compiler, str(source), '--runtime-config=cjSoftMaxHeapSize='+value,
           '--save-temps', str(dest), '-o', str(dest/'main')]
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=90)
    (dest/'compile.log').write_text(r.stdout)
    observations = []
    hashes = {}
    for bc in sorted(dest.glob('*.bc')):
        if '.opt.' in bc.name:
            continue
        dis = subprocess.run([a.llvm_dis, str(bc), '-o', '-'], capture_output=True, text=True)
        if dis.returncode:
            raise RuntimeError(dis.stderr)
        values = re.findall(r'^@\.cjcj\.runtime\.config\.value\.0 = .*? c"(.*?)",', dis.stdout, re.M)
        if values:
            (dest/(bc.stem+'.ll')).write_text(dis.stdout)
            observations.extend(values)
            hashes[bc.name] = hashlib.sha256(bc.read_bytes()).hexdigest()
    link_known = r.returncode == 0 or (r.returncode == 1 and
        'undefined reference to `CJ_MRT_CjRuntimeInitWithConfigV1' in r.stdout)
    passed = link_known and observations == [value+'\\00']
    result = dict(input=value, observed=observations, compile_rc=r.returncode,
                  product_bitcode_sha256=hashes, passed=passed)
    print('OPTION_TEXT_ASSERT', name, json.dumps(result), flush=True)
    return name, result

with concurrent.futures.ThreadPoolExecutor(max_workers=len(cases)) as pool:
    results = dict(pool.map(run, cases))
(a.out/'result.json').write_text(json.dumps(results, indent=2))
(a.out/'wall.txt').write_text(f'wall={time.monotonic()-start} parallel_cases={len(cases)}\n')
subprocess.run(['uptime'], stdout=(a.out/'uptime-after.txt').open('w'))
raise SystemExit(int(any(not r['passed'] for r in results.values())))
