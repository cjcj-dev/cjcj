#!/usr/bin/env python3
"""Link other-expression dispatch fixtures to existing product release archives.

No product sources are recompiled. This avoids the dependency export-for-test
failure tracked by cjcj#256. Build the supplied tree with cjpm build first.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
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
    sources = [Path(__file__).resolve().parent / 'checker.cj']
    executable = out / 'other-dispatch-checker'
    command = [str(sdk / 'bin/cjc'), '-O0', '--diagnostic-format=noColor', '--trimpath', str(tree),
               *map(str, sources), '-o', str(executable)]
    archives, inputs = [], list(sources)
    for directory in sorted((tree / 'target/release').iterdir()):
        if not directory.is_dir() or directory.name in ('bin', 'compiler_unittest@cjcj'):
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
        record['cases'] = {}
        diagnostics = {
            'constant': 'expect 1 operand(s), but there are 0 in fact.',
            'debug': 'expect 1 operand(s), but there are 0 in fact.',
            'tuple': 'expect at least 1 operand(s), but there are 0 in fact.',
            'field': 'expect 1 operand(s), but there are 0 in fact.',
            'field-by-name': 'you should convert this expression to `Field`.',
            'apply': 'expect at least 1 operand(s), but there are 0 in fact.',
            'invoke': 'expect at least 1 operand(s), but there are 0 in fact.',
            'invoke-static': 'expect at least 1 operand(s), but there are 0 in fact.',
            'instanceof': 'expect 1 operand(s), but there are 0 in fact.',
            'class-cast': '',
            'numeric-cast': '',
            'exception': 'Object&',
            'spawn': 'expect at least 1 operand(s), but there are 0 in fact.',
            'raw-allocate': 'expect 1 operand(s), but there are 0 in fact.',
            'raw-literal': 'expect at least 1 operand(s), but there are 0 in fact.',
            'raw-value': 'expect 3 operand(s), but there are 0 in fact.',
            'varray': 'VArray',
            'varray-builder': 'expect 3 operand(s), but there are 0 in fact.',
            'intrinsic': 'intrinsic kind must be valid.',
            'box': 'expect 1 operand(s), but there are 0 in fact.',
            'unbox': 'expect 1 operand(s), but there are 0 in fact.',
            'generic': 'expect 1 operand(s), but there are 0 in fact.',
            'concrete': 'expect 1 operand(s), but there are 0 in fact.',
            'instantiate': 'expect 1 operand(s), but there are 0 in fact.',
            'unbox-ref': 'expect 1 operand(s), but there are 0 in fact.',
            'rtti': 'expect 1 operand(s), but there are 0 in fact.',
            'rtti-static': 'Unit',
            'unknown': 'find unrecongnized ExprKind `INVALID.',
            'constant-good': '',
        }

        def run_case(item):
            mode, diagnostic = item
            start = time.monotonic()
            with (out / (mode + '.log')).open('w') as log:
                rc = subprocess.call([str(executable), mode], cwd=tree, env=env,
                                     stdout=log, stderr=subprocess.STDOUT)
            output = (out / (mode + '.log')).read_text()
            expected = 'true' if mode in ('class-cast', 'numeric-cast', 'unknown', 'constant-good') else 'false'
            target = f'TARGET mode={mode} observed={expected} expected={expected}'
            return mode, {
                'rc': rc, 'wall': time.monotonic() - start,
                'target_executed': f'TARGET mode={mode} ' in output,
                'target_bool': target in output,
                'target_diagnostic': diagnostic in output if diagnostic else 'chir checker error:' not in output,
            }
        with ThreadPoolExecutor(max_workers=min(len(diagnostics), len(os.sched_getaffinity(0)))) as pool:
            record['cases'] = dict(pool.map(run_case, diagnostics.items()))
        record['test_rc'] = int(any(c['rc'] != 0 or not c['target_executed'] or not c['target_bool'] or not c['target_diagnostic']
                                    for c in record['cases'].values()))
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True).strip()
    (out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record.get('test_rc', record['build_rc'])


if __name__ == '__main__':
    raise SystemExit(main())
