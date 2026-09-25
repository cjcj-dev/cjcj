#!/usr/bin/env python3
"""Exercise SDK assembly and real ld selection of the installed shared pair.

These ELF fixtures test sdk_build.sh, not the Cangjie compiler or runtime GC.
Retain all installation/link traces and hashes in --output (must not exist).
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

TUPLE = 'linux_x86_64_cjnative'
PAIR = ('libcangjie-runtime.so', 'libboundscheck.so')
COMMIT = '1234567890abcdef1234567890abcdef12345678'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--product', type=Path, default=Path(__file__).with_name('sdk_build.sh'))
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--fixtures-from', type=Path)
    parser.add_argument('--repeat', type=int, default=3)
    args = parser.parse_args()
    product = args.product.resolve()
    root = args.output.resolve()
    root.mkdir(parents=True, exist_ok=False)
    libs = root / 'libs'
    if args.fixtures_from:
        shutil.copytree(args.fixtures_from.resolve() / 'libs', libs)
    else:
        libs.mkdir()
        sources = {
            'pinned-runtime': 'int g_cjLoadBadMask; const char stamp[]="CJRT-COMMIT:' + COMMIT + '";',
            'pinned-bounds': 'int pinned_bounds;',
            'inherited': 'int inherited_library;',
            'std': 'extern int g_cjLoadBadMask; int *colour_reference=&g_cjLoadBadMask;',
        }
        for name, source in sources.items():
            src = libs / (name + '.c')
            src.write_text(source + '\n')
            subprocess.run(['cc', '-fPIC', '-c', str(src), '-o', str(libs / (name + '.o'))], check=True)
            subprocess.run(['cc', '-shared', str(libs / (name + '.o')), '-o', str(libs / (name + '.so'))], check=True)
            subprocess.run(['ar', 'rcs', str(libs / (name + '.a')), str(libs / (name + '.o'))], check=True)
    manifest = {PAIR[0]: sha(libs / 'pinned-runtime.so'), PAIR[1]: sha(libs / 'pinned-bounds.so')}
    (root / 'pinned-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')

    def run(case):
        layout, aliases, repetition = case
        name = f'{layout}-{aliases}-{repetition}'
        work = root / name
        base = work / 'base'
        target = work / 'sdk'
        dyn_rel = Path('runtime/lib') / TUPLE
        lib_rel = Path('lib') / TUPLE
        copy(Path('/bin/true'), base / 'bin/cjc')
        (base / 'bin/cjc').chmod(0o755)
        (base / 'envsetup.sh').write_text(':\n')
        copy(libs / 'std.a', base / lib_rel / 'libcangjie-std-core.a')
        for member in PAIR:
            copy(libs / 'inherited.so', base / dyn_rel / member)
        inherited = PAIR if aliases == 'both' else (PAIR[1],) if aliases == 'bounds' else ()
        for member in inherited:
            copy(libs / 'inherited.so', base / lib_rel / member)
        source = work / 'install'
        dyn_source = source if layout == 'flat' else source / dyn_rel
        for member, fixture in zip(PAIR, ('pinned-runtime.so', 'pinned-bounds.so')):
            copy(libs / fixture, dyn_source / member)
        if layout == 'nested-static':
            copy(libs / 'inherited.a', base / lib_rel / 'libcangjie-runtime.a')
            copy(libs / 'pinned-runtime.a', source / lib_rel / 'libcangjie-runtime.a')
            # A static-side shared file must not override the pinned dynamic pair.
            for member in PAIR:
                copy(libs / 'inherited.so', source / lib_rel / member)
        cmd = ['bash', str(product), '--from', str(base), '--to', str(target),
               '--target', TUPLE, '--runtime', str(source), '--runtime-commit', COMMIT,
               '--colour-runtime', str(libs / 'pinned-runtime.so'),
               '--host-runtime', str(libs / 'inherited.so')]
        assembly = subprocess.run(cmd, capture_output=True, text=True)
        (work / 'assembly.log').write_text(assembly.stdout + assembly.stderr)
        # Link the actual assembler outputs. Search order and library options are
        # Gnu.cj:306-312 and Linux_CJNATIVE.cj:114-115. No compiler claim is made.
        link_cmd = ['ld', '-shared', '-t', '-L' + str(target / lib_rel),
                    '-L' + str(target / dyn_rel), '-l:libcangjie-runtime.so',
                    '-lboundscheck', '-o', str(work / 'linked.so')]
        link = subprocess.run(link_cmd, capture_output=True, text=True)
        (work / 'link.stdout').write_text(link.stdout)
        (work / 'link.stderr').write_text(link.stderr)
        selected = {}
        for line in link.stdout.splitlines():
            path = Path(line.strip())
            if path.name in PAIR and path.is_file():
                selected[path.name] = dict(path=str(path), sha256=sha(path))
        assertions = {
            'assembler_completed': assembly.returncode == 0,
            'link_completed': link.returncode == 0 and (work / 'linked.so').is_file(),
            'selected_pinned_pair': all(selected.get(member, {}).get('sha256') == manifest[member] for member in PAIR),
            'no_new_alias': all((target / lib_rel / member).exists() == (member in inherited) for member in PAIR),
        }
        record = dict(name=name, command=cmd, assembly_rc=assembly.returncode,
                      link_command=link_cmd, link_rc=link.returncode, selected=selected,
                      assertions=assertions, product_sha256=sha(product),
                      linked_sha256=sha(work / 'linked.so') if (work / 'linked.so').is_file() else None)
        (work / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
        return record

    cases = [(layout, aliases, repetition)
             for layout in ('flat', 'nested', 'nested-static')
             for aliases in ('absent', 'bounds', 'both')
             for repetition in range(args.repeat)]
    with ThreadPoolExecutor(max_workers=4) as executor:
        results = list(executor.map(run, cases))
    for result in results:
        for assertion, passed in result['assertions'].items():
            print(f'{"PASS" if passed else "FAIL"} ASSERT {result["name"]}/{assertion} executed=true '
                  f'assembly_rc={result["assembly_rc"]} link_rc={result["link_rc"]}')
    (root / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    return int(any(not all(result['assertions'].values()) for result in results))


if __name__ == '__main__':
    raise SystemExit(main())
