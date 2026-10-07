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


def prepare(tree, sdk, out, producer=None, stub_imports=None):
    """Produce declaration inputs only; publish identity even on failure."""
    tree, sdk, out = (Path(p).resolve() for p in (tree, sdk, out))
    out.mkdir(parents=True, exist_ok=True)
    record = {'tree': str(tree), 'sdk': str(sdk), 'stubs': {},
              'phase': 'copy', 'rc': None, 'argv': None, 'logs': {}, 'error': None}
    try:
        if producer is None:
            products = [tree / 'target/release/bin' / n for n in ('cjcj::cjc', 'cjc@cjcj')]
            products = [p for p in products if p.is_file()]
            if len(products) != 1:
                raise ValueError('expected exactly one same-tree release compiler')
            producer = products[0]
        product = out / 'cjcj-stage1'
        if Path(producer).resolve() != product:
            shutil.copy2(producer, product)
        record['phase'] = 'input_identity'
        inputs = [product, sdk / 'bin/cjc', sdk / 'tools/bin/cjpm',
                  tree / 'runtime_shim/cjselfhost_llvmshim.o',
                  sdk / 'lib/linux_x86_64_cjnative/libcangjie-std-core.a',
                  sdk / 'third_party/llvm/lib/libLLVM-15.so']
        inputs += sorted((sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))
        sources = [tree / 'scripts/objc_regcomp_fixtures' / (n + '.cj') for n in ('internal', 'lang')]
        record['inputs'] = {str(p): digest(p) for p in inputs + sources}
        record['sdk_files'] = {str(p.relative_to(sdk)): digest(p)
                               for p in sorted(sdk.rglob('*')) if p.is_file()}
        record['source_sha'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=tree, text=True).strip()
        record['phase'] = 'copy_imports'
        imports = out / 'imports/objc'
        imports.mkdir(parents=True, exist_ok=True)
        env = os.environ.copy()
        env['CANGJIE_HOME'] = str(sdk)
        env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / p) for p in (
            'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
            'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
        if stub_imports is not None:
            shutil.copytree(Path(stub_imports).resolve(), out / 'imports', dirs_exist_ok=True)
        else:
            for name, source in zip(('internal', 'lang'), sources):
                argv = [str(product), str(source), '--import-path', str(out / 'imports'),
                        '--output-type=staticlib', '--output-dir', str(imports),
                        '-o', name + '.a', '--diagnostic-format=noColor']
                record.update(phase='execute', rc=None, argv=argv)
                log_path = out / (name + '.log')
                record['logs'][name] = str(log_path)
                with log_path.open('w') as log:
                    rc = subprocess.call(argv, cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT)
                record['rc'] = rc
                record['stubs'][name] = {'argv': argv, 'rc': rc, 'log': str(log_path)}
                if rc:
                    raise ValueError(f'{name} producer rc={rc}')
        record['phase'] = 'verify_products'
        for name in ('internal', 'lang'):
            for filename in ('objc.' + name + '.cjo', name + '.a'):
                if not (imports / filename).is_file():
                    raise ValueError('missing ' + filename)
        record['files'] = {str(p.relative_to(out / 'imports')): digest(p)
                           for p in sorted((out / 'imports').rglob('*')) if p.is_file()}
        record['imports'] = str(out / 'imports')
        record.update(phase='complete', rc=0)
        return record
    except Exception as error:
        record.update(error='ObjCPreamble fixture prerequisite: ' + str(error),
                      exception_type=type(error).__name__, exception_text=str(error))
        raise RuntimeError(record['error']) from error
    finally:
        (out / 'fixture.json').write_text(json.dumps(record, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-tree', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--interface-tree', type=Path,
                        help='use shared release declarations while linking build-tree product archives')
    parser.add_argument('--stub-imports', type=Path,
                        help='physically copy shared declaration fixture imports for differential arms')
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--producer', type=Path)
    args = parser.parse_args()
    tree, sdk, out = (p.resolve() for p in (args.build_tree, args.sdk, args.out))
    if args.prepare_only:
        prepare(tree, sdk, out, args.producer)
        return 0
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
        str(sdk / 'third_party/llvm/lib/libLLVM-15.so'), '-lstdc++'])]
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
        record['fixture'] = prepare(tree, sdk, out, producer=args.producer,
                                    stub_imports=args.stub_imports)
        record['elf_sha256'] = digest(executable)
        loader = subprocess.run(['ldd', str(executable)], cwd=tree, env=env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (out / 'loader.log').write_text(loader.stdout)
        record['loader_rc'] = loader.returncode
        record['loaded_product_libraries'] = {}
        for line in loader.stdout.splitlines():
            fields = line.split()
            if len(fields) >= 3 and fields[1] == '=>' and fields[0].startswith(
                    ('libLLVM-', 'libcangjie-runtime', 'libboundscheck')):
                library = Path(fields[2])
                record['loaded_product_libraries'][fields[0]] = {
                    'path': str(library), 'sha256': digest(library) if library.is_file() else None}
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
