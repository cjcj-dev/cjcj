#!/usr/bin/env python3
"""Check ObjC file preambles through the release CompilerInstance frontend.

Build the tree with cjpm build first. Only the test source is compiled here;
all product code is linked from those release archives. Declaration fixtures
stand in for objc.internal/objc.lang, so this does not test a Darwin runtime.
"""
import argparse
import hashlib
import json
import os
import shutil
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
    parser.add_argument('--interface-tree', type=Path,
                        help='use shared release declarations while linking build-tree product archives')
    parser.add_argument('--stub-imports', type=Path,
                        help='physically copy shared declaration fixture imports for differential arms')
    args = parser.parse_args()
    tree, sdk, out = (p.resolve() for p in (args.build_tree, args.sdk, args.out))
    interfaces = args.interface_tree.resolve() if args.interface_tree else tree
    out.mkdir(parents=True, exist_ok=True)
    temporary = out / 'tmp'
    temporary.mkdir(exist_ok=True)
    env = os.environ.copy()
    env['CANGJIE_HOME'] = str(sdk)
    env['TMPDIR'] = str(temporary)
    env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / p) for p in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    env['OBJC_PREAMBLE_IMPORTS'] = str(out / 'imports')
    sources = [tree / 'packages/compiler_unittest/src' / name for name in (
        'ObjCPreamble_test.cj',)]
    executable = out / 'objc-preamble-tests'
    command = [str(sdk / 'bin/cjc'), '--test', '-O0', '--diagnostic-format=noColor', '--trimpath', str(tree),
               *map(str, sources), '-o', str(executable)]
    archives, inputs = [], list(sources)
    for directory in sorted((tree / 'target/release').iterdir()):
        if not directory.is_dir() or directory.name in ('bin', 'compiler_unittest@cjcj'):
            continue
        interface_directory = interfaces / 'target/release' / directory.name
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
    record = {'command': command, 'interface_tree': str(interfaces), 'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True).strip()}
    start = time.monotonic()
    with (out / 'build.log').open('w') as log:
        record['build_rc'] = subprocess.call(command, cwd=tree, env=env, stdout=log, stderr=subprocess.STDOUT)
    record['build_wall'] = time.monotonic() - start
    if record['build_rc'] == 0:
        imports = out / 'imports/objc'
        imports.mkdir(parents=True, exist_ok=True)
        compiler = tree / 'target/release/bin/cjcj::cjc'
        # Preserve the product basename required by its runtime entry selection.
        product = out / 'cjcj-stage1'
        shutil.copy2(compiler, product)
        record['compiler_sha256'] = digest(product)
        record['stubs'] = {}
        if args.stub_imports is not None:
            origin = args.stub_imports.resolve()
            shutil.copytree(origin, out / 'imports', dirs_exist_ok=True)
            record['stub_origin'] = str(origin)
        else:
            for name in ('internal', 'lang'):
                stub = tree / 'scripts/objc_regcomp_fixtures' / (name + '.cj')
                argv = [str(product), str(stub), '--import-path', str(out / 'imports'),
                        '--output-type=staticlib', '--output-dir', str(imports),
                        '-o', name + '.a', '--diagnostic-format=noColor']
                with (out / (name + '.log')).open('w') as log:
                    rc = subprocess.call(argv, cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT)
                record['stubs'][name] = {'argv': argv, 'rc': rc}
                if rc:
                    (out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
                    return rc
        record['stub_sha256'] = {
            str(p.relative_to(out / 'imports')): digest(p)
            for p in sorted((out / 'imports').rglob('*')) if p.is_file()
        }
        record['elf_sha256'] = digest(executable)
        start = time.monotonic()
        with (out / 'test.log').open('w') as log:
            record['test_rc'] = subprocess.call([str(executable), '--no-color', '--show-all-output',
                                                '--no-progress'], cwd=tree, env=env,
                                               stdout=log, stderr=subprocess.STDOUT)
        record['test_wall'] = time.monotonic() - start
        # Keep frontend failures visible. File observations also cover output
        # written before a later, unrelated frontend error (for example #273).
        expected = (b'/*\n * NOTE: This file is auto-generated by cjc.\n'
                    b' * Do NOT modify it manually.\n */\n')
        record['generated_files'] = {
            str(p.relative_to(out)): {'sha256': digest(p), 'preamble': p.read_bytes().startswith(expected)}
            for p in sorted(temporary.glob('objc-preamble-*/generated/*')) if p.is_file()
        }
        for name, observation in record['generated_files'].items():
            print(f"OBJC_PREAMBLE_OUTPUT file={name} preamble={observation['preamble']}", flush=True)
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True).strip()
    (out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record.get('test_rc', record['build_rc'])


if __name__ == '__main__':
    raise SystemExit(main())
