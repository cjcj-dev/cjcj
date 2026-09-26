#!/usr/bin/env python3
"""Drive sdk_build.sh --cjc against a regular bin/cjc and a same-dir symlink.

Target assertion is symlink-cjc-replaced: bin/cjc -> cjcj-stage1 must be
installed through the link, the link text must stay cjcj-stage1, and the
referent sha256 must become the --cjc ELF. A regular bin/cjc is still replaced
in place. A link whose referent is outside the copy must be rejected without
changing that file. A dangling bin/cjc must still die at the existing
[ -f bin/cjc ] gate.
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
    (base / 'std-producer.json').write_text(json.dumps({'compiler_sha256': sha256(elf)}) + '\n')


def assemble(product, base, target, libs, cjc):
    cmd = [
        'bash', str(product), '--from', str(base), '--to', str(target), '--host',
        '--cjc', str(cjc),
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


def os_readlink(path):
    try:
        return path.readlink().as_posix() if path.is_symlink() else ''
    except OSError:
        return ''


def run_case(name, product, root, libs, old_elf, new_elf, repeat):
    work = root / name
    work.mkdir()
    base = work / 'base'
    target = work / 'sdk'
    outside = work / 'outside'
    plant_runtime(base, libs)
    kind = name.rsplit('-', 1)[0]
    bin_dir = base / 'bin'
    bin_dir.mkdir()
    outside.mkdir()
    outside_elf = outside / 'elf'
    shutil.copyfile(old_elf, outside_elf)
    outside_elf.chmod(0o755)
    outside_before = sha256(outside_elf)
    if kind == 'regular-swap':
        shutil.copyfile(old_elf, bin_dir / 'cjc')
        (bin_dir / 'cjc').chmod(0o755)
        plant_producer(base, new_elf)
    elif kind == 'symlink-swap':
        shutil.copyfile(old_elf, bin_dir / 'cjcj-stage1')
        (bin_dir / 'cjcj-stage1').chmod(0o755)
        (bin_dir / 'cjc').symlink_to('cjcj-stage1')
        (bin_dir / 'cjc-frontend').symlink_to('cjcj-stage1')
        plant_producer(base, new_elf)
    elif kind == 'escape-swap':
        (bin_dir / 'cjc').symlink_to(outside_elf)
        plant_producer(base, new_elf)
    elif kind == 'dangling-cjc':
        (bin_dir / 'cjc').symlink_to('missing-cjcj-stage1')
        plant_producer(base, new_elf)
    else:
        raise SystemExit('unknown case ' + kind)
    cmd, result = assemble(product, base, target, libs, new_elf)
    log_path = work / 'run.log'
    log_path.write_text(result.stdout)
    installed = target / 'bin/cjc'
    stage1 = target / 'bin/cjcj-stage1'
    frontend = target / 'bin/cjc-frontend'
    record = {
        'name': name,
        'repeat': repeat,
        'command': cmd,
        'rc': result.returncode,
        'product_sha256': sha256(product),
        'old_elf_sha256': sha256(old_elf),
        'new_elf_sha256': sha256(new_elf),
        'log': str(log_path),
        'sdk_build_ok': 'SDK-BUILD-OK' in result.stdout,
        'missing_slot': '没有名为 cjc' in result.stdout,
        'outside_refuse': '指向副本之外' in result.stdout,
        'dangling_gate': '缺 bin/cjc' in result.stdout,
        'replaced_line': '[cjc] 替换' in result.stdout,
        'verify_line': cjc_verify_line(result.stdout),
        'installed_is_symlink': installed.is_symlink(),
        'installed_link': os_readlink(installed),
        'frontend_link': os_readlink(frontend),
        'installed_sha256': sha256(installed) if installed.is_file() else '',
        'stage1_sha256': sha256(stage1) if stage1.is_file() else '',
        'outside_sha256': sha256(outside_elf),
        'outside_before': outside_before,
    }
    (work / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


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

    regular = by_kind['regular-swap']
    add('regular-cjc-replaced',
        all(item['rc'] == 0 and item['sdk_build_ok'] and item['replaced_line']
            and not item['installed_is_symlink']
            and item['installed_sha256'] == item['new_elf_sha256']
            and item['installed_sha256'] != item['old_elf_sha256']
            and 'ELF' in item['verify_line'] and 'ldd' in item['verify_line']
            and '--version' in item['verify_line']
            for item in regular),
        'rc=%s sha=%s line=%s' % (regular[0]['rc'], regular[0]['installed_sha256'][:16], regular[0]['verify_line']),
        regular)
    linked = by_kind['symlink-swap']
    add('symlink-cjc-replaced',
        all(item['rc'] == 0 and item['sdk_build_ok'] and item['replaced_line']
            and not item['missing_slot']
            and item['installed_is_symlink'] and item['installed_link'] == 'cjcj-stage1'
            and item['frontend_link'] == 'cjcj-stage1'
            and item['stage1_sha256'] == item['new_elf_sha256']
            and item['stage1_sha256'] != item['old_elf_sha256']
            and item['installed_sha256'] == item['new_elf_sha256']
            and 'ELF' in item['verify_line'] and 'ldd' in item['verify_line']
            and '--version' in item['verify_line']
            for item in linked),
        'rc=%s link=%s stage1=%s missing_slot=%s line=%s' % (
            linked[0]['rc'], linked[0]['installed_link'], linked[0]['stage1_sha256'][:16],
            str(linked[0]['missing_slot']).lower(), linked[0]['verify_line']),
        linked)
    escape = by_kind['escape-swap']
    add('escape-outside-unchanged',
        all(item['rc'] != 0 and not item['sdk_build_ok']
            and item['outside_sha256'] == item['outside_before']
            and item['outside_sha256'] == item['old_elf_sha256']
            for item in escape),
        'rc=%s outside=%s before=%s refuse=%s' % (
            escape[0]['rc'], escape[0]['outside_sha256'][:16], escape[0]['outside_before'][:16],
            str(escape[0]['outside_refuse']).lower()),
        escape)
    add('escape-seen-and-refused',
        all(item['rc'] != 0 and item['outside_refuse']
            and item['outside_sha256'] == item['outside_before']
            and not item['replaced_line']
            for item in escape),
        'rc=%s refuse=%s replaced=%s' % (
            escape[0]['rc'], str(escape[0]['outside_refuse']).lower(), str(escape[0]['replaced_line']).lower()),
        escape)
    dangling = by_kind['dangling-cjc']
    add('dangling-cjc-early-gate',
        all(item['rc'] != 0 and item['dangling_gate'] and not item['replaced_line']
            and not item['sdk_build_ok']
            for item in dangling),
        'rc=%s gate=%s' % (dangling[0]['rc'], str(dangling[0]['dangling_gate']).lower()),
        dangling)
    return verdicts


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--product', type=Path, default=Path(__file__).with_name('sdk_build.sh'))
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--old-elf', type=Path, default=Path('/bin/true'))
    parser.add_argument('--new-elf', type=Path, default=Path('/bin/echo'))
    parser.add_argument('--repeat', type=int, default=1)
    args = parser.parse_args()
    if args.repeat < 1:
        parser.error('--repeat must be >= 1')
    product = args.product.resolve()
    old_elf = args.old_elf.resolve()
    new_elf = args.new_elf.resolve()
    if sha256(old_elf) == sha256(new_elf):
        parser.error('old and new ELF are identical')
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    libs = root / 'libs'
    write_libs(libs)
    records = []
    kinds = ('regular-swap', 'symlink-swap', 'escape-swap', 'dangling-cjc')
    for repeat in range(1, args.repeat + 1):
        for kind in kinds:
            records.append(run_case('%s-%d' % (kind, repeat), product, root, libs, old_elf, new_elf, repeat))
    verdicts = judge(records)
    (root / 'results.json').write_text(json.dumps({
        'product': str(product),
        'product_sha256': sha256(product),
        'old_elf_sha256': sha256(old_elf),
        'new_elf_sha256': sha256(new_elf),
        'records': records,
        'verdicts': verdicts,
    }, indent=2) + '\n')
    failed = False
    for item in verdicts:
        status = 'PASS' if item['passed'] else 'FAIL'
        failed = failed or not item['passed']
        print('%s ASSERT %s executed=true passed=%s N=%s %s' % (
            status, item['name'], str(item['passed']).lower(), item['n'], item['detail']))
    print('PRODUCT_SHA256 %s' % sha256(product))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
