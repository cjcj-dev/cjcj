#!/usr/bin/env python3
"""Link the static dispatch tests to existing release compiler archives.

No product sources are recompiled. This avoids the dependency export-for-test
failure tracked by cjcj#256. Build the supplied tree with cjpm build first.
"""
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
    parser.add_argument('--build-tree', type=Path, required=True)
    parser.add_argument('--release-dir', type=Path, help='Shared build release artifacts')
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--interface-tree', type=Path,
                        help="Reuse one CJO interface snapshot while linking each arm's product archives")
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--source-dir', type=Path, help='Common test source snapshot for every arm')
    args = parser.parse_args()
    tree, sdk, out = (p.resolve() for p in (args.build_tree, args.sdk, args.out))
    release = (args.release_dir or tree / 'target/release').resolve()
    interfaces = args.interface_tree.resolve() / 'target/release' if args.interface_tree else release
    out.mkdir(parents=True, exist_ok=True)
    temporary = out / 'tmp'
    temporary.mkdir(exist_ok=True)
    env = os.environ.copy()
    env['CANGJIE_HOME'] = str(sdk)
    env['TMPDIR'] = str(temporary)
    env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / p) for p in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    source_dir = args.source_dir or tree / 'packages/chir/src/devirtualization_tests'
    sources = sorted(source_dir.glob('*_test.cj'))
    executable = out / 'static-dispatch-tests'
    command = [str(sdk / 'bin/cjc'), '--test', '-O0', '--diagnostic-format=noColor', '--trimpath', str(tree),
               *map(str, sources), '-o', str(executable)]
    archives, inputs = [], list(sources) + [Path(__file__).resolve()]
    for directory in sorted(release.iterdir()):
        if not directory.is_dir() or directory.name in ('bin', 'compiler_unittest@cjcj', 'devirtualization_tests@chir@cjcj'):
            continue
        interface_directory = interfaces / directory.name
        command += ['--import-path', str(interface_directory), '-L', str(directory)]
        archives += sorted(directory.glob('*.a'))
        inputs += sorted(interface_directory.glob('*.cjo'))
    shim = tree / 'runtime_shim/cjselfhost_llvmshim.o'
    command += ['--link-options=' + ' '.join([
        '--start-group', *map(str, archives), '--end-group', str(shim),
        '-L' + str(sdk / 'third_party/llvm/lib'), '-lLLVM-15', '-lstdc++'])]
    inputs += archives + [shim, sdk / 'bin/cjc', sdk / 'third_party/llvm/lib/libLLVM-15.so']
    inputs += sorted((sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))
    inputs += [sdk / 'lib/linux_x86_64_cjnative/libcangjie-std-core.a']
    (out / 'inputs.sha256').write_text(''.join(f'{digest(p)}  {p}\n' for p in inputs))
    record = {'command': command, 'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True).strip()}
    start = time.monotonic()
    with (out / 'build.log').open('w') as log:
        record['build_rc'] = subprocess.call(command, cwd=tree, env=env, stdout=log, stderr=subprocess.STDOUT)
    record['build_wall'] = time.monotonic() - start
    if record['build_rc'] == 0:
        record['elf_sha256'] = digest(executable)
        start = time.monotonic()
        with (out / 'test.log').open('w') as log:
            record['test_rc'] = subprocess.call([str(executable), '--no-color', '--show-all-output',
                                                '--no-progress'], cwd=tree, env=env,
                                               stdout=log, stderr=subprocess.STDOUT)
        record['test_wall'] = time.monotonic() - start
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True).strip()
    (out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record.get('test_rc', record['build_rc'])


if __name__ == '__main__':
    raise SystemExit(main())
