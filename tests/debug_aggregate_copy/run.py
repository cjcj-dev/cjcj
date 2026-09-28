#!/usr/bin/env python3
"""Check real compiler-produced bitcode with the production LLVM reader."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command, log):
    with log.open('w') as out:
        try:
            return subprocess.run(command, stdout=out, stderr=subprocess.STDOUT,
                                  timeout=300).returncode
        except subprocess.TimeoutExpired:
            return 124


def case(args, source, debug):
    name = source.stem + ('-debug' if debug else '-plain')
    out = args.out / name
    temps = out / 'temps'
    temps.mkdir(parents=True)
    archive = out / 'result.a'
    command = [str(args.compiler), str(source), '--output-type=staticlib', '-O0',
               '--dump-ir', '--save-temps', str(temps), '-j' + str(args.jobs), '-o', str(archive)]
    if debug:
        command.append('-g')
    start = time.monotonic()
    compile_rc = run(command, out / 'compile.log')
    bitcodes = sorted(p for p in temps.glob('*.bc') if not p.name.endswith('.opt.bc'))
    readers = []
    for bc in bitcodes:
        log = out / (bc.stem + '.reader.log')
        reader_command = [str(args.opt), '-disable-verify', '-disable-output', str(bc)]
        rc = run(reader_command, log)
        readers.append({'file': str(bc), 'sha256': sha(bc), 'command': reader_command,
                        'rc': rc, 'log': str(log)})
    # Keep presence and the target assertion separate. Even after a driver error,
    # inspect every produced bitcode instead of masking the reader's result.
    checks = {'bitcode_produced': bool(bitcodes),
              'reader_accepts_product_bitcode': bool(readers) and all(r['rc'] == 0 for r in readers),
              'driver_completed': compile_rc == 0 and archive.is_file()}
    result = {'name': name, 'source_sha256': sha(source), 'command': command,
              'compile_rc': compile_rc, 'readers': readers, 'checks': checks,
              'archive_sha256': sha(archive) if archive.is_file() else None,
              'wall': time.monotonic() - start}
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    for assertion, ok in checks.items():
        print(f'ASSERT {name} {assertion}={"PASS" if ok else "FAIL"}', flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--opt', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=os.cpu_count())
    args = parser.parse_args()
    args.compiler = args.compiler.absolute()
    args.opt = args.opt.absolute()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    record = {'compiler': str(args.compiler), 'compiler_sha256': sha(args.compiler),
              'opt': str(args.opt), 'opt_sha256': sha(args.opt),
              'runner_sha256': sha(Path(__file__)), 'jobs': args.jobs, 'parallel_cases': 4,
              'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True),
              'environment': {k: os.environ.get(k, '') for k in
                              ('CANGJIE_HOME', 'LD_LIBRARY_PATH', 'cjHeapSize')}, 'libraries': {}}
    for directory in os.environ.get('LD_LIBRARY_PATH', '').split(':'):
        for name in ('libcangjie-runtime.so', 'libboundscheck.so', 'libLLVM-15.so'):
            path = Path(directory) / name
            if directory and path.is_file() and name not in record['libraries']:
                record['libraries'][name] = {'path': str(path), 'sha256': sha(path)}
    start = time.monotonic()
    with ThreadPoolExecutor(max_workers=4) as pool:
        tasks = [pool.submit(case, args, Path(__file__).resolve().with_name(name + '.cj'), debug)
                 for name in ('offset', 'control') for debug in (False, True)]
        record['cases'] = [task.result() for task in tasks]
    record['wall'] = time.monotonic() - start
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    record['rc'] = int(not all(all(c['checks'].values()) for c in record['cases']))
    (args.out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record['rc']


if __name__ == '__main__':
    raise SystemExit(main())
