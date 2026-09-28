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


def run(command, log, env=None):
    with log.open('w') as out:
        try:
            return subprocess.run(command, stdout=out, stderr=subprocess.STDOUT,
                                  timeout=300, env=env).returncode
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
                        'rc': rc, 'log': str(log),
                        'gep_type_rejected': 'Explicit gep type does not match pointee type' in log.read_text()})
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


def value_case(args):
    out = args.out / 'value-debug'
    out.mkdir()
    source = Path(__file__).resolve().with_name('value.cj')
    executable = out / 'value'
    command = [str(args.compiler), str(source), '-g', '-O0', '-j' + str(args.jobs),
               '-o', str(executable)]
    result = {'command': command, 'compile_rc': run(command, out / 'compile.log'),
              'source_sha256': sha(source), 'run_rc': None}
    if result['compile_rc'] == 0 and executable.is_file():
        result['elf_sha256'] = sha(executable)
        env = dict(os.environ, LD_LIBRARY_PATH=str(args.runtime_dir))
        result['runtime_sha256'] = sha(args.runtime_dir / 'libcangjie-runtime.so')
        result['boundscheck_sha256'] = sha(args.runtime_dir / 'libboundscheck.so')
        result['run_rc'] = run([str(executable)], out / 'run.log', env=env)
        result['value_assertion_executed'] = 'ASSERT generic_struct_value=' in (out / 'run.log').read_text()
        result['passed'] = result['run_rc'] == 0 and (
            'ASSERT generic_struct_value=PASS value=305419896' in (out / 'run.log').read_text())
    else:
        result['passed'] = False
        result['value_assertion_executed'] = False
    # A failed compile is NOT a runtime-value red arm. Keep that distinction explicit.
    result['status'] = ('PASS' if result['passed'] else 'FAIL') if result['run_rc'] is not None else 'NOT_RUN'
    print('ASSERT generic_struct_value=' + result['status'], flush=True)
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--opt', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--runtime-dir', type=Path, help='Matching target runtime/std directory for value execution')
    parser.add_argument('--workers', type=int, default=4)
    parser.add_argument('--jobs', type=int, default=os.cpu_count())
    args = parser.parse_args()
    args.compiler = args.compiler.absolute()
    args.opt = args.opt.absolute()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    record = {'compiler': str(args.compiler), 'compiler_sha256': sha(args.compiler),
              'opt': str(args.opt), 'opt_sha256': sha(args.opt),
              'runner_sha256': sha(Path(__file__)), 'jobs': args.jobs, 'parallel_cases': args.workers,
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
    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        tasks = [pool.submit(case, args, Path(__file__).resolve().with_name(name + '.cj'), debug)
                 for name in ('offset', 'control') for debug in (False, True)]
        record['cases'] = [task.result() for task in tasks]
    if args.runtime_dir:
        args.runtime_dir = args.runtime_dir.resolve()
        record['value'] = value_case(args)
    record['wall'] = time.monotonic() - start
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    record['rc'] = int(not all(all(c['checks'].values()) for c in record['cases']) or
                       not record.get('value', {'passed': True})['passed'])
    (args.out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record['rc']


if __name__ == '__main__':
    raise SystemExit(main())
