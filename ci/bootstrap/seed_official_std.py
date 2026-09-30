#!/usr/bin/env python3
"""Retain the official host std for stage0; fork std first builds in stage1."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def sha(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def selected(sdk, tuple_name):
    files = set()
    modules = sdk / 'modules' / tuple_name
    for file in modules.rglob('*'):
        if file.is_file():
            files.add(file.relative_to(sdk).as_posix())
    for parent in ('lib', 'runtime/lib'):
        for file in (sdk / parent / tuple_name).glob('libcangjie-std-*'):
            if file.is_file():
                files.add(file.relative_to(sdk).as_posix())
    files.add('lib/libstdFFI.so')
    for required in (f'modules/{tuple_name}/std.cjo', f'lib/{tuple_name}/libcangjie-std-core.a',
                     f'runtime/lib/{tuple_name}/libcangjie-std-core.so', 'lib/libstdFFI.so'):
        if required not in files or not (sdk / required).is_file():
            raise ValueError(f'OFFICIAL_STD_SEED_MISSING {required}')
    return {name: {'sha256': sha(sdk / name), 'mode': (sdk / name).stat().st_mode & 0o777}
            for name in sorted(files)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--tuple', required=True)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    sdk = args.sdk.resolve()
    files = selected(sdk, args.tuple)
    identity = hashlib.sha256(json.dumps(files, sort_keys=True).encode()).hexdigest()
    if args.output is None:
        print(identity)
        return
    output = args.output.resolve()
    if output == sdk or output in sdk.parents or sdk in output.parents or output == Path('/'):
        raise ValueError('OFFICIAL_STD_SEED_OUTPUT_ALIASES_SDK')
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    for name, record in files.items():
        destination = output / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(sdk / name, destination, follow_symlinks=True)
        if sha(destination) != record['sha256']:
            raise ValueError(f'OFFICIAL_STD_SEED_COPY_MISMATCH {name}')
    receipt = {'role': 'official-host-bootstrap-std', 'sdk': str(sdk),
               'identity_sha256': identity, 'files': files}
    (output / 'BOOTSTRAP-STD.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(f'OFFICIAL_STD_SEED_PASS files={len(files)} identity_sha256={identity}')


if __name__ == '__main__':
    main()
