#!/usr/bin/env python3
"""Compare CHIR bytes from two real compiler executables on identical inputs."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compile_input(compiler, source, destination, imports, jobs):
    destination.mkdir(parents=True, exist_ok=True)
    command = [str(compiler), str(source), '--emit-chir=raw', '--output-type=staticlib',
               '--dump-chir', '-o', str(destination / 'output.chir')]
    if jobs is not None:
        command.extend(['--jobs', str(jobs)])
    if source.is_dir():
        command.insert(1, '-p')
    for directory in imports:
        command.extend(['--import-path', str(directory)])
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    with (destination / 'compile.log').open('w') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=900)
    return {'command': command, 'rc': result.returncode, 'wall': time.monotonic() - start,
            'uptime_before': before, 'uptime_after': subprocess.check_output(['uptime'], text=True).strip(),
            'outputs': {str(p.relative_to(destination)): digest(p) for p in destination.rglob('*.chir')},
            'log': str(destination / 'compile.log')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--candidate', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--input', type=Path, action='append', required=True)
    parser.add_argument('--import-dir', type=Path, action='append', default=[])
    parser.add_argument('--jobs', type=int, help='compiler parallelism; #200 uses 1 to isolate #203')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    manifest = {'compilers': {name: {'path': str(path), 'sha256': digest(path)}
                             for name, path in [('baseline', args.baseline), ('candidate', args.candidate)]},
                'affinity': sorted(os.sched_getaffinity(0)), 'cases': []}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        for index, source in enumerate(args.input):
            case = {'source': str(source)}
            futures = {arm: pool.submit(compile_input, compiler, source,
                                       args.out / str(index) / arm, args.import_dir, args.jobs)
                       for arm, compiler in [('baseline', args.baseline), ('candidate', args.candidate)]}
            for arm, future in futures.items():
                case[arm] = future.result()
            case['same_bytes'] = (case['baseline']['rc'] == case['candidate']['rc'] == 0
                                  and bool(case['baseline']['outputs'])
                                  and case['baseline']['outputs'] == case['candidate']['outputs'])
            manifest['cases'].append(case)
            (args.out / 'result.json').write_text(json.dumps(manifest, indent=2) + '\n')
            print(f"{'PASS' if case['same_bytes'] else 'FAIL'} {source} "
                  f"rc={case['baseline']['rc']}/{case['candidate']['rc']}", flush=True)
    return 0 if all(c['same_bytes'] for c in manifest['cases']) else 1


if __name__ == '__main__':
    raise SystemExit(main())
