#!/usr/bin/env python3
"""Compile a real input once, then inspect the compiler's object DWARF."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha(path):
    with path.open('rb') as stream:
        digest = hashlib.sha256()
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
        return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source', type=Path, default=Path(__file__).with_name('arrays.cj'))
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--jobs', type=int, required=True)
    args = parser.parse_args()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, LC_ALL='C', cjHeapSize='32GB')
    result = {'compiler': str(args.compiler), 'compiler_sha256': sha(args.compiler),
              'source': str(args.source.resolve()), 'jobs': args.jobs,
              'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True),
              'ld_library_path': env.get('LD_LIBRARY_PATH', ''),
              'cangjie_home': env.get('CANGJIE_HOME', ''),
              'checker_sha256': sha(Path(__file__).with_name('check.py'))}
    result['libraries'] = {}
    for directory in result['ld_library_path'].split(':'):
        for name in ('libcangjie-runtime.so', 'libboundscheck.so', 'libLLVM-15.so'):
            path = Path(directory) / name
            if directory and path.is_file() and name not in result['libraries']:
                result['libraries'][name] = {'path': str(path), 'sha256': sha(path)}
    archive = args.out / 'result.a'
    source_args = ['-p', str(args.source.resolve())] if args.source.is_dir() else [str(args.source.resolve())]
    command = [str(args.compiler.resolve()), *source_args, '--no-sub-pkg', '-g',
               '--apc=1', '--output-type=staticlib', '-O2', '-j' + str(args.jobs), '-o', str(archive)]
    result['command'] = command
    start = time.monotonic()
    rc = 0
    try:
        with (args.out / 'compile.log').open('w') as log:
            rc = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT,
                                timeout=900).returncode
        result['compile_rc'] = rc
        if rc == 0:
            result['archive_sha256'] = sha(archive)
            with (args.out / 'debug.txt').open('w') as log:
                rc = subprocess.run(['readelf', '--debug-dump=info', str(archive)], env=env,
                                    stdout=log, stderr=subprocess.STDOUT).returncode
            result['readelf_rc'] = rc
        if rc == 0:
            with (args.out / 'check.log').open('w') as log:
                rc = subprocess.run(['python3', str(Path(__file__).with_name('check.py')),
                                     str(args.out / 'debug.txt'), '--json', str(args.out / 'checks.json')],
                                    stdout=log, stderr=subprocess.STDOUT).returncode
            result['check_rc'] = rc
    except subprocess.TimeoutExpired:
        result['timeout'] = True
        rc = 124
    finally:
        result['rc'] = rc
        result['wall'] = time.monotonic() - start
        result['uptime_after'] = subprocess.check_output(['uptime'], text=True)
        (args.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, sort_keys=True))
    return rc


if __name__ == '__main__':
    raise SystemExit(main())
