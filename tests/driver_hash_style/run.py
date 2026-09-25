#!/usr/bin/env python3
"""Link the hash-style assertions against a built, unmodified driver package.

Usage: run.py --tree <cjpm workspace> --sdk <matching host SDK> --out <evidence>
The SDK must match the workspace archives' compiler/runtime ABI.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('tree', 'sdk', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    tree, sdk, out = (p.resolve() for p in (args.tree, args.sdk, args.out))
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CANGJIE_HOME=str(sdk))
    env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / p) for p in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    imports = sorted((tree / 'target/release').glob('*@cjcj'))
    archives = sorted((tree / 'target/release').rglob('lib*@cjcj.a'))
    source = Path(__file__).with_name('main.cj').resolve()
    executable = out / 'hash-style-test'
    command = [str(sdk / 'bin/cjc'), str(source), '-o', str(executable)]
    for directory in imports:
        command += ['--import-path', str(directory)]
    command += [str(p) for p in archives]
    command += [str(tree / 'runtime_shim/cjselfhost_llvmshim.o'),
                str(sdk / 'third_party/llvm/lib/libLLVM-15.so'), '-lstdc++']
    result = {'command': command, 'source_sha256': sha(source),
              'archives': {str(p): sha(p) for p in archives},
              'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True)}
    start = time.monotonic()
    with (out / 'build.log').open('w') as log:
        result['build_rc'] = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT).returncode
    result['build_wall'] = time.monotonic() - start
    if result['build_rc'] == 0:
        result['elf_sha256'] = sha(executable)
        run = subprocess.run([str(executable), str(sdk)], cwd=out, env=env,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        result['run_rc'] = run.returncode
        (out / 'run.log').write_text(run.stdout)
        print(run.stdout, end='')
    result['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return result.get('run_rc', result['build_rc'])


if __name__ == '__main__':
    raise SystemExit(main())
