#!/usr/bin/env python3
"""One exact symbol predicate for SDK assembly and stage3 std validation."""
import argparse
import hashlib
from pathlib import Path
import subprocess
import sys

# Runtime exports the mask; std can load it directly or through its TLS offset.
RUNTIME_SYMBOL = 'g_cjLoadBadMask'
STD_SYMBOLS = (RUNTIME_SYMBOL, 'g_cjLoadBadMaskOffset')


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
        # Mach-O nm prefixes C symbols with one underscore.
        if name.startswith('_g_'):
            name = name[1:]
        if runtime:
            if kind not in ('U', 'w', 'v') and name == RUNTIME_SYMBOL:
                found.add(name)
        elif kind == 'U' and name in STD_SYMBOLS:
            found.add(name)
    return sorted(found)


def sha256(file):
    return hashlib.sha256(Path(file).read_bytes()).hexdigest()


def assert_pair(runtime, std, source):
    # Capture identities even on inspection failures: absence is not an nm error.
    rt_sha, std_sha = sha256(runtime), sha256(std)
    identity = (f'runtime={runtime} runtime_sha256={rt_sha} '
                f'std={std} std_sha256={std_sha} std_source={source}')
    try:
        rt_hits, std_hits = symbols(runtime, runtime=True), symbols(std)
    except (OSError, ValueError) as error:
        raise ValueError(f'{identity} inspection={error}') from error
    detail = (f'{identity} runtime_symbols={",".join(rt_hits) or "none"} '
              f'std_symbols={",".join(std_hits) or "none"} '
              f'std_expected={",".join(STD_SYMBOLS)}')
    if bool(rt_hits) != bool(std_hits):
        raise ValueError(f'STD-RUNTIME-COLOUR-MISMATCH {detail}')
    print(f'STD-RUNTIME-PAIR-OK {detail}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--std-colour', type=Path, help='Print 1/0 for the shared std predicate')
    parser.add_argument('--runtime', type=Path)
    parser.add_argument('--std', type=Path)
    parser.add_argument('--source', help='Original std install prefix or inherited SDK')
    args = parser.parse_args()
    try:
        if args.std_colour is not None:
            if args.runtime or args.std or args.source:
                parser.error('--std-colour cannot be combined with pair arguments')
            print(int(bool(symbols(args.std_colour))))
        else:
            if not args.runtime or not args.std or not args.source:
                parser.error('pair check requires --runtime, --std and --source')
            assert_pair(args.runtime, args.std, args.source)
    except (OSError, ValueError) as error:
        print(f'STD-RUNTIME-CHECK-FAIL {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
