#!/usr/bin/env python3
"""Run the real SDK assembler on complete and incomplete std prefixes.

ELF fixtures exercise assembly, not compiler or runtime semantics. Every
assertion records the installed bytes or the assembler's diagnostic/exit code.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

TUPLE = 'linux_x86_64_cjnative'
CROSS = 'windows_x86_64_cjnative'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--product', type=Path, default=Path(__file__).with_name('sdk_build.sh'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--fixtures-from', type=Path)
    args = parser.parse_args()
    product = args.product.resolve()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    fixtures = root / 'fixtures'
    if args.fixtures_from:
        shutil.copytree(args.fixtures_from.resolve(), fixtures)
    else:
        fixtures.mkdir()
        pin = dict(line.split('=', 1) for line in
                   (product.parent.parent / 'runtime_pin.env').read_text().splitlines()
                   if line)['RUNTIME_REF']
        sources = {
            'host': 'int host_runtime;',
            'colour': 'int g_cjLoadBadMask; const char stamp[]="CJRT-COMMIT:' + pin + '";',
            'old': 'int old_package;',
            'host-std': 'int new_package;',
            'target-std': 'extern int g_cjLoadBadMask; int *reference=&g_cjLoadBadMask;',
        }
        for name, source in sources.items():
            src = fixtures / (name + '.c')
            src.write_text(source + '\n')
            obj = fixtures / (name + '.o')
            subprocess.run(['cc', '-fPIC', '-c', str(src), '-o', str(obj)], check=True)
            subprocess.run(['cc', '-shared', str(obj), '-o', str(fixtures / (name + '.so'))], check=True)
            subprocess.run(['ar', 'rcs', str(fixtures / (name + '.a')), str(obj)], check=True)
        copy(Path('/bin/true'), fixtures / 'cjcj-stage1')
    fixture_hashes = {p.name: sha(p) for p in sorted(fixtures.iterdir())}

    def run(case):
        role, missing = case
        name = role + '-' + (missing.replace('/', '_') if missing else 'complete')
        work = root / name
        base, prefix, target = (work / p for p in ('base', 'std [prefix]', 'sdk [output]'))
        copy(fixtures / 'cjcj-stage1', base / 'bin/cjcj-stage1')
        for alias in ('cjc', 'cjc-frontend'):
            (base / 'bin' / alias).symlink_to('cjcj-stage1')
        (base / 'envsetup.sh').write_text(':\n')
        for sdk in (base, prefix):
            (sdk / 'modules' / TUPLE).mkdir(parents=True)
            (sdk / 'modules' / TUPLE / 'core.cjo').write_text(str(sdk) + '\n')
            (sdk / 'std-producer.json').write_text(json.dumps({
                'compiler_sha256': sha(fixtures / 'cjcj-stage1')}) + '\n')
        for parent, ext in (('lib', '.a'), ('runtime/lib', '.so')):
            for package in ('core', 'sort', 'collection.concurrentFFI'):
                rel = Path(parent) / TUPLE / ('libcangjie-std-' + package + ext)
                copy(fixtures / ('old' + ext), base / rel)
                copy(fixtures / (role + '-std' + ext), prefix / rel)
            # Aggregates and other tuples must be pruned, even if no replacement
            # exists. Non-std files in both tuples must survive unchanged.
            copy(fixtures / ('old' + ext), base / parent / TUPLE / ('libcangjie-std' + ext))
            copy(fixtures / ('old' + ext), base / parent / CROSS / ('libcangjie-std-sort' + ext))
            for tuple_name in (TUPLE, CROSS):
                copy(fixtures / ('host' + ext), base / parent / tuple_name / ('libkeep' + ext))
        runtime = 'host' if role == 'host' else 'colour'
        for name_so in ('libcangjie-runtime.so', 'libboundscheck.so'):
            copy(fixtures / (runtime + '.so'), base / 'runtime/lib' / TUPLE / name_so)
        copy(fixtures / 'old.so', base / 'lib/libstdFFI.so')
        copy(fixtures / (role + '-std.so'), prefix / 'lib/libstdFFI.so')
        # Source runtime files must never overwrite the installed runtime pair.
        copy(fixtures / 'old.so', prefix / 'runtime/lib' / TUPLE / 'libcangjie-runtime.so')
        rel_missing = Path(missing) / TUPLE / ('libcangjie-std-sort' + ('.a' if missing == 'lib' else '.so'))
        if missing:
            (prefix / rel_missing).unlink()
        command = ['bash', str(product), '--from', str(base), '--to', str(target),
                   '--' + role, '--std', str(prefix),
                   '--colour-runtime', str(fixtures / 'colour.so'),
                   '--host-runtime', str(fixtures / 'host.so')]
        result = subprocess.run(command, capture_output=True, text=True)
        log = result.stdout + result.stderr
        (work / 'assembly.log').write_text(log)
        actual = {str(p.relative_to(target)): sha(p) for parent in ('lib', 'runtime/lib')
                  for p in (target / parent).glob('*/libcangjie-std*') if p.is_file()}
        expected = {str(p.relative_to(prefix)): sha(p) for parent in ('lib', 'runtime/lib')
                    for p in (prefix / parent / TUPLE).glob('libcangjie-std*')}
        assertions = {}
        if missing:
            assertions['missing_package_rejected'] = (
                result.returncode != 0 and 'std install prefix 缺包: ' + str(rel_missing) in log)
        else:
            assertions['assembly_completed'] = result.returncode == 0 and 'SDK-BUILD-OK' in log
            assertions['installed_std_exactly_prefix'] = actual == expected
            assertions['ffi_installed'] = sha(target / 'lib/libstdFFI.so') == sha(prefix / 'lib/libstdFFI.so')
        preserved = [p.relative_to(base) for p in base.glob('**/libkeep*')]
        preserved += [Path('runtime/lib') / TUPLE / p for p in ('libcangjie-runtime.so', 'libboundscheck.so')]
        assertions['non_std_preserved'] = all(
            (target / p).is_file() and sha(target / p) == sha(base / p) for p in preserved)
        record = dict(name=name, command=command, rc=result.returncode,
                      assertions=assertions, actual_std=actual, expected_std=expected,
                      product_sha256=sha(product), fixture_sha256=fixture_hashes)
        (work / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
        return record

    cases = [(role, missing) for role in ('host', 'target') for missing in ('', 'lib', 'runtime/lib')]
    with ThreadPoolExecutor(max_workers=len(cases)) as executor:
        results = list(executor.map(run, cases))
    for result in results:
        for assertion, passed in result['assertions'].items():
            print(f'{"PASS" if passed else "FAIL"} ASSERT {result["name"]}/{assertion} '
                  f'executed=true assembly_rc={result["rc"]}')
    (root / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    return int(any(not all(r['assertions'].values()) for r in results))


if __name__ == '__main__':
    raise SystemExit(main())
