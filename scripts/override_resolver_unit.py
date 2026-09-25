#!/usr/bin/env python3
"""Link the resolver tests to existing release compiler archives.

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
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--integration-only', action='store_true')
    args = parser.parse_args()
    tree, sdk, out = (p.resolve() for p in (args.build_tree, args.sdk, args.out))
    out.mkdir(parents=True, exist_ok=True)
    temporary = out / 'tmp'
    temporary.mkdir(exist_ok=True)
    env = os.environ.copy()
    env['CANGJIE_HOME'] = str(sdk)
    env['TMPDIR'] = str(temporary)
    env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / p) for p in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    names = ['ResolverTestSupport_test.cj', 'GIMResolverIntegration_test.cj']
    if not args.integration_only:
        names.append('OverrideFunctionResolver_test.cj')
    sources = [tree / 'packages/sema/src/resolver_tests' / name for name in names]
    executable = out / 'resolver-tests'
    command = [str(sdk / 'bin/cjc'), '--test', '-O0', '--diagnostic-format=noColor', '--trimpath', str(tree),
               *map(str, sources), '-o', str(executable)]
    archives, inputs = [], list(sources)
    for directory in sorted((tree / 'target/release').iterdir()):
        if not directory.is_dir() or directory.name == 'bin':
            continue
        command += ['--import-path', str(directory), '-L', str(directory)]
        archives += sorted(directory.glob('*.a'))
        inputs += sorted(directory.glob('*.cjo'))
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
