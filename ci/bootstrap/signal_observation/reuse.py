#!/usr/bin/env python3
"""Verified relocation of the retained candidate. No producer or launch here."""
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import posixpath
import shutil
import struct
import sys
import tarfile

HERE = Path(__file__).resolve().parent
ARCHIVE_SHA = 'b83f20b696fa746fb0fb3fe27ea20cb8a839d4bf30f90c7164ac251b2912f884'
MANIFEST_SHA = 'f0f87f0c256052a52e2bcee52c63e06b01db0d5871a6b304e1dc7e20e995c48b'
SOURCE_SHA = '6dd9c429fe33903ac1a231ed19c8d8e8d539ee62'
TUPLE = 'darwin_aarch64_cjnative'
IDENTITIES = {
    'candidate/cjc': '3bee36eb5a9b4c17355bad296c7a4e4e2304f07a36f8cfd9b94ecc2fa014d254',
    'candidate/Signal.cj': '8d586c844cdf11619af47c8c986e330b650754889e29980e4834e9f67de7588b',
    'host-runtime/runtime/lib/' + TUPLE + '/libcangjie-runtime.dylib': '55c5945ee0837d31cb996994d0d16863233a2abd7a64381a2cdb973f51dae516',
    'host-runtime/runtime/lib/' + TUPLE + '/libboundscheck.dylib': '4814dc1585b4ef71fade765f1bd40fdaae7ac21c3fbf75fb9b0437ddbb110ea9',
    'sdk-stage0-run/third_party/llvm/lib/libLLVM.dylib': 'c48dafd8db987e2309e58755a43736efe7c3ea7ac048b6392ea2cd06a0cb5b92',
    'sdk-stage0/third_party/llvm/lib/libLLVM.dylib': '0429b5e9c149ce1b233621adea6381c6b2defd0e23a21081a382ea1fdada95e3',
}


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def require(ok, reason):
    if not ok:
        raise ValueError(reason)


def inside(root, path):
    root = Path(root).resolve(strict=True)
    path = Path(path)
    require(path.resolve(strict=True).is_relative_to(root), 'outside-entity-root: ' + str(path))
    require(not path.is_symlink(), 'entity-is-link: ' + str(path))
    return path.resolve(strict=True)


