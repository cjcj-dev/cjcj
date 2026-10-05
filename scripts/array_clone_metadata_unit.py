#!/usr/bin/env python3
"""Link and run only ArrayCloneMetadataTest against fresh release archives."""
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
    parser.add_argument('--build-tree', required=True, type=Path)
    parser.add_argument('--sdk', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    tree, sdk, out = (p.resolve() for p in (args.build_tree, args.sdk, args.out))
    out.mkdir(parents=True, exist_ok=True)
    (out / 'tmp').mkdir(exist_ok=True)
    env = dict(os.environ, CANGJIE_HOME=str(sdk), TMPDIR=str(out / 'tmp'),
               ARRAY_CLONE_TEST_ROOT=str(out / 'source'), cjHeapSize='32GB')
    env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / p) for p in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    source = tree / 'packages/compiler_unittest/src/ArrayCloneMetadata_test.cj'
    elf = out / 'array-clone-tests'
    command = [str(sdk / 'bin/cjc'), '--test', '-O0', '--diagnostic-format=noColor',
               '--trimpath', str(tree), str(source), '-o', str(elf)]
    archives = []
    for directory in sorted((tree / 'target/release').iterdir()):
        if not directory.is_dir() or directory.name in ('bin', 'compiler_unittest@cjcj'):
            continue
        command += ['--import-path', str(directory), '-L', str(directory)]
        archives += sorted(directory.glob('*.a'))
    shim = tree / 'runtime_shim/cjselfhost_llvmshim.o'
    config = tree / 'runtime_shim/cjc_runtime_config.o'
    command += ['--link-options=' + ' '.join([
        '--start-group', *map(str, archives), '--end-group', str(shim), str(config),
        '-L' + str(sdk / 'third_party/llvm/lib'), '-lLLVM-15', '-lstdc++'])]
    record = {'command': command, 'archives': [str(p) for p in archives],
              'source_sha256': sha(source), 'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True).strip()}
    start = time.monotonic()
    with (out / 'link.log').open('w') as log:
        try:
            record['link_rc'] = subprocess.call(command, cwd=tree, env=env, stdout=log,
                                                stderr=subprocess.STDOUT, timeout=600)
        except subprocess.TimeoutExpired:
            record['link_rc'] = 124
    record['link_wall'] = time.monotonic() - start
    if record['link_rc'] == 0:
        record['elf_sha256'] = sha(elf)
        (out / 'elf.sha256').write_text(record['elf_sha256'] + '  ' + str(elf) + '\n')
        run = [str(elf), '--no-color', '--show-all-output', '--no-progress']
        record['run_command'] = run
        start = time.monotonic()
        with (out / 'test.log').open('w') as log:
            try:
                record['test_rc'] = subprocess.call(run, cwd=out, env=env, stdout=log,
                                                    stderr=subprocess.STDOUT, timeout=180)
            except subprocess.TimeoutExpired:
                record['test_rc'] = 124
        record['test_wall'] = time.monotonic() - start
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True).strip()
    (out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record.get('test_rc', record['link_rc'])


if __name__ == '__main__':
    raise SystemExit(main())
