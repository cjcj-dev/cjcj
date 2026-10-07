#!/usr/bin/env python3
"""Collect CHIR and IR from the real compiler on identical finalizer inputs."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def linked_libraries(compiler):
    linkage = subprocess.run(['ldd', str(compiler)], capture_output=True, text=True)
    libraries = {}
    for line in linkage.stdout.splitlines():
        fields = line.split()
        if len(fields) >= 3 and fields[1] == '=>' and fields[2].startswith('/'):
            library = Path(fields[2])
            libraries[str(library)] = digest(library)
    return linkage.returncode, libraries


def compile_case(compiler, source, destination, phase, optimization):
    destination.mkdir(parents=True)
    command = [str(compiler), str(source), '--no-prelude', '--experimental',
               '--output-type=staticlib', '-' + optimization, '--jobs', str(os.cpu_count())]
    if phase == 'ir':
        temps = destination / 'temps'
        temps.mkdir()
        command += ['--dump-ir', '--save-temps', str(temps), '-o', str(destination / 'result.a')]
    else:
        command += ['--emit-chir=' + phase, '--dump-chir', '-o', str(destination / 'output.chir')]
    before = subprocess.check_output(['uptime'], text=True).strip()
    started = time.monotonic()
    with (destination / 'compile.log').open('w') as log:
        try:
            rc = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                timeout=300).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    result = {'source': str(source), 'source_sha256': digest(source), 'command': command,
              'rc': rc, 'wall': time.monotonic() - started, 'phase': phase,
              'optimization': optimization, 'uptime_before': before,
              'uptime_after': subprocess.check_output(['uptime'], text=True).strip(),
              'log': str(destination / 'compile.log'),
              'artifacts': {str(path): digest(path) for path in destination.rglob('*')
                            if path.is_file() and path.suffix in ('.chir', '.chirtxt', '.bc', '.ll', '.a')}}
    (destination / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'{source.stem}/{phase}/{optimization} compiler_rc={rc}', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--phase', choices=('raw', 'opt', 'ir'), action='append')
    parser.add_argument('--optimization', choices=('O0', 'O2'), action='append')
    parser.add_argument('--source', type=Path, action='append')
    parser.add_argument('--workers', type=int, choices=range(1, 5), default=4)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    sources = args.source or sorted(Path(__file__).parent.glob('*.cj'))
    phases = args.phase or ['raw', 'opt']
    optimizations = args.optimization or ['O0', 'O2']
    linkage_rc, libraries = linked_libraries(args.compiler)
    summary = {'compiler': str(args.compiler), 'compiler_sha256': digest(args.compiler),
               'affinity': sorted(os.sched_getaffinity(0)), 'jobs': os.cpu_count(),
               'parallel_compilers': args.workers, 'libraries': libraries, 'ldd_rc': linkage_rc,
               'cases': []}
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(compile_case, args.compiler, source,
                               args.out / (source.stem + '-' + phase + '-' + optimization),
                               phase, optimization)
                   for source in sources for phase in phases for optimization in optimizations]
        summary['cases'] = [future.result() for future in futures]
    (args.out / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')
    return 0 if all(case['rc'] == 0 for case in summary['cases']) else 1


if __name__ == '__main__':
    raise SystemExit(main())