def materialize(archive, manifest, source, destination):
    require(digest(archive) == ARCHIVE_SHA, 'archive-identity')
    require(digest(manifest) == MANIFEST_SHA, 'manifest-identity')
    require(Path(source).read_text().strip() == SOURCE_SHA, 'source-identity')
    destination = Path(destination).absolute()
    require(not destination.exists(), 'destination-exists')
    # Validate every archive name and link target before writing any entities.
    with tarfile.open(archive) as tar:
        members = {}
        for item in tar.getmembers():
            name = item.name.rstrip('/')
            require(name not in members, 'duplicate-archive-member')
            require(not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts
                    and (name == 'keep' or name.startswith('keep/')), 'archive-path')
            require(item.isfile() or item.isdir() or item.issym() or item.islnk(), 'archive-type')
            members[name] = item

        def resolve(name, seen=()):
            require(name in members and name not in seen, 'archive-link-target: ' + name)
            item = members[name]
            if item.issym() or item.islnk():
                require(not PurePosixPath(item.linkname).is_absolute(), 'absolute-archive-link')
                target = posixpath.normpath(posixpath.join(posixpath.dirname(name), item.linkname)
                                           if item.issym() else item.linkname)
                require(target.startswith('keep/'), 'external-archive-link')
                return resolve(target, seen + (name,))
            require(item.isfile() or item.isdir(), 'archive-link-type')
            return item

        for name in members:
            resolve(name)
        destination.mkdir(parents=True)
        mapping = []
        for name, item in members.items():
            target = destination / name
            original = resolve(name)
            if original.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            with tar.extractfile(original) as src, target.open('wb') as dst:
                shutil.copyfileobj(src, dst)
            target.chmod(original.mode & 0o777)
            mapping.append({'archive_path': name, 'resolved_archive_path': original.name,
                            'path': str(target), 'sha256': digest(target),
                            'was_link': item.issym() or item.islnk()})
    # Preserve the historical manifest; its absolute runner paths are evidence only.
    covered = set()
    for line in Path(manifest).read_text().splitlines():
        expected, historical = line.split(None, 1)
        prefix = '/signal-observation/keep/'
        require(prefix in historical, 'historical-manifest-prefix')
        relative = historical.split(prefix, 1)[1]
        require('..' not in PurePosixPath(relative).parts and not relative.startswith('/'), 'manifest-path')
        path = inside(destination / 'keep', destination / 'keep' / relative)
        require(digest(path) == expected, 'manifest-content: ' + relative)
        require(relative not in covered, 'duplicate-manifest-path')
        covered.add(relative)
    for relative, expected in IDENTITIES.items():
        require(digest(inside(destination / 'keep', destination / 'keep' / relative)) == expected,
                'entity-identity: ' + relative)
    shutil.copyfile(manifest, destination / 'original-keep.sha256')
    shutil.copyfile(source, destination / 'original-candidate-source.sha')
    receipt = {'archive_sha256': ARCHIVE_SHA, 'source_sha': SOURCE_SHA,
               'root': str(destination / 'keep'), 'mapping': mapping,
               'historical_manifest_paths': sorted(covered),
               'additional_regular_files': [m for m in mapping if not m['was_link'] and
                                           m['archive_path'][5:] not in covered]}
    (destination / 'mapping-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return destination / 'keep'


def select(root):
    root = Path(root).resolve(strict=True)
    receipt = json.loads((root.parent / 'mapping-receipt.json').read_text())
    require(receipt['root'] == str(root) and receipt['archive_sha256'] == ARCHIVE_SHA
            and receipt['source_sha'] == SOURCE_SHA, 'entity-root-receipt')
    selected = {relative: inside(root, root / relative) for relative in IDENTITIES}
    for relative, path in selected.items():
        require(digest(path) == IDENTITIES[relative], 'entity-identity: ' + relative)
    sdk = inside(root, root / 'sdk-stage0-run')
    runtime = inside(root, root / 'host-runtime/runtime/lib' / TUPLE)
    llvm = inside(root, sdk / 'third_party/llvm/lib/libLLVM.dylib')
    directories = [runtime, sdk / 'runtime/lib' / TUPLE, sdk / 'lib' / TUPLE,
                   llvm.parent, sdk / 'tools/lib']
    directories = [inside(root, path) for path in directories]
    libraries = {name: inside(root, runtime / name)
                 for name in ('libcangjie-runtime.dylib', 'libboundscheck.dylib')}
    libraries['libLLVM.dylib'] = llvm
    # Expected identities and loader search must refer to the same chosen files.
    for name, path in libraries.items():
        first = next((directory / name for directory in directories if (directory / name).is_file()), None)
        require(first == path, 'loader-expected-path: ' + name)
    return {'root': str(root), 'binary': str(selected['candidate/cjc']),
            'environment': {'CANGJIE_HOME': str(sdk),
                            'DYLD_LIBRARY_PATH': ':'.join(map(str, directories))},
            'expected_libraries': {name: digest(path) for name, path in libraries.items()},
            'selected_libraries': {name: str(path) for name, path in libraries.items()},
            'roles': {'compilation_sdk': str(root / 'sdk-stage0'), 'process_sdk': str(sdk)},
            'historical_sdk_lock_sha256': digest(sdk / 'SDK.lock.json')}


def validate_modules(result, selection):
    for name, path in selection['selected_libraries'].items():
        found = [m for m in result.get('modules', []) if Path(m['path']).name == name]
        require(len(found) == 1, 'module-count: ' + name)
        module = found[0]
        actual = inside(selection['root'], module['path'])
        require(module['path'] == path and str(actual) == path, 'module-path: ' + name)
        require(module.get('sha256') == selection['expected_libraries'][name]
                and digest(actual) == module['sha256'], 'module-hash: ' + name)


def native_dependency():
    # Read-only qualification of the unarchived absolute dependency; never install it.
    path = Path('/opt/homebrew/opt/zstd/lib/libzstd.1.dylib')
    require(path.is_file(), 'NOT_RUN: missing-zstd')
    data = path.read_bytes()
    require(len(data) >= 8 and data[:4] == b'\xcf\xfa\xed\xfe'
            and struct.unpack('<I', data[4:8])[0] == 0x0100000c,
            'NOT_RUN: zstd-not-arm64-mach-o')
    return {'path': str(path), 'resolved_path': str(path.resolve()), 'sha256': digest(path),
            'architecture': 'arm64', 'bytes': len(data)}


if __name__ == '__main__':
    if sys.argv[1] == 'materialize' and len(sys.argv) == 6:
        print(materialize(*sys.argv[2:]))
    else:
        raise SystemExit('usage: reuse.py materialize ARCHIVE MANIFEST SOURCE NEW_DESTINATION')
