#!/usr/bin/env python3
"""Compile only the fixture and link existing release product archives."""
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
    parser.add_argument('--tree', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--compiler', type=Path)
    parser.add_argument('--dependencies', type=Path, help='Pin unchanged basic/utils artifacts across arms')
    parser.add_argument('--sigint', action='store_true')
    args = parser.parse_args()
    tree, sdk, out = (x.resolve() for x in (args.tree, args.sdk, args.out))
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(CANGJIE_HOME=str(sdk), TMPDIR=str(out), cjHeapSize='32GB')
    env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / x) for x in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    compiler = args.compiler or sdk / 'bin/cjc'
    source = tree / 'tests/temp_file_signal_safe/fixture.cj'
    elf = out / 'fixture'
    cmd = [str(compiler), str(source), '-O2', '--trimpath', str(tree), '--diagnostic-format=noColor', '-o', str(elf)]
    archives, inputs = [], [source, compiler]
    for package in ('basic', 'utils', 'option'):
        root = args.dependencies.resolve() if args.dependencies and package != 'option' else tree
        directory = root / 'target/release' / (package + '@cjcj')
        cmd += ['--import-path', str(directory), '-L', str(directory)]
        archives += sorted(directory.glob('*.a'))
        inputs += sorted(directory.glob('*.cjo'))
    cmd += ['--link-options=--start-group ' + ' '.join(map(str, archives)) + ' --end-group']
    inputs += archives + list((sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))
    inputs += [sdk / 'lib/linux_x86_64_cjnative/libcangjie-std-core.a']
    (out / 'inputs.sha256').write_text(''.join(f'{sha(p)}  {p}\n' for p in inputs))
    result = {'command': cmd, 'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True), 'tests': {}}
    start = time.monotonic()
    with (out / 'build.log').open('w') as log:
        result['build_rc'] = subprocess.call(cmd, cwd=tree, env=env, stdout=log, stderr=subprocess.STDOUT)
    result['build_wall'] = time.monotonic() - start
    rc = result['build_rc']
    if rc == 0:
        result['elf_sha256'] = sha(elf)
        with (out / 'symbols.txt').open('w') as log:
            result['nm_rc'] = subprocess.call(['nm', '--defined-only', str(elf)], stdout=log)
        for mode in (['sigint'] if args.sigint else ['direct', 'normal']):
            command = [str(elf), mode]
            manifest = out / 'registered-paths.txt'
            if mode == 'sigint':
                command += [str(manifest)]
            start = time.monotonic()
            with (out / (mode + '.log')).open('w') as log:
                actual_rc = subprocess.call(command, cwd=tree, env=env, stdout=log, stderr=subprocess.STDOUT)
            row = {'rc': actual_rc, 'wall': time.monotonic() - start}
            if mode == 'sigint':
                paths = manifest.read_text().splitlines() if manifest.exists() else []
                row['removed'] = {p: not Path(p).exists() for p in paths}
                row['pass'] = actual_rc == 130 and len(paths) == 2 and all(row['removed'].values())
            else:
                row['pass'] = actual_rc == 0 and 'TARGET: fileRemoved=true directoryRemoved=true' in (out / (mode + '.log')).read_text()
            result['tests'][mode] = row
            if not row['pass']:
                rc = 1
    result['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result['tests']))
    return rc


if __name__ == '__main__':
    raise SystemExit(main())
