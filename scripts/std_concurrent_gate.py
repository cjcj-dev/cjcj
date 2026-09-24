#!/usr/bin/env python3
"""Check real stage1 symbols and the stage1 build's product library APIs."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'test/std_concurrent'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def run(command, out, env=None):
    start = time.monotonic()
    result = subprocess.run([str(x) for x in command], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=300)
    out.with_suffix('.log').write_text(result.stdout)
    out.with_suffix('.json').write_text(json.dumps({
        'command': [str(x) for x in command], 'rc': result.returncode,
        'wall': time.monotonic() - start}, indent=2) + '\n')
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--products', required=True, type=Path,
                        help='unmodified stage1 build target/release directory')
    parser.add_argument('--host-sdk', required=True, type=Path)
    parser.add_argument('--shim', required=True, type=Path)
    parser.add_argument('--runtime-sdk', type=Path, help='alpha.06 SDK for real import/link/run checks')
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    checks = []
    identity = {'compiler': sha(args.compiler),
                'fixtures': {p.name: sha(p) for p in FIXTURES.glob('*.cj')},
                'archives': {str(p): sha(p) for p in args.products.glob('*/*.a')},
                'uptime_before': subprocess.check_output(['uptime'], text=True)}

    def check(name, ok, detail):
        checks.append({'name': name, 'pass': ok, 'detail': detail})
        print(f'{"PASS" if ok else "FAIL"} {name}: {detail}', flush=True)

    def compile_fixture(name):
        out = args.out / name
        out.mkdir(exist_ok=True)
        archive = out / (name + '.a')
        result = run([args.compiler, '-g', '--dump-ir', '--dump-to-screen',
                      '--output-type=staticlib', '-o', archive, FIXTURES / (name + '.cj')],
                     out / 'compile')
        symbols = ''
        if result.returncode == 0 and archive.is_file():
            identity[name + '_archive'] = sha(archive)
            nm = run(['nm', '--defined-only', archive], out / 'nm')
            if nm.returncode == 0:
                symbols = nm.stdout
        return name, result, symbols

    with ThreadPoolExecutor(max_workers=2) as pool:
        fixtures = list(pool.map(compile_fixture, ['concurrent', 'collection_concurrent']))
    for name, result, symbols in fixtures:
        code = 'cr' if name == 'concurrent' else 'bh'
        check(name + ':compile', result.returncode == 0 and bool(symbols),
              f'compiler_rc={result.returncode}; archive symbols={len(symbols)} bytes')
        # Check emitted values even on failure: prerequisites cannot hide target checks.
        probe = re.findall(r'\b(_CN\S*5probe\S*)', symbols)
        check(name + ':symbol', any(s.startswith('_CN' + code + '5probe') for s in probe),
              repr(probe))
        initializers = re.findall(r'\b(_CGF\S+)', symbols)
        check(name + ':file-init', any(s.startswith('_CGF' + code) for s in initializers),
              repr(initializers))
        check(name + ':compression', any('Y' in s for s in probe), repr(probe))

    # Link the very archives that produced stage1; never rebuild a component in the test.
    env = dict(os.environ)
    env['CANGJIE_HOME'] = str(args.host_sdk)
    env['LD_LIBRARY_PATH'] = ':'.join(str(args.host_sdk / p) for p in [
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib']) + ':/usr/lib/x86_64-linux-gnu'
    env['PATH'] = ':'.join(str(args.host_sdk / p) for p in ['bin', 'tools/bin', 'third_party/llvm/bin']) + ':/usr/bin:/bin'
    command = [args.host_sdk / 'bin/cjc', FIXTURES / 'registration.cj',
               '--import-path', args.products, '-o', args.out / 'registration']
    archives = ' '.join(str(p) for p in sorted(args.products.glob('*/*.a')))
    command += ['--link-options', f'--start-group {archives} --end-group {args.shim} {args.host_sdk}/third_party/llvm/lib/libLLVM-15.so -lstdc++']
    compiled = run(command, args.out / 'registration-compile', env)
    check('registration:compile', compiled.returncode == 0, f'rc={compiled.returncode}')
    if compiled.returncode == 0:
        identity['registration_elf'] = sha(args.out / 'registration')
        tested = run([args.out / 'registration'], args.out / 'registration-run', env)
        print(tested.stdout, end='', flush=True)
        lines = [s for s in tested.stdout.splitlines() if s.startswith(('PASS ', 'FAIL '))]
        for line in lines:
            state, name, detail = line.split(' ', 2)
            checks.append({'name': name, 'pass': state == 'PASS', 'detail': detail})
        check('registration:completed', len(lines) == 26 and tested.returncode in (0, 1),
              f'rc={tested.returncode}; assertions={len(lines)}')
    if args.runtime_sdk:
        sdk = args.runtime_sdk
        target_env = dict(os.environ)
        target_env['CANGJIE_HOME'] = str(sdk)
        runtime_env = dict(target_env)
        runtime_env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / p) for p in [
            'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
            'third_party/llvm/lib', 'tools/lib']) + ':/usr/lib/x86_64-linux-gnu'
        identity['target_runtime'] = {str(p): sha(p) for p in (sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so')}
        for name in ['import_concurrent', 'import_control']:
            binary = args.out / name
            linked = run([args.compiler, '-V', FIXTURES / (name + '.cj'), '-o', binary],
                         args.out / (name + '-compile'), target_env)
            check(name + ':link', linked.returncode == 0, f'rc={linked.returncode}')
            if linked.returncode == 0:
                identity[name + '_elf'] = sha(binary)
                executed = run([binary], args.out / (name + '-run'), runtime_env)
                expected = 'concurrent-result=42' if name == 'import_concurrent' else 'control-result=42'
                check(name + ':run', executed.returncode == 0 and expected in executed.stdout,
                      f'rc={executed.returncode}; {executed.stdout.strip()}')
    identity['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (args.out / 'identity.json').write_text(json.dumps(identity, indent=2) + '\n')
    (args.out / 'checks.json').write_text(json.dumps(checks, indent=2) + '\n')
    return int(any(not c['pass'] for c in checks))


if __name__ == '__main__':
    raise SystemExit(main())
