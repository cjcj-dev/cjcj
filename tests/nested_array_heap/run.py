#!/usr/bin/env python3
"""Compile nested class-array literals with a bounded compiler heap (#144)."""
import argparse
import concurrent.futures
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
    parser.add_argument('--repeat', type=int, default=3)
    parser.add_argument('--heap', default='256MB')
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error('--repeat must be positive')
    compiler, sdk, out = (p.resolve() for p in (args.compiler, args.sdk, args.out))
    out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).resolve().parent
    env = os.environ.copy()
    env.update(CANGJIE_HOME=str(sdk), cjHeapSize=args.heap,
               LD_LIBRARY_PATH=':'.join(str(sdk / p) for p in (
                   'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
                   'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu',
               PATH=f'{sdk}/bin:{sdk}/tools/bin:{sdk}/third_party/llvm/bin:/usr/bin:/bin')
    env['TMPDIR'] = str(out / 'tmp')
    Path(env['TMPDIR']).mkdir(exist_ok=True)
    identity = {'compiler': str(compiler),
                'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
                'heap': args.heap, 'cpus': sorted(os.sched_getaffinity(0)),
                'inputs': {}}
    for p in [*sorted((sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so')),
              *sorted((sdk / 'lib/linux_x86_64_cjnative').glob('*.a')),
              sdk / 'third_party/llvm/bin/llc', sdk / 'third_party/llvm/bin/opt',
              fixtures / 'tiny.cj', fixtures / 'n174.cj']:
        identity['inputs'][str(p)] = hashlib.sha256(p.read_bytes()).hexdigest()
    (out / 'identity.json').write_text(json.dumps(identity, indent=2))
    (out / 'uptime-before').write_text(subprocess.check_output(['uptime'], text=True))

    def compile_case(case):
        name, iteration = case
        directory = out / f'{name}-{iteration}'
        directory.mkdir(exist_ok=True)
        artifact = directory / 'result.o'
        if artifact.exists():
            artifact.unlink()
        command = [str(compiler), '-O2', '-Woff', 'unused', '--experimental',
                   '--output-type=obj', str(fixtures / f'{name}.cj'), '-o', str(artifact)]
        start = time.monotonic()
        with (directory / 'compile.log').open('w') as log:
            try:
                rc = subprocess.run(command, cwd=directory, env=env, stdout=log,
                                    stderr=subprocess.STDOUT, timeout=180).returncode
            except subprocess.TimeoutExpired:
                rc = 124
        data = artifact.read_bytes() if artifact.exists() else b''
        # Both observations run even when compilation fails: no prerequisite
        # assertion hides the target completion invariant.
        checks = {'compiler_completed': rc == 0, 'elf_object_emitted': data[:4] == b'\x7fELF'}
        result = {'case': name, 'iteration': iteration, 'command': command, 'rc': rc,
                  'wall': time.monotonic() - start, 'checks': checks,
                  'object_sha256': hashlib.sha256(data).hexdigest() if data else None}
        (directory / 'result.json').write_text(json.dumps(result, indent=2))
        for check, passed in checks.items():
            print(f'{"PASS" if passed else "FAIL"} {name}[{iteration}].{check} rc={rc}', flush=True)
        return result

    cases = [(name, i) for name in ('tiny', 'n174') for i in range(1, args.repeat + 1)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results = list(pool.map(compile_case, cases))
    (out / 'results.json').write_text(json.dumps(results, indent=2))
    (out / 'uptime-after').write_text(subprocess.check_output(['uptime'], text=True))
    return 0 if all(all(result['checks'].values()) for result in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
