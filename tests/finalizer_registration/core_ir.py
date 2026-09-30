#!/usr/bin/env python3
"""Exercise the product frontend entry on a complete, pinned core package."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

from run import digest, linked_libraries


def compile_case(compiler, core, directory, optimization):
    directory.mkdir(parents=True)
    command = [str(compiler), '-p', str(core), '--no-prelude', '--experimental',
               '--output-type=staticlib', '-' + optimization, '--jobs', str(os.cpu_count()),
               '--dump-ir', '-o', str(directory / 'result.bc')]
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    with (directory / 'run.log').open('w') as log:
        try:
            rc = subprocess.run(['strace', '-f', '-e', 'execve', '-o', str(directory / 'entry.trace')]
                                + command, stdout=log, stderr=subprocess.STDOUT,
                                timeout=900).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    result = {'command': command, 'rc': rc, 'optimization': optimization,
              'wall': time.monotonic() - start, 'uptime_before': before,
              'uptime_after': subprocess.check_output(['uptime'], text=True).strip(),
              'compiler_sha256': digest(compiler), 'directory': str(directory),
              'artifacts': {str(path): digest(path) for path in directory.rglob('*')
                            if path.is_file() and path.suffix in ('.ll', '.bc')}}
    (directory / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'FRONTEND {directory.parent.name}/{optimization} rc={rc}', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', action='append', required=True)
    parser.add_argument('--core', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    jobs = []
    identities = {}
    for entry in args.compiler:
        label, source = entry.split('=', 1)
        directory = args.out / label
        (directory / 'bin').mkdir(parents=True)
        compiler = directory / 'bin/cjc-frontend'
        shutil.copy2(source, compiler)
        linkage_rc, libraries = linked_libraries(compiler)
        identities[label] = {'source': source, 'source_sha256': digest(Path(source)),
                             'frontend_sha256': digest(compiler), 'ldd_rc': linkage_rc,
                             'libraries': libraries}
        for optimization in ('O0', 'O2'):
            jobs.append((compiler, args.core, directory / optimization, optimization))
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda values: compile_case(*values), jobs))
    (args.out / 'result.json').write_text(json.dumps({
        'identities': identities, 'jobs': os.cpu_count(), 'parallel_compilers': 4,
        'sources': {str(path.relative_to(args.core)): digest(path) for path in args.core.rglob('*.cj')},
        'affinity': sorted(os.sched_getaffinity(0)), 'cases': results}, indent=2) + '\n')
    return 0 if all(case['rc'] == 0 for case in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
