#!/usr/bin/env python3
"""Install/verify the two driver names against the supplied compiler producer."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil

NAMES = ('cjc', 'cjc-frontend', 'cjc-upstream-oracle', 'cjc-oracle',
         'cjcj-stage1', 'cjcj-stage2', 'cjcj')
RECORD = 'compiler-lineage.json'


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else digest(stream)


def digest(stream):
    value = hashlib.sha256()
    for chunk in iter(lambda: stream.read(1024 * 1024), b''):
        value.update(chunk)
    return value.hexdigest()


def verify(sdk, expected_producer_sha256=None):
    record = json.loads((sdk / RECORD).read_text())
    expected = record['installed_sha256']
    if len(expected) != 64 or not record.get('producer_sha256'):
        raise ValueError('COMPILER_IDENTITY invalid producer record')
    # The installation record establishes copy consistency, not producer origin.
    # A bootstrap consumer must supply its build's hash independently of this SDK.
    if expected_producer_sha256 is not None:
        if len(expected_producer_sha256) != 64 or any(c not in '0123456789abcdef' for c in expected_producer_sha256):
            raise ValueError('COMPILER_IDENTITY invalid expected producer SHA-256')
        if record['producer_sha256'] != expected_producer_sha256 or expected != expected_producer_sha256:
            raise ValueError('COMPILER_IDENTITY independent bootstrap producer mismatch')
    rejected = []
    for name in NAMES:
        path = sdk / 'bin' / name
        if name in ('cjc', 'cjc-frontend', 'cjcj-stage1'):
            if not path.is_file() or sha(path) != expected:
                rejected.append(name + ': producer hash mismatch')
            if name != 'cjcj-stage1' and (not path.is_symlink() or os.readlink(path) != 'cjcj-stage1'):
                rejected.append(name + ': expected same-directory cjcj-stage1 link')
            if name == 'cjcj-stage1' and path.is_symlink():
                rejected.append(name + ': producer must be a physical copy')
        elif path.exists() or path.is_symlink():
            rejected.append(name + ': stale compiler component')
    if rejected:
        raise ValueError('COMPILER_IDENTITY ' + '; '.join(rejected))
    return record


def install(sdk, product):
    expected = sha(product)
    # Read the producer before removing any inherited aliases.
    if product.resolve().is_relative_to((sdk / 'bin').resolve()):
        raise ValueError('COMPILER_IDENTITY producer must be outside destination bin')
    binary = sdk / 'bin'
    binary.mkdir(parents=True, exist_ok=True)
    for name in NAMES:
        (binary / name).unlink(missing_ok=True)
    shutil.copyfile(product, binary / 'cjcj-stage1')
    (binary / 'cjcj-stage1').chmod(0o755)
    for name in ('cjc', 'cjc-frontend'):
        (binary / name).symlink_to('cjcj-stage1')
    (sdk / RECORD).write_text(json.dumps({'producer_sha256': expected,
        'installed_sha256': expected, 'source': str(product.resolve()), 'transformation': 'copy'}, indent=2) + '\n')
    return verify(sdk)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sdk', type=Path)
    parser.add_argument('--install', type=Path)
    parser.add_argument('--expected-producer-sha256', help='trusted build output hash, obtained outside the installed SDK')
    args = parser.parse_args()
    if args.install and args.expected_producer_sha256:
        parser.error('--expected-producer-sha256 is a consumer constraint; install separately')
    try:
        record = install(args.sdk, args.install) if args.install else verify(args.sdk, args.expected_producer_sha256)
    except (OSError, ValueError, KeyError) as error:
        parser.exit(1, str(error) + '\n')
    print(json.dumps(record, sort_keys=True))


if __name__ == '__main__':
    main()
