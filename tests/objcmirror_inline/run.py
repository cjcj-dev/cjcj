#!/usr/bin/env python3
"""Exercise the release FunctionInline pass; only the fixture is compiled here."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tree', type=Path, required=True)
    parser.add_argument('--dependencies', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    tree, deps, sdk, out = [p.resolve() for p in (args.tree, args.dependencies, args.sdk, args.out)]
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(CANGJIE_HOME=str(sdk), cjHeapSize='32GB', TMPDIR=str(out))
    env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / p) for p in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    source = Path(__file__).with_name('pass.cj').resolve()
    compiler = sdk / 'bin/cjc'
    elf = out / 'pass'
    command = [str(compiler), str(source), '-O1', '--trimpath', str(source.parent), '-o', str(elf)]
    inputs, archives = [source, compiler], []
    for directory in sorted((deps / 'target/release').glob('*@cjcj')):
        if directory.name == 'chir@cjcj':
            directory = tree / 'target/release/chir@cjcj'
        command += ['--import-path', str(directory), '-L', str(directory)]
        archives += sorted(directory.glob('*.a'))
        inputs += sorted(directory.glob('*.cjo'))
    extra = sorted((deps / 'runtime_shim').glob('*.o'))
    llvm = sdk / 'third_party/llvm/lib/libLLVM-15.so'
    command += ['--link-options=--start-group ' + ' '.join(map(str, archives + extra)) +
                ' --end-group ' + str(llvm) + ' -lstdc++ --export-dynamic']
    inputs += archives + extra + [llvm] + list((sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))
    result = {'command': command, 'inputs': {str(p): digest(p) for p in inputs},
              'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True)}
    start = time.monotonic()
    with (out / 'build.log').open('w') as log:
        rc = subprocess.call(command, env=env, stdout=log, stderr=subprocess.STDOUT)
    result.update(build_rc=rc, build_wall=time.monotonic() - start)
    if rc == 0:
        result['elf_sha256'] = digest(elf)
        with (out / 'symbols.txt').open('w') as log:
            result['nm_rc'] = subprocess.call(['nm', '--defined-only', str(elf)], stdout=log)
        start = time.monotonic()
        with (out / 'run.log').open('w') as log:
            rc = subprocess.call([str(elf)], env=env, stdout=log, stderr=subprocess.STDOUT)
        result.update(run_rc=rc, run_wall=time.monotonic() - start)
    result['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'build_rc={result["build_rc"]} run_rc={result.get("run_rc", "NOT_RUN")} evidence={out}')
    return rc


if __name__ == '__main__':
    raise SystemExit(main())
