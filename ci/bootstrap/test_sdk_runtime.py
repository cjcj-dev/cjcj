#!/usr/bin/env python3
"""Run the real SDK assembler against isolated ELF SDK fixtures.

Usage: test_sdk_runtime.py --output DIR [--product sdk_build.sh]
Retains commands, script/ELF identities, SDK output and assertion results.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

LINUX = 'linux_x86_64_cjnative'
WINDOWS = 'windows_x86_64_cjnative'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--product', type=Path, default=Path(__file__).with_name('sdk_build.sh'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--fixtures-from', type=Path, help='Reuse the exact ELF libraries from a prior arm')
    args = parser.parse_args()
    product = args.product.resolve()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    libs = root / 'libs'
    libs.mkdir()
    symbols = {
        'mask': 'int g_cjLoadBadMask;',
        'both': 'int g_cjLoadBadMask; int g_cjLoadBadMaskOffset;',
        'offset': 'int g_cjLoadBadMaskOffset;',
        'none': 'int unrelated;',
        'undefined': 'extern int g_cjLoadBadMask; int *reference = &g_cjLoadBadMask;',
    }
    versions = libs / 'versions.map'
    versions.write_text('CANGJIE { global: *; };\n')
    for name, source in (symbols.items() if args.fixtures_from is None else []):
        src = libs / (name + '.c')
        src.write_text(source + '\n')
        for versioned in (False, True):
            so = libs / (name + ('-versioned' if versioned else '') + '.so')
            cmd = ['cc', '-shared', '-fPIC', str(src), '-o', str(so)]
            if versioned:
                cmd.append('-Wl,--version-script=' + str(versions))
            subprocess.run(cmd, check=True)
            (so.with_suffix('.nm')).write_text(subprocess.check_output(['nm', '-D', str(so)], text=True))
    if args.fixtures_from is not None:
        shutil.copytree(args.fixtures_from / 'libs', libs, dirs_exist_ok=True)
    # Keep selection and colour surfaces independent: tuple cases contain only
    # the exact mask, while symbol cases have only one tuple.
    cases = [
        ('windows-first', [WINDOWS, LINUX], 'mask', 'target', 0, None),
        ('linux-first', [LINUX, WINDOWS], 'mask', 'target', 0, None),
        ('verify-windows-first', [WINDOWS, LINUX], 'mask', 'target', 0, None),
        ('verify-linux-first', [LINUX, WINDOWS], 'mask', 'target', 0, None),
        ('single-tuple-control', [LINUX], 'mask', 'target', 0, None),
        ('missing-target', [WINDOWS], 'mask', 'target', 1, '目标里缺构建目标 runtime/lib/' + LINUX),
        ('source-mismatch', [LINUX], 'mask', 'target', 1, 'runtime 平台不一致'),
    ]
    for variant in ('both', 'both-versioned', 'none', 'offset', 'offset-versioned', 'undefined'):
        for role in ('host', 'target'):
            coloured = variant.startswith('both')
            expected = 0 if coloured == (role == 'target') else 1
            cases.append((variant + '-' + role, [LINUX], variant, role, expected, None))

    def run(case):
        name, order, variant, role, expected, diagnostic = case
        work = root / name
        base = work / 'base'
        (base / 'bin').mkdir(parents=True)
        shutil.copyfile('/bin/true', base / 'bin/cjc')
        (base / 'bin/cjc').chmod(0o755)
        (base / 'envsetup.sh').write_text(':\n')
        for tpl in order:
            directory = base / 'runtime/lib' / tpl
            directory.mkdir(parents=True)
            # Windows is an independent sentinel: it must not be selected or replaced.
            initial = 'mask.so' if name.startswith('verify-') and tpl == LINUX else 'none.so'
            shutil.copyfile(libs / initial, directory / 'libcangjie-runtime.so')
        source_tuple = WINDOWS if name == 'source-mismatch' else LINUX
        source = work / 'install/runtime/lib' / source_tuple
        source.mkdir(parents=True)
        shutil.copyfile(libs / (variant + '.so'), source / 'libcangjie-runtime.so')
        target = work / 'sdk'
        cmd = ['bash', str(product), '--from', str(base), '--to', str(target), '--' + role]
        if role == 'target':
            cmd.append(LINUX)
        if not name.startswith('verify-'):
            cmd += ['--runtime', str(work / 'install')]
        base_order = subprocess.check_output(['find', str(base / 'runtime/lib'), '-mindepth', '1',
                                              '-maxdepth', '1', '-type', 'd'], text=True).splitlines()
        result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        (work / 'run.log').write_text(result.stdout)
        # Every case reaches this nonfatal target assertion, including failed assembly.
        ok = result.returncode == expected
        if diagnostic:
            ok &= diagnostic in result.stdout
        if expected == 0:
            installed = target / 'runtime/lib' / LINUX / 'libcangjie-runtime.so'
            ok &= installed.is_file() and sha(installed) == sha(source / 'libcangjie-runtime.so')
            ok &= 'SDK-BUILD-OK role=' + role in result.stdout
            if WINDOWS in order:
                ok &= sha(target / 'runtime/lib' / WINDOWS / 'libcangjie-runtime.so') == sha(libs / 'none.so')
        elif diagnostic is None:
            # A colour refusal, not an unrelated earlier failure.
            ok &= '[3/5] 着色断言' in result.stdout and '[4/5]' not in result.stdout
            mask = 1 if variant.startswith('both') else 0
            ok &= 'mask=' + str(mask) in result.stdout
        record = dict(name=name, assertion_executed=True, passed=bool(ok), rc=result.returncode,
                      expected_rc=expected, command=cmd, base_enumeration=base_order, product_sha256=sha(product),
                      elf_sha256=sha(base / 'bin/cjc'), so_sha256=sha(source / 'libcangjie-runtime.so'))
        (work / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
        return record

    with ThreadPoolExecutor(max_workers=len(cases)) as pool:
        results = list(pool.map(run, cases))
    for result in results:
        print(('PASS' if result['passed'] else 'FAIL') + ' ASSERT ' + result['name'] +
              ' executed=true rc=' + str(result['rc']) + ' expected=' + str(result['expected_rc']))
    (root / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    return int(any(not result['passed'] for result in results))


if __name__ == '__main__':
    raise SystemExit(main())
