#!/usr/bin/env python3
"""Verify and activate source-built stage3 tuples; H48 schema 1 is separate."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

from language_tuple import ALIASES, TUPLE, digest, inventory, require, emit_env

ROLES = {
    'compiler': 'sdk/bin/cjcj-stage1',
    'stdlib': f'sdk/lib/{TUPLE}/libcangjie-std-core.a',
    'llc': 'sdk/third_party/llvm/bin/llc',
    'opt': 'sdk/third_party/llvm/bin/opt',
    'llvm_library': 'sdk/third_party/llvm/lib/libLLVM-15.so',
    'compiler_runtime': f'compiler-runtime/{TUPLE}/libcangjie-runtime.so',
    'compiler_boundscheck': f'compiler-runtime/{TUPLE}/libboundscheck.so',
    'official_host_runtime': f'official-host/{TUPLE}/libcangjie-runtime.so',
    'official_host_boundscheck': f'official-host/{TUPLE}/libboundscheck.so',
}


def verify(root, manifest_sha256, compiler_sha256):
    require(re.fullmatch(r'[0-9a-f]{64}', manifest_sha256), 'SOURCE_TUPLE_MANIFEST_PIN')
    require(digest(root / 'language-tuple.json') == manifest_sha256, 'SOURCE_TUPLE_MANIFEST_DIGEST')
    value = json.loads((root / 'language-tuple.json').read_text())
    require(value['schema'] == 2 and value['platform'] == TUPLE, 'SOURCE_TUPLE_SCHEMA')
    require(value['roles'] == ROLES, 'SOURCE_TUPLE_ROLES')
    require(value['target_runtime'] == 'consumer-built', 'SOURCE_TUPLE_TARGET_ROLE')
    actual = inventory(root)
    require(actual.keys() == value['files'].keys(), 'SOURCE_TUPLE_FILE_SET')
    for name, record in actual.items():
        require(record == value['files'][name], f'SOURCE_TUPLE_PAYLOAD {name}')
    for name, target in ALIASES.items():
        require(actual.get(name) == {'link': target}, f'SOURCE_TUPLE_ALIAS {name}')
    for component in ('cjcj', 'runtime', 'llvm'):
        require(re.fullmatch(r'[0-9a-f]{40}', value['sources'][component]), f'SOURCE_TUPLE_SOURCE {component}')
    require(actual[ROLES['compiler']]['sha256'] == compiler_sha256, 'SOURCE_TUPLE_COMPILER_PIN')
    for role, name in ROLES.items():
        require(actual[name]['sha256'] == value['role_sha256'][role], f'SOURCE_TUPLE_ROLE_DIGEST {role}')
    # The compiler's runtime is frozen independently of the runtime under test.
    require(value['role_sha256']['compiler_runtime'] != value['role_sha256']['official_host_runtime'],
            'SOURCE_TUPLE_HOST_IS_COMPILER_RUNTIME')
    for name in actual:
        require(not (name.startswith('sdk/') and Path(name).name in
                     ('libcangjie-runtime.so', 'libcangjie-runtime.a', 'libboundscheck.so')),
                f'SOURCE_TUPLE_TARGET_INCLUDED {name}')
    compiler = value['build']['compiler']
    std = value['build']['stdlib']
    runtime = value['build']['runtime']
    require(compiler['source']['commit'] == value['sources']['cjcj'], 'SOURCE_TUPLE_COMPILER_SOURCE')
    require(std['source']['commit'] == value['sources']['runtime'], 'SOURCE_TUPLE_STD_SOURCE')
    require(std['compilerSource']['commit'] == value['sources']['cjcj']
            and compiler['production']['source'] == std['compilerSource'], 'SOURCE_TUPLE_BUILD_COMPILER_SOURCE')
    require(std['inputs']['llvmLibrary'] == value['role_sha256']['llvm_library']
            == compiler['production']['llvmLibrarySha256'], 'SOURCE_TUPLE_LLVM_LIBRARY')
    require(runtime['runtime_sha'] == value['sources']['runtime']
            and runtime['build']['sourceCommit'] == value['sources']['runtime'], 'SOURCE_TUPLE_RUNTIME_SOURCE')
    require(runtime['build']['buildInputs']['commands'] and runtime['build']['buildInputs']['compiler_state'],
            'SOURCE_TUPLE_RUNTIME_BUILD_INPUTS')
    require(value['build']['llvm']['LLVM_SHA'] == value['sources']['llvm'], 'SOURCE_TUPLE_LLVM_SOURCE')
    require(compiler['production']['stage'] == 'stage3', 'SOURCE_TUPLE_COMPILER_STAGE')
    require(compiler['artifact']['sha256'] == compiler_sha256, 'SOURCE_TUPLE_COMPILER_LINEAGE')
    require(std['inputs']['compiler'] == compiler['artifact']['sha256']
            == compiler['production']['stdCompilerSha256'], 'SOURCE_TUPLE_STD_COMPILER')
    require(re.fullmatch(r'[0-9a-f]{40}', compiler['production']['bootstrap']['parentSource']['commit']),
            'SOURCE_TUPLE_BOOTSTRAP_SOURCE')
    require(std['products']['core'] == value['role_sha256']['stdlib'], 'SOURCE_TUPLE_STD_OUTPUT')
    for role in ('llc', 'opt'):
        require(std['inputs'][role] == value['role_sha256'][role], f'SOURCE_TUPLE_STD_INPUT {role}')
    require(std['inputs']['runtime'] == value['role_sha256']['compiler_runtime'], 'SOURCE_TUPLE_STD_RUNTIME')
    require(compiler['production']['runtimeSha256'] == value['role_sha256']['compiler_runtime'],
            'SOURCE_TUPLE_COMPILER_RUNTIME')
    for role, file in (('compiler_runtime', 'libcangjie-runtime.so'), ('compiler_boundscheck', 'libboundscheck.so')):
        require(runtime['files'][f'runtime/lib/{TUPLE}/{file}'] == value['role_sha256'][role]
                == runtime['build']['installed'][f'runtime/lib/{TUPLE}/{file}'],
                f'SOURCE_TUPLE_RUNTIME_INPUT {file}')
    require(value['official_host']['identity'], 'SOURCE_TUPLE_OFFICIAL_HOST_IDENTITY')
    for role, file in (('official_host_runtime', 'libcangjie-runtime.so'),
                       ('official_host_boundscheck', 'libboundscheck.so')):
        require(value['official_host']['pins'][file] == value['role_sha256'][role],
                f'SOURCE_TUPLE_OFFICIAL_HOST_PIN {file}')
    return value


def pack(args):
    require(not args.output.exists(), 'SOURCE_TUPLE_OUTPUT_EXISTS')
    # Node runs the existing final-compiler consumer, including the full std
    # payload identity. Neither an archive label nor a user-supplied receipt
    # substitutes for that check.
    build = json.loads(subprocess.check_output([
        args.node, str(Path(__file__).with_name('source_tuple_inputs.mjs')),
        str(args.sdk), str(args.compiler), str(args.std), str(args.runtime),
        args.cjcj_sha, args.runtime_sha, args.llvm_sha, args.run_id, args.run_attempt, str(args.llvm_manifest),
    ], text=True))
    host_pins = {}
    for line in args.host_pins.read_text().splitlines():
        fields = line.split()
        if len(fields) == 2 and fields[0] in ('libcangjie-runtime.so', 'libboundscheck.so'):
            host_pins[fields[0]] = fields[1]
    for file in ('libcangjie-runtime.so', 'libboundscheck.so'):
        require(digest(args.host / file) == host_pins.get(file), f'SOURCE_TUPLE_OFFICIAL_HOST_PIN {file}')
    root = args.output / 'tuple'
    sdk = root / 'sdk'
    sdk.mkdir(parents=True)
    for name in ('include', 'lib', 'modules', 'runtime', 'third_party', 'tools'):
        shutil.copytree(args.sdk / name, sdk / name, symlinks=False)
    (sdk / 'bin').mkdir()
    shutil.copy2(args.compiler / 'cjc', sdk / 'bin/cjcj-stage1')
    for name, target in ALIASES.items():
        (root / name).symlink_to(target)
    # Bootstrap backend entries are workspace wrappers. Ship their verified
    # native executables so the SDK can be relocated after download.
    for name in ('llc', 'opt'):
        backend = sdk / 'third_party/llvm/bin' / name
        shutil.copy2(args.sdk / 'third_party/llvm/bin' / (name + '-stage1'), backend)
        (sdk / 'third_party/llvm/bin' / (name + '-stage1')).unlink()
    for component, source in (('compiler-runtime', args.runtime / 'runtime/lib' / TUPLE),
                              ('official-host', args.host)):
        destination = root / component / TUPLE
        destination.mkdir(parents=True)
        for file in ('libcangjie-runtime.so', 'libboundscheck.so'):
            shutil.copy2(source / file, destination / file)
    for file in tuple(sdk.rglob('*')):
        if file.is_file() and file.name in ('libcangjie-runtime.so', 'libcangjie-runtime.a', 'libboundscheck.so'):
            file.unlink()
    # Retain the exact std receipt and final compiler handoff alongside payloads.
    receipts = root / 'provenance'
    receipts.mkdir()
    for name, value in build.items():
        (receipts / (name + '.json')).write_text(json.dumps(value, indent=2) + '\n')
    value = {'schema': 2, 'platform': TUPLE, 'roles': ROLES,
             'target_runtime': 'consumer-built',
             'sources': {'cjcj': args.cjcj_sha, 'runtime': args.runtime_sha, 'llvm': args.llvm_sha},
             'build': build, 'official_host': {'identity': args.host_identity, 'pins': host_pins, 'pin_file_sha256': digest(args.host_pins)},
             'files': inventory(root),
             'role_sha256': {role: digest(root / name) for role, name in ROLES.items()}}
    (root / 'language-tuple.json').write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    manifest_sha = digest(root / 'language-tuple.json')
    compiler_sha = build['compiler']['artifact']['sha256']
    verify(root, manifest_sha, compiler_sha)
    name = f"source-language-tuple-{args.cjcj_sha}-{args.runtime_sha}.tar.gz"
    archive = args.output / name
    with tarfile.open(archive, 'w:gz', dereference=False) as stream:
        stream.add(root, arcname='tuple')
    shutil.copy2(root / 'language-tuple.json', args.output / 'language-tuple.json')
    (args.output / 'SHA256SUMS').write_text(
        f'{digest(archive)}  {name}\n{manifest_sha}  language-tuple.json\n')
    print(f'SOURCE_TUPLE_PACKED manifest_sha256={manifest_sha} compiler_sha256={compiler_sha}')


def unpack(args):
    require(digest(args.archive) == args.archive_sha256, 'SOURCE_TUPLE_ARCHIVE_DIGEST')
    require(not args.output.exists(), 'SOURCE_TUPLE_OUTPUT_EXISTS')
    with tarfile.open(args.archive, 'r:gz') as archive:
        members = archive.getmembers()
        names = set()
        for entry in members:
            parts = Path(entry.name).parts
            require(parts and parts[0] == 'tuple' and '..' not in parts and not Path(entry.name).is_absolute()
                    and entry.name not in names, 'SOURCE_TUPLE_ARCHIVE_PATH')
            names.add(entry.name)
            relative = '/'.join(parts[1:])
            require(entry.isfile() or entry.isdir() or (entry.issym() and ALIASES.get(relative) == entry.linkname),
                    'SOURCE_TUPLE_ARCHIVE_TYPE')
        args.output.mkdir(parents=True)
        for entry in members:
            if not entry.issym():
                archive.extract(entry, args.output)
        for entry in members:
            if entry.issym():
                (args.output / entry.name).symlink_to(entry.linkname)
    verify(args.output / 'tuple', args.manifest_sha256, args.compiler_sha256)
    print('SOURCE_TUPLE_UNPACKED_VERIFIED')


def activate(args):
    value = verify(args.root, args.manifest_sha256, args.compiler_sha256)
    for file, expected in (('libcangjie-runtime.so', args.target_runtime_sha256),
                           ('libboundscheck.so', args.target_boundscheck_sha256)):
        require(re.fullmatch(r'[0-9a-f]{64}', expected) and digest(args.target / file) == expected,
                f'SOURCE_TUPLE_TARGET_DIGEST {file}')
    require(not args.output.exists(), 'SOURCE_TUPLE_OUTPUT_EXISTS')
    sdk = args.output.resolve() / 'sdk'
    shutil.copytree(args.root / 'sdk', sdk, symlinks=True)
    target = sdk / 'runtime/lib' / TUPLE
    target.mkdir(parents=True, exist_ok=True)
    for file in ('libcangjie-runtime.so', 'libboundscheck.so'):
        shutil.copy2(args.target / file, target / file)
    expected = {name: record for name, record in value['files'].items() if name.startswith('sdk/')}
    for file in ('libcangjie-runtime.so', 'libboundscheck.so'):
        expected[f'sdk/runtime/lib/{TUPLE}/{file}'] = {'sha256': digest(args.target / file),
                                                     'mode': (args.target / file).stat().st_mode & 0o777}
    require(inventory(args.output) == expected, 'SOURCE_TUPLE_ACTIVATION_COPY')
    emit_env(sdk, args.root.resolve() / 'compiler-runtime' / TUPLE, args.target.resolve())
    # Official tools must opt into this role; it is never the compiler loader.
    import shlex
    print('export CJCJ_OFFICIAL_HOST_RUNTIME_LIB_DIR=' + shlex.quote(str(args.root.resolve() / 'official-host' / TUPLE)))


def qualify(args):
    value = verify(args.root, args.manifest_sha256, args.compiler_sha256)
    source_sha = subprocess.check_output(['git', '-C', str(args.runtime_source), 'rev-parse', 'HEAD'], text=True).strip()
    require(source_sha == value['sources']['runtime'], 'SOURCE_TUPLE_GATE_SOURCE')
    clean = subprocess.run(['git', '-C', str(args.runtime_source), 'diff', '--quiet', 'HEAD', '--',
                            'runtime/tests/gc_unit'], check=False).returncode
    require(clean == 0, 'SOURCE_TUPLE_GATE_SOURCE_MODIFIED')
    # Use the shipped activation path, then execute the unchanged runtime gate.
    # The output is fresh: no previous ELF/stamp can satisfy this qualification.
    activate(args)
    output = args.output.resolve()
    env = dict(os.environ, CJC=str(output / 'sdk/bin/cjc'), CANGJIE_HOME=str(output / 'sdk'),
               GC_UNIT_CJC_RUNTIME_LIB_DIR=str(args.root.resolve() / 'compiler-runtime' / TUPLE),
               GCV2_RUNTIME_LIB_DIR=str(args.target.resolve()), GC_UNIT_GATE_LANGUAGE_TESTS='only',
               GC_UNIT_OUT=str(output / 'gate'))
    gate = args.runtime_source / 'runtime/tests/gc_unit/gate_gc_unit.sh'
    log = output / 'gate.log'
    with log.open('w') as stream:
        result = subprocess.run(['bash', str(gate)], env=env, stdout=stream, stderr=subprocess.STDOUT)
    products = {}
    for name in ('finalizer_trigger', 'phase_entry_trigger'):
        file = output / 'gate' / name
        if file.is_file() and file.read_bytes()[:4] == b'\x7fELF':
            products[f'gate/{name}'] = digest(file)
    receipt = {'schema': 1, 'manifest_sha256': args.manifest_sha256,
               'compiler_sha256': args.compiler_sha256, 'runtime_source_sha': source_sha,
               'compiler_runtime_sha256': value['role_sha256']['compiler_runtime'],
               'target_runtime_sha256': args.target_runtime_sha256,
               'target_boundscheck_sha256': args.target_boundscheck_sha256,
               'gate_sha256': digest(gate), 'gate_log_sha256': digest(log),
               'gate_rc': result.returncode, 'elf': products}
    (output / 'qualification.json').write_text(json.dumps(receipt, indent=2) + '\n')
    require(result.returncode == 0 and len(products) == 2, 'SOURCE_TUPLE_LANGUAGE_GATE')
    print('SOURCE_TUPLE_QUALIFIED')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    producer = commands.add_parser('pack')
    for name in ('sdk', 'compiler', 'std', 'runtime', 'host', 'output', 'llvm-manifest'):
        producer.add_argument('--' + name, type=Path, required=True)
    for name in ('cjcj-sha', 'runtime-sha', 'llvm-sha', 'run-id', 'run-attempt', 'host-identity'):
        producer.add_argument('--' + name, required=True)
    producer.add_argument('--node', default='node')
    producer.add_argument('--host-pins', type=Path, default=Path(__file__).parent.parent / 'bootstrap/stage1_host_identities.txt')
    check = commands.add_parser('verify')
    check.add_argument('--root', type=Path, required=True)
    extract = commands.add_parser('unpack')
    extract.add_argument('--archive', type=Path, required=True)
    extract.add_argument('--archive-sha256', required=True)
    extract.add_argument('--output', type=Path, required=True)
    activation = commands.add_parser('activate')
    for name in ('root', 'target', 'output'):
        activation.add_argument('--' + name, type=Path, required=True)
    for name in ('target-runtime-sha256', 'target-boundscheck-sha256'):
        activation.add_argument('--' + name, required=True)
    qualification = commands.add_parser('qualify')
    for name in ('root', 'target', 'output', 'runtime-source'):
        qualification.add_argument('--' + name, type=Path, required=True)
    for name in ('target-runtime-sha256', 'target-boundscheck-sha256'):
        qualification.add_argument('--' + name, required=True)
    for command in (check, extract, activation, qualification):
        command.add_argument('--manifest-sha256', required=True)
        command.add_argument('--compiler-sha256', required=True)
    args = parser.parse_args()
    if args.command == 'pack':
        pack(args)
    elif args.command == 'verify':
        verify(args.root, args.manifest_sha256, args.compiler_sha256)
        print('SOURCE_TUPLE_VERIFIED')
    elif args.command == 'unpack':
        unpack(args)
    elif args.command == 'qualify':
        qualify(args)
    else:
        activate(args)


if __name__ == '__main__':
    main()
