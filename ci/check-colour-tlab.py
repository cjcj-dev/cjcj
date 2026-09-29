#!/usr/bin/env python3
"""Inspect the linked x86-64 product, including its statically linked std.

Signatures: llvm X86MCInstLower.cpp TLAB allocation sequences (67934046).
This is a byte-layout check, not a claim that the program completed a load.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def inspect(file):
    data = Path(file).read_bytes()
    old_object = data.count(bytes.fromhex('488b12488b02488b4a08'))
    old_array = data.count(bytes.fromhex('4d8b09498b014d8b5108'))
    new_object = data.count(bytes.fromhex('498b17488b02488b4a08'))
    new_array = data.count(bytes.fromhex('498b014d8b5108')) - old_array
    result = subprocess.run(['nm', '-u', str(file)], capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f'nm failed rc={result.returncode}: {result.stderr}')
    refs = sorted({line.split()[-1] for line in result.stdout.splitlines()
                   if line.split() and line.split()[-1].split('@')[0].startswith('g_cjLoad')})
    return dict(file=str(file), sha256=hashlib.sha256(data).hexdigest(),
                three_level=old_object + old_array, two_level=new_object + new_array,
                colour_refs=refs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('files', nargs='+', type=Path)
    args = parser.parse_args()
    failed = False
    for file in args.files:
        row = inspect(file)
        row['assertions'] = {'three_level_zero': row['three_level'] == 0,
                             'two_level_present': row['two_level'] > 0,
                             'colour_refs_present': bool(row['colour_refs'])}
        print(json.dumps(row), flush=True)
        failed |= not all(row['assertions'].values())
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
