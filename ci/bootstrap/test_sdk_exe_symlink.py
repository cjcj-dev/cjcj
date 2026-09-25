#!/usr/bin/env python3
"""Drive sdk_build.sh with the same ELF as a regular file and as a same-dir symlink.

The target assertion is symlink-elf-reaches-ldd: bin/cjc -> cjcj-stage1 must pass
the product ELF gate and print the ldd/--version line. Dangling links and links
to non-ELF files must still be rejected. This script does not reimplement the gate.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

TUPLE = 'linux_x86_64_cjnative'


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def write_libs(libs):
    libs.mkdir(parents=True)
    none_c = libs / 'none.c'
    both_c = libs / 'both.c'
    none_c.write_text('int unrelated;\n')
    both_c.write_text('int g_cjLoadBadMask;\nint future_colour_export;\n')
    subprocess.run(['cc', '-c', '-fPIC', str(none_c), '-o', str(libs / 'none.o')], check=True)
    subprocess.run(['ar', 'rcs', str(libs / 'none.a'), str(libs / 'none.o')], check=True)
    subprocess.run(['cc', '-shared', '-fPIC', str(none_c), '-o', str(libs / 'none.so')], check=True)
    versions = libs / 'versions.map'
    versions.write_text('CANGJIE { global: *; };\n')
    subprocess.run(
        ['cc', '-shared', '-fPIC', str(both_c), '-Wl,--version-script=' + str(versions),
         '-o', str(libs / 'both-versioned.so')],
        check=True,
    )


def plant_runtime(base, libs):
    dyn = base / 'runtime/lib' / TUPLE
    std = base / 'lib' / TUPLE
    dyn.mkdir(parents=True)
    std.mkdir(parents=True)
    shutil.copyfile(libs / 'none.so', dyn / 'libcangjie-runtime.so')
    shutil.copyfile(libs / 'none.a', std / 'libcangjie-std-core.a')
    (base / 'envsetup.sh').write_text(':\n')


def plant_producer(base, elf):
    (base / 'std-producer.json').write_text(
        json.dumps({'compiler_sha256': sha256(elf)}) + '\n')


def assemble(product, base, target, libs):
    cmd = [
        'bash', str(product), '--from', str(base), '--to', str(target), '--host',
        '--colour-runtime', str(libs / 'both-versioned.so'),
        '--host-runtime', str(libs / 'none.so'),
    ]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return cmd, result


def cjc_verify_line(log):
    for line in log.splitlines():
        if 'bin/cjc' in line and 'ELF' in line and 'ldd' in line and 'bin/cjc-' not in line:
            return line
    return ''


def run_case(name, product, root, libs, elf, repeat):
    work = root / name
    work.mkdir()
    base = work / 'base'
    target = work / 'sdk'
    plant_runtime(base, libs)
    kind = name.rsplit('-', 1)[0]
    bin_dir = base / 'bin'
    bin_dir.mkdir()
    if kind == 'regular-elf':
        shutil.copyfile(elf, bin_dir / 'cjc')
        (bin_dir / 'cjc').chmod(0o755)
        plant_producer(base, bin_dir / 'cjc')
    elif kind == 'symlink-elf':
        shutil.copyfile(elf, bin_dir / 'cjcj-stage1')
        (bin_dir / 'cjcj-stage1').chmod(0o755)
        (bin_dir / 'cjc').symlink_to('cjcj-stage1')
        (bin_dir / 'cjc-frontend').symlink_to('cjcj-stage1')
        plant_producer(base, bin_dir / 'cjcj-stage1')
    elif kind == 'nonelf-symlink':
        (bin_dir / 'cjcj-stage1').write_text('not an elf\n')
        (bin_dir / 'cjc').symlink_to('cjcj-stage1')
        plant_producer(base, elf)
    elif kind == 'dangling-cjc':
        (bin_dir / 'cjc').symlink_to('missing-cjcj-stage1')
        plant_producer(base, elf)
    elif kind == 'dangling-llc':
        shutil.copyfile(elf, bin_dir / 'cjc')
        (bin_dir / 'cjc').chmod(0o755)
        plant_producer(base, bin_dir / 'cjc')
        llc = base / 'third_party/llvm/bin'
        llc.mkdir(parents=True)
        (llc / 'llc').symlink_to('missing-llc')
    else:
        raise SystemExit('unknown case ' + kind)
    cmd, result = assemble(product, base, target, libs)
    log_path = work / 'run.log'
    log_path.write_text(result.stdout)
    installed = target / 'bin/cjc'
    record = {
        'name': name,
        'repeat': repeat,
        'command': cmd,
        'rc': result.returncode,
        'product_sha256': sha256(product),
        'elf_sha256': sha256(elf),
        'log': str(log_path),
        'reached_file_gate': '[4/5]' in result.stdout,
        'not_elf': '不是 ELF' in result.stdout,
        'verify_line': cjc_verify_line(result.stdout),
        'installed_is_symlink': installed.is_symlink(),
        'installed_link': os_readlink(installed),
    }
    (work / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


def os_readlink(path):
    try:
        return path.readlink().as_posix() if path.is_symlink() else ''
    except OSError:
        return ''


def judge(records):
    by_kind = {}
    for record in records:
        by_kind.setdefault(record['name'].rsplit('-', 1)[0], []).append(record)
    verdicts = []

    def add(name, passed, detail, samples):
        verdicts.append({
            'name': name,
            'executed': True,
            'passed': bool(passed),
            'detail': detail,
            'n': len(samples),
        })

    regular = by_kind['regular-elf']
    add('regular-elf-reaches-ldd',
        all(item['rc'] == 0 and 'ELF' in item['verify_line'] and 'ldd' in item['verify_line']
            and '--version' in item['verify_line'] and not item['not_elf'] for item in regular),
        regular[0]['verify_line'], regular)
    linked = by_kind['symlink-elf']
    add('symlink-elf-reaches-ldd',
        all(item['rc'] == 0 and 'ELF' in item['verify_line'] and 'ldd' in item['verify_line']
            and '--version' in item['verify_line'] and not item['not_elf']
            and item['installed_is_symlink'] and item['installed_link'] == 'cjcj-stage1'
            for item in linked),
        'rc=%s line=%s link=%s' % (linked[0]['rc'], linked[0]['verify_line'], linked[0]['installed_link']),
        linked)
    nonelf = by_kind['nonelf-symlink']
    add('nonelf-symlink-rejected',
        all(item['rc'] != 0 and item['not_elf'] and item['reached_file_gate'] and not item['verify_line']
            for item in nonelf),
        'rc=%s gate=%s' % (nonelf[0]['rc'], nonelf[0]['reached_file_gate']), nonelf)
    dangling_cjc = by_kind['dangling-cjc']
    add('dangling-cjc-rejected',
        all(item['rc'] != 0 and not item['verify_line'] for item in dangling_cjc),
        'rc=%s' % dangling_cjc[0]['rc'], dangling_cjc)
    dangling_llc = by_kind['dangling-llc']
    add('dangling-llc-rejected',
        all(item['rc'] != 0 and item['not_elf'] and item['reached_file_gate'] and 'llc' in Path(item['log']).read_text()
            for item in dangling_llc),
        'rc=%s gate=%s' % (dangling_llc[0]['rc'], dangling_llc[0]['reached_file_gate']), dangling_llc)
    return verdicts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--product', type=Path, default=Path(__file__).with_name('sdk_build.sh'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--elf', type=Path, default=Path('/bin/true'))
    parser.add_argument('--repeat', type=int, default=1)
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error('--repeat must be >= 1')
    product = args.product.resolve()
    elf = args.elf.resolve()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    libs = root / 'libs'
    write_libs(libs)
    file_probe = root / 'file-probe'
    file_probe.mkdir()
    shutil.copyfile(elf, file_probe / 'elf')
    (file_probe / 'link').symlink_to('elf')
    probe = {
        'file_b': subprocess.run(['file', '-b', str(file_probe / 'link')], capture_output=True, text=True).stdout.strip(),
        'file_bL': subprocess.run(['file', '-bL', str(file_probe / 'link')], capture_output=True, text=True).stdout.strip(),
    }
    (root / 'file-probe.json').write_text(json.dumps(probe, indent=2) + '\n')
    records = []
    kinds = ('regular-elf', 'symlink-elf', 'nonelf-symlink', 'dangling-cjc', 'dangling-llc')
    for repeat in range(1, args.repeat + 1):
        for kind in kinds:
            records.append(run_case('%s-%d' % (kind, repeat), product, root, libs, elf, repeat))
    verdicts = judge(records)
    (root / 'results.json').write_text(json.dumps({'probe': probe, 'records': records, 'verdicts': verdicts}, indent=2) + '\n')
    failed = False
    for item in verdicts:
        status = 'PASS' if item['passed'] else 'FAIL'
        failed = failed or not item['passed']
        print('%s ASSERT %s executed=true passed=%s N=%s %s' % (
            status, item['name'], str(item['passed']).lower(), item['n'], item['detail']))
    print('PRODUCT_SHA256 %s' % sha256(product))
    print('FILE_B_LINK %s' % probe['file_b'])
    print('FILE_BL_LINK %s' % probe['file_bL'])
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
