#!/usr/bin/env python3
"""Compile source fixtures through a retained product stage1 compiler."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=4)
    args = parser.parse_args()
    compiler, sdk, out = (p.resolve() for p in (args.compiler, args.sdk, args.out))
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CANGJIE_HOME=str(sdk), cjHeapSize='32GB')
    env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / p) for p in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    record = {'compiler': str(compiler), 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'sdk_inputs': {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                             for p in sorted((sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))},
              'fixture_workers': args.workers, 'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True).strip()}

    def compile(name):
        destination = out / name
        destination.mkdir(exist_ok=True)
        source = Path(__file__).resolve().parent / (name + '.cj')
        cmd = [str(compiler), str(source), '--emit-chir=raw', '--output-type=staticlib',
               '--jobs', str(os.cpu_count()),
               '--diagnostic-format=noColor', '-o', str(destination / 'output.chir')]
        start = time.monotonic()
        with (destination / 'compiler.log').open('w') as log:
            rc = subprocess.call(cmd, cwd=destination, env=env, stdout=log, stderr=subprocess.STDOUT)
        return name, {'command': cmd, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(), 'rc': rc, 'wall': time.monotonic() - start,
                      'outputs': {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in destination.glob('*.chir')}}

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        record['cases'] = dict(pool.map(compile, ('control', 'function', 'parent', 'nested', 'intersection')))
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True).strip()
    (out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return int(any(c['rc'] != 0 or not c['outputs'] for c in record['cases'].values()))


if __name__ == '__main__':
    raise SystemExit(main())
