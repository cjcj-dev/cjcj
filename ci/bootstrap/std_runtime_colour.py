#!/usr/bin/env python3
"""Shared std/runtime pairing from the declared colour/host export difference."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import sys


def symbols(file, *, runtime=False):
    command = ['nm', '-D', '--defined-only'] if runtime else ['nm', '-A']
    result = subprocess.run([*command, str(file)], capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f'nm rc={result.returncode} file={file}: {result.stderr.strip()}')
    found = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if len(fields) < 2:
            continue
        kind, name = fields[-2:]
        name = name.split('@', 1)[0]
        if (runtime and kind not in ('U', 'w', 'v')) or (not runtime and kind == 'U'):
            found.add(name)
    return found


def sha256(file):
    return hashlib.sha256(Path(file).read_bytes()).hexdigest()


def colour_symbols(colour_runtime, host_runtime):
    identity = (f'colour_runtime={colour_runtime} colour_runtime_sha256={sha256(colour_runtime)} '
                f'host_runtime={host_runtime} host_runtime_sha256={sha256(host_runtime)}')
    exports = symbols(colour_runtime, runtime=True) - symbols(host_runtime, runtime=True)
    print(f'STD-COLOUR-EXPORTS {identity} colour_only={",".join(sorted(exports)) or "none"}',
          file=sys.stderr)
    if not exports:
        raise ValueError(f'empty colour-only runtime export set {identity}')
    return exports


def assert_pair(runtime, std, source, exports, host_runtime):
    identity = (f'runtime={runtime} runtime_sha256={sha256(runtime)} '
                f'std={std} std_sha256={sha256(std)} std_source={source}')
    try:
        rt_hits = symbols(runtime, runtime=True) - symbols(host_runtime, runtime=True)
        std_hits = symbols(std) & exports
    except (OSError, ValueError) as error:
        raise ValueError(f'{identity} inspection={error}') from error
    detail = (f'{identity} runtime_symbols={",".join(sorted(rt_hits)) or "none"} '
              f'std_symbols={",".join(sorted(std_hits)) or "none"}')
    if bool(rt_hits) != bool(std_hits):
        raise ValueError(f'STD-RUNTIME-COLOUR-MISMATCH {detail}')
    print(f'STD-RUNTIME-PAIR-OK {detail}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--colour-runtime', type=Path, required=True)
    parser.add_argument('--host-runtime', type=Path, required=True)
    parser.add_argument('--std-colour', type=Path, help='Print 1/0 for the shared std predicate')
    parser.add_argument('--runtime', type=Path)
    parser.add_argument('--std', type=Path)
    parser.add_argument('--source', help='Original std install prefix or inherited SDK')
    args = parser.parse_args()
    try:
        exports = colour_symbols(args.colour_runtime, args.host_runtime)
        if args.std_colour is not None:
            if args.runtime or args.std or args.source:
                parser.error('--std-colour cannot be combined with pair arguments')
            print(int(bool(symbols(args.std_colour) & exports)))
        else:
            if not args.runtime or not args.std or not args.source:
                parser.error('pair check requires --runtime, --std and --source')
            assert_pair(args.runtime, args.std, args.source, exports, args.host_runtime)
    except (OSError, ValueError) as error:
        print(f'STD-RUNTIME-CHECK-FAIL {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
