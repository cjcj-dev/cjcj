#!/usr/bin/env python3
"""Install the pinned AST producer payload into a private compilation SDK."""
import hashlib
from pathlib import Path
import shutil
import sys


def install(artifact, sdk, triple):
    artifact, sdk = Path(artifact), Path(sdk)
    # SHA256SUMS is authenticated by the artifact identity in ci/ast_support.
    for line in (artifact / 'SHA256SUMS').read_text().splitlines():
        expected, name = line.split('  ', 1)
        file = artifact / name
        actual = hashlib.sha256(file.read_bytes()).hexdigest()
        if actual != expected:
            raise ValueError(f'AST_INPUT_DIGEST_MISMATCH {name}')
    for name in ('include', 'schema', 'third_party/flatbuffers'):
        shutil.copytree(artifact / name, sdk / name, dirs_exist_ok=True, symlinks=False)
    dest = sdk / 'lib' / triple
    dest.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(artifact / 'libcangjie-ast-support.a', dest / 'libcangjie-ast-support.a')
    print(f'STD_SDK_INPUTS_INSTALLED sdk={sdk} triple={triple}')


if __name__ == '__main__':
    install(*sys.argv[1:])
