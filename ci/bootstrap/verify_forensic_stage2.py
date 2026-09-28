#!/usr/bin/env python3
"""Check real bootstrap ELFs; run after building, never against dry-run output."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def std_lines(decoded):
    """Compare source/line membership, excluding relocated code addresses."""
    rows, source = set(), ''
    for line in decoded.splitlines():
        if line.endswith(':') or line.endswith(':[++]'):
            source = line.split('/stdlib/', 1)[1].rstrip(':') if '/stdlib/' in line else ''
        row = re.match(r'\S+\.cj\s+([1-9][0-9]*)\s+0x[0-9a-fA-F]+', line)
        if source and row:
            rows.add((source, int(row[1])))
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--release', type=Path, required=True)
    parser.add_argument('--release-sha256', required=True)
    parser.add_argument('--forensic', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    checks = {}
    commands = []

    def check(name, passed, detail):
        checks[name] = {'passed': bool(passed), 'detail': detail}
        print(f"{'PASS' if passed else 'FAIL'} {name}: {detail}")

    def run(label, command):
        result = subprocess.run(command, text=True, capture_output=True,
                                env={**os.environ, 'LC_ALL': 'C'})
        (args.output / f'{label}.stdout').write_text(result.stdout)
        (args.output / f'{label}.stderr').write_text(result.stderr)
        commands.append({'command': command, 'rc': result.returncode})
        if result.returncode:
            raise RuntimeError(f'{label} rc={result.returncode}; see {args.output}')
        return result.stdout

    release_sha = sha256(args.release)
    forensic_sha = sha256(args.forensic)
    # Independent assertions: a missing line table must not hide this result.
    check('release-unchanged', release_sha == args.release_sha256, release_sha)
    sections = run('sections', ['readelf', '-SW', str(args.forensic)])
    check('forensic-debug-line', bool(re.search(r'\s\.debug_line\s', sections)), '.debug_line section')
    decoded = run('decodedline', ['objdump', '--dwarf=decodedline', str(args.forensic)])
    release_decoded = run('release-decodedline', ['objdump', '--dwarf=decodedline', str(args.release)])
    release_std, forensic_std = std_lines(release_decoded), std_lines(decoded)
    check('std-lines-unchanged', bool(release_std) and release_std == forensic_std,
          f'release={len(release_std)} forensic={len(forensic_std)} '
          f'added={len(forensic_std - release_std)} removed={len(release_std - forensic_std)}')
    # Use source package paths, not the spelling of the disposable checkout.
    paths = [line for line in decoded.splitlines()
             if re.search(r'/packages/[^/]+/src/.*\.cj:', line)]
    check('forensic-cjcj-lines', bool(paths), f'cjcj package source headers={len(paths)}')
    symbols = run('symbols', ['nm', '-S', '--defined-only', str(args.forensic)])
    symbol = '_CN9cjcj:chir11CHIRBuilder17GetAllCustomTypesHv'
    match = re.search(r'^([0-9a-fA-F]+)\s+([0-9a-fA-F]+)\s+\S\s+' + symbol + r'$', symbols, re.M)
    addresses = []
    if match:
        start, size = (int(value, 16) for value in match.groups())
        # Select a real line-table PC inside the function, including past its prologue.
        addresses = sorted({int(pc, 16) for pc in re.findall(r'\.cj\s+[1-9][0-9]*\s+(0x[0-9a-fA-F]+)', decoded)
                            if start <= int(pc, 16) < start + size})
    location = 'no line-table PC in CHIRBuilder::GetAllCustomTypes'
    if addresses:
        location = run('addr2line', ['addr2line', '-e', str(args.forensic), '-f', '-C', '-i', hex(addresses[0])]).strip()
    check('forensic-source-location', bool(re.search(r'CHIRBuilder\.cj:[1-9][0-9]*', location)), location)
    result = {'release_sha256': release_sha, 'forensic_sha256': forensic_sha,
              'checks': checks, 'commands': commands}
    (args.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if all(item['passed'] for item in checks.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
