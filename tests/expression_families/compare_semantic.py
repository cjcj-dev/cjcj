#!/usr/bin/env python3
"""Compile real source packages to objects and compare every emitted object byte."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compile_case(exe, source, output, imports, jobs, optimization):
    output.mkdir(parents=True, exist_ok=True)
    (output / "temps").mkdir(exist_ok=True)
    command = [str(exe)]
    command += ['-p', str(source)] if source.is_dir() else [str(source)]
    command += ['--experimental', '--output-type=obj', '--compile-target', 'staticlib', '-' + optimization, '--jobs', str(jobs), '--dump-ir',
                '--trimpath', str(output), '--save-temps', str(output / 'temps'),
                '-o', str(output / 'output.o')]
    for directory in imports:
        command += ['--import-path', str(directory)]
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    with (output / 'compile.log').open('w') as log:
        try:
            run = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=3600)
            rc = run.returncode
        except subprocess.TimeoutExpired:
            rc = 124
    result = {'command': command, 'rc': rc, 'wall': time.monotonic() - start,
              'uptime_before': before, 'uptime_after': subprocess.check_output(['uptime'], text=True).strip(),
              'objects': {}, 'llvm_ir': {}}
    for file in output.rglob('*.o'):
        result['objects'][str(file.relative_to(output))] = sha(file)
    for file in output.rglob('*.ll'):
        result['llvm_ir'][str(file.relative_to(output))] = sha(file)
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--source-root', type=Path, required=True)
    p.add_argument('--imports-root', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--jobs', type=int, default=os.cpu_count())
    p.add_argument('--workers', type=int, default=2)
    p.add_argument('--fixture-only', action='store_true')
    p.add_argument('--optimization', choices=('O0', 'O2'), default='O0')
    args = p.parse_args()
    imports = [args.imports_root] + sorted(args.imports_root.glob('*@cjcj'))
    sources = [] if args.fixture_only else [root / 'src' for root in sorted((args.source_root / 'packages').iterdir())
                                           if (root / 'cjpm.toml').exists() and root.name != 'cjc']
    fixtures = [Path(__file__).with_name(name + '.cj') for name in ('class_cast', 'numeric_cast', 'control')]
    args.out.mkdir(parents=True, exist_ok=True)
    cases = [{'source': str(source)} for source in fixtures + sources]
    manifest = {'compilers': {name: {'path': str(exe), 'sha256': sha(exe)} for name, exe in
                             [('baseline', args.baseline), ('candidate', args.candidate)]},
                'affinity': sorted(os.sched_getaffinity(0)), 'jobs': args.jobs,
                'parallel_compilers': args.workers, 'optimization': args.optimization, 'cases': cases}
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        pending = {}
        for index, source in enumerate(fixtures + sources):
            for name, exe in [('baseline', args.baseline), ('candidate', args.candidate)]:
                pending[pool.submit(compile_case, exe, source, args.out / str(index) / name,
                                    imports, args.jobs, args.optimization)] = (index, name)
        for future in concurrent.futures.as_completed(pending):
            index, name = pending[future]
            case = cases[index]
            try:
                case[name] = future.result()
            except Exception as error:
                case[name] = {'rc': -1, 'error': str(error), 'objects': {}, 'llvm_ir': {}}
            if 'baseline' in case and 'candidate' in case:
                case['same_object_bytes'] = (case['baseline']['rc'] == case['candidate']['rc'] == 0
                    and bool(case['baseline']['objects'])
                    and case['baseline']['objects'] == case['candidate']['objects'])
                print(f"OBJECT_BYTES {case['source']} same={case['same_object_bytes']} rc={case['baseline']['rc']}/{case['candidate']['rc']}", flush=True)
            (args.out / 'result.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return 0 if all(case['same_object_bytes'] for case in cases) else 1


if __name__ == '__main__':
    raise SystemExit(main())
