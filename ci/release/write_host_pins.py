#!/usr/bin/env python3
"""Bind the selected official SDK and independently pinned host LLVM for this run."""
import hashlib
import os
from pathlib import Path
import re
import sys


def main():
    output = Path(sys.argv[1])
    sdk = Path(os.environ['CJCJ_SRCBUILD_HOST_SDK'])
    runtime = sdk / 'runtime/lib/linux_x86_64_cjnative'
    inputs = (
        ('libcangjie-runtime.so', runtime / 'libcangjie-runtime.so', 'CJCJ_HOST_RUNTIME_SHA256'),
        ('libboundscheck.so', runtime / 'libboundscheck.so', 'CJCJ_HOST_BOUNDSCHECK_SHA256'),
        ('libLLVM-15.so', Path(os.environ['CJCJ_BOOTSTRAP_HOST_LLVM_SO']), 'CJCJ_BOOTSTRAP_HOST_LLVM_SHA256'),
    )
    rows = []
    for name, file, key in inputs:
        expected = os.environ[key]
        if not re.fullmatch('[0-9a-f]{64}', expected):
            raise SystemExit(f'HOST_PIN_REQUIRED {key}')
        actual = hashlib.sha256()
        with file.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                actual.update(block)
        if actual.hexdigest() != expected:
            raise SystemExit(f'HOST_PIN_MISMATCH {name}')
        rows.append(f'{name} {expected}\n')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(''.join(rows))
    print(f'HOST_PINS_BOUND files={len(rows)} output={output}')


if __name__ == '__main__':
    main()
