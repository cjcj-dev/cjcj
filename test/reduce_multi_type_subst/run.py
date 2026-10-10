#!/usr/bin/env python3
"""Compile only the regression tests; link the supplied real product archives."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--release', type=Path, required=True)
p.add_argument('--sdk', type=Path, required=True)
p.add_argument('--reference-release', type=Path,
               help='Freeze interfaces and all archives except the mutated sema product archive')
p.add_argument('--source', type=Path, default=Path(__file__).with_name('main.cj'),
               help='Run the finite-cycle fixture in its own process')
p.add_argument('--out', type=Path, required=True)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
env = os.environ.copy()
env['CANGJIE_HOME'] = str(a.sdk)
env['LD_LIBRARY_PATH'] = ':'.join(str(a.sdk / d) for d in (
    'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
    'third_party/llvm/lib', 'tools/lib'))
env['TMPDIR'] = str(a.out / 'tmp')
Path(env['TMPDIR']).mkdir(exist_ok=True)
source = a.source.resolve()
elf = a.out / 'tests'
command = [str(a.sdk / 'bin/cjc'), '--test', '-O0', '--trimpath', str(source.parent),
           '--diagnostic-format=noColor', str(source), '-o', str(elf)]
archives = []
inputs = [source, Path(__file__).resolve(), a.sdk / 'bin/cjc']
reference = a.reference_release or a.release
for directory in sorted(reference.iterdir()):
    if not directory.is_dir() or directory.name == 'bin':
        continue
    command += ['--import-path', str(directory), '-L', str(directory)]
    for archive in sorted(directory.glob('*.a')):
        if archive.name == 'libsema@cjcj.a':
            archive = a.release / directory.name / archive.name
        archives.append(archive)
    inputs += sorted(directory.glob('*.cjo'))
command += ['--link-options=--start-group ' + ' '.join(map(str, archives)) + ' --end-group']
inputs += archives + sorted((a.sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))
inputs += [a.sdk / 'lib/linux_x86_64_cjnative/libcangjie-std-core.a']
(a.out / 'inputs.sha256').write_text(''.join(f'{sha(f)}  {f}\n' for f in inputs))
r = {'command': command, 'affinity': sorted(os.sched_getaffinity(0)),
     'uptime_before': subprocess.check_output(['uptime'], text=True).strip()}
t = time.monotonic()
with (a.out / 'build.log').open('w') as log:
    r['build_rc'] = subprocess.call(command, env=env, stdout=log, stderr=subprocess.STDOUT)
r['build_wall'] = time.monotonic() - t
if r['build_rc'] == 0:
    r['elf_sha256'] = sha(elf)
    with (a.out / 'symbols.txt').open('w') as log:
        subprocess.run(['nm', '--defined-only', str(elf)], stdout=log, check=True)
    t = time.monotonic()
    with (a.out / 'test.log').open('w') as log:
        try:
            r['test_rc'] = subprocess.call([str(elf), '--no-color', '--show-all-output', '--no-progress'],
                                      env=env, stdout=log, stderr=subprocess.STDOUT, timeout=120)
        except subprocess.TimeoutExpired:
            r['test_rc'] = 124
            r['test_status'] = 'NOT_TERMINATED'
    r['test_wall'] = time.monotonic() - t
r['uptime_after'] = subprocess.check_output(['uptime'], text=True).strip()
(a.out / 'result.json').write_text(json.dumps(r, indent=2) + '\n')
print(json.dumps({k: v for k, v in r.items() if k != 'command'}))
raise SystemExit(r.get('test_rc', r['build_rc']))
