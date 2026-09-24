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
    parser.add_argument('--real-coloured-sdk', type=Path)
    parser.add_argument('--real-official-sdk', type=Path)
    args = parser.parse_args()
    if bool(args.real_coloured_sdk) != bool(args.real_official_sdk):
        parser.error('both real SDK paths are required together')
    product = args.product.resolve()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    libs = root / 'libs'
    libs.mkdir()
    symbols = {
        'mask': 'int g_cjLoadBadMask;',
        'both': 'int g_cjLoadBadMask; int g_cjLoadBadMaskOffset; int g_cjLoadShift; int future_colour_export; int unrelated;',
        'shift-undefined': 'extern int g_cjLoadShift; int *reference = &g_cjLoadShift;',
        'future-undefined': 'extern int future_colour_export; int *reference = &future_colour_export;',
        'common-undefined': 'extern int unrelated; int *reference = &unrelated;',
        'offset': 'int g_cjLoadBadMaskOffset;',
        'none': 'int unrelated;',
        'offset-undefined': 'extern int g_cjLoadBadMaskOffset; int *reference = &g_cjLoadBadMaskOffset;',
        'prefix-undefined': 'extern int g_cjLoadBadMaskExtra; int *reference = &g_cjLoadBadMaskExtra;',
        'undefined': 'extern int g_cjLoadBadMask; int *reference = &g_cjLoadBadMask;',
    }
    versions = libs / 'versions.map'
    versions.write_text('CANGJIE { global: *; };\n')
    for name, source in (symbols.items() if args.fixtures_from is None else []):
        src = libs / (name + '.c')
        src.write_text(source + '\n')
        obj = libs / (name + '.o')
        subprocess.run(['cc', '-c', '-fPIC', str(src), '-o', str(obj)], check=True)
        subprocess.run(['ar', 'rcs', str(libs / (name + '.a')), str(obj)], check=True)
        for versioned in (False, True):
            so = libs / (name + ('-versioned' if versioned else '') + '.so')
            cmd = ['cc', '-shared', '-fPIC', str(src), '-o', str(so)]
            if versioned:
                cmd.append('-Wl,--version-script=' + str(versions))
            subprocess.run(cmd, check=True)
            (so.with_suffix('.nm')).write_text(subprocess.check_output(['nm', '-D', str(so)], text=True))
    if args.fixtures_from is None:
        src = libs / 'version-reference.c'
        src.write_text('extern int mask; int *reference = &mask;\n'
                       '__asm__(".symver mask,g_cjLoadBadMask@CANGJIE");\n')
        subprocess.run(['cc', '-c', '-fPIC', str(src), '-o', str(libs / 'version-reference.o')], check=True)
        subprocess.run(['ar', 'rcs', str(libs / 'version-reference.a'), str(libs / 'version-reference.o')], check=True)
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

    # Both directions, exact symbol boundaries, installed/inherited std and
    # the independent managed-tool host runtime must reach the actual assembler.
    pair_cases = {
        'pair-shift-target': ('both', 'target', 'shift-undefined', 0),
        'pair-shift-host': ('none', 'host', 'shift-undefined', 1),
        'pair-future-target': ('both', 'target', 'future-undefined', 0),
        'pair-common-target': ('both', 'target', 'common-undefined', 1),
        'pair-common-host': ('none', 'host', 'common-undefined', 0),
        'pair-mask-target': ('mask', 'target', 'undefined', 0),
        'pair-version-target': ('mask', 'target', 'version-reference', 0),
        'pair-offset-target': ('mask', 'target', 'offset-undefined', 0),
        'pair-official-host': ('none', 'host', 'none', 0),
        'pair-official-target': ('mask', 'target', 'none', 1),
        'pair-coloured-host': ('none', 'host', 'undefined', 1),
        'pair-offset-host': ('none', 'host', 'offset-undefined', 1),
        'pair-prefix-target': ('mask', 'target', 'prefix-undefined', 1),
        'pair-prefix-host': ('none', 'host', 'prefix-undefined', 0),
        'pair-definition-target': ('mask', 'target', 'mask', 1),
        'pair-install-target': ('mask', 'target', 'offset-undefined', 0),
        'pair-install-official': ('mask', 'target', 'none', 1),
        'pair-verify-host': ('mask', 'target', 'undefined', 0),
        'pair-verify-host-mismatch': ('mask', 'target', 'none', 1),
    }
    real_pairs = {}
    if args.real_coloured_sdk:
        for name, rt_sdk, std_sdk, role, expected in (
            ('real-coloured', args.real_coloured_sdk, args.real_coloured_sdk, 'target', 0),
            ('real-official', args.real_official_sdk, args.real_official_sdk, 'host', 0),
            ('real-official-std', args.real_coloured_sdk, args.real_official_sdk, 'target', 1),
            ('real-coloured-std', args.real_official_sdk, args.real_coloured_sdk, 'host', 1),
        ):
            pair_cases[name] = ('mask' if role == 'target' else 'none', role, 'none', expected)
            real_pairs[name] = (rt_sdk, std_sdk)
    for name, (variant, role, std_variant, expected) in pair_cases.items():
        cases.append((name, [LINUX], variant, role, expected,
                      'STD-RUNTIME-COLOUR-MISMATCH' if expected else None))

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
        # A complete SDK fixture includes std, paired with the actual runtime.
        # Runtime-role failures still stop at their original assertion.
        std_dir = base / 'lib' / LINUX
        std_dir.mkdir(parents=True)
        std_variant = 'undefined' if variant in ('mask', 'both', 'both-versioned') else 'none'
        shutil.copyfile(libs / (std_variant + '.a'), std_dir / 'libcangjie-std-core.a')
        if name in pair_cases:
            shutil.copyfile(libs / (pair_cases[name][2] + '.a'), std_dir / 'libcangjie-std-core.a')
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
        if name in real_pairs:
            rt_sdk, std_sdk = real_pairs[name]
            shutil.copyfile(rt_sdk / 'runtime/lib' / LINUX / 'libcangjie-runtime.so',
                            base / 'runtime/lib' / LINUX / 'libcangjie-runtime.so')
            shutil.copyfile(std_sdk / 'lib' / LINUX / 'libcangjie-std-core.a',
                            std_dir / 'libcangjie-std-core.a')
            # Inherited real pair: no runtime installation/provenance transform.
            del cmd[-2:]
            shutil.copyfile(base / 'runtime/lib' / LINUX / 'libcangjie-runtime.so', source / 'libcangjie-runtime.so')
        if name.startswith('pair-install-'):
            prefix = work / 'final-std'
            for directory in ('modules/' + LINUX, 'lib/' + LINUX, 'runtime/lib/' + LINUX):
                (base / directory).mkdir(parents=True, exist_ok=True)
                (prefix / directory).mkdir(parents=True)
            shutil.copyfile(std_dir / 'libcangjie-std-core.a', prefix / 'lib' / LINUX / 'libcangjie-std-core.a')
            for rel in ('runtime/lib/' + LINUX + '/libcangjie-std-core.so', 'lib/libstdFFI.so'):
                shutil.copyfile(libs / 'none.so', base / rel)
                shutil.copyfile(libs / 'none.so', prefix / rel)
            # The baseline has the opposite colour: the *installed* std decides.
            other = 'undefined' if pair_cases[name][2] == 'none' else 'none'
            shutil.copyfile(libs / (other + '.a'), std_dir / 'libcangjie-std-core.a')
            cmd += ['--std', str(prefix)]
        if name.startswith('pair-verify-host'):
            host_rt = work / 'host-rt'
            host_rt.mkdir()
            shutil.copyfile(libs / 'none.so', host_rt / 'libcangjie-runtime.so')
            cmd += ['--verify-host-rt', str(host_rt)]
        colour_reference = (args.real_coloured_sdk / 'runtime/lib' / LINUX / 'libcangjie-runtime.so'
                            if name in real_pairs else libs / 'both-versioned.so')
        host_reference = (args.real_official_sdk / 'runtime/lib' / LINUX / 'libcangjie-runtime.so'
                          if name in real_pairs else libs / 'none.so')
        cmd += ['--colour-runtime', str(colour_reference), '--host-runtime', str(host_reference)]
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
        if name in pair_cases and expected != 0:
            installed_std = target / 'lib' / LINUX / 'libcangjie-std-core.a'
            ok &= ('std_sha256=' + sha(installed_std)) in result.stdout
            std_source = work / 'final-std' if name.startswith('pair-install-') else base
            ok &= ('std_source=' + str(std_source)) in result.stdout
        record = dict(name=name, assertion_executed=True, passed=bool(ok), rc=result.returncode,
                      expected_rc=expected, command=cmd,
                      predicate_sha256=sha(product.with_name('std_runtime_colour.py')) if product.with_name('std_runtime_colour.py').exists() else None, base_enumeration=base_order, product_sha256=sha(product),
                      elf_sha256=sha(base / 'bin/cjc'), so_sha256=sha(source / 'libcangjie-runtime.so'))
        if name in real_pairs:
            rt_sdk, std_sdk = real_pairs[name]
            record['real_runtime_source'] = str(rt_sdk / 'runtime/lib' / LINUX / 'libcangjie-runtime.so')
            record['real_std_source'] = str(std_sdk / 'lib' / LINUX / 'libcangjie-std-core.a')
            record['std_sha256'] = sha(std_dir / 'libcangjie-std-core.a')
        (work / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
        return record

    with ThreadPoolExecutor(max_workers=len(cases)) as pool:
        results = list(pool.map(run, cases))
    # This is also the exact CLI consumed by stage3, using these same archives.
    for variant, expected in [('undefined', '1'), ('offset-undefined', '1'),
                              ('version-reference', '1'), ('none', '0'),
                              ('prefix-undefined', '0'), ('mask', '0'), ('shift-undefined', '1'),
                              ('future-undefined', '1'), ('common-undefined', '0')]:
        command = ['python3', str(product.with_name('std_runtime_colour.py')),
                   '--std-colour', str(libs / (variant + '.a')),
                   '--colour-runtime', str(libs / 'both-versioned.so'),
                   '--host-runtime', str(libs / 'none.so')]
        result = subprocess.run(command, capture_output=True, text=True)
        results.append(dict(name='std-cli-' + variant, assertion_executed=True,
                            passed=result.returncode == 0 and result.stdout.strip() == expected,
                            rc=result.returncode, expected_rc=0, expected_stdout=expected,
                            stdout=result.stdout, stderr=result.stderr, command=command,
                            predicate_sha256=sha(product.with_name('std_runtime_colour.py'))))
    for result in results:
        print(('PASS' if result['passed'] else 'FAIL') + ' ASSERT ' + result['name'] +
              ' executed=true rc=' + str(result['rc']) + ' expected=' + str(result['expected_rc']))
    (root / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    return int(any(not result['passed'] for result in results))


if __name__ == '__main__':
    raise SystemExit(main())
