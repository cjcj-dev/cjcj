#!/usr/bin/env python3
"""Exercise the real compiler's RAW serializer; never construct CHIR in the test.

Use the same source/imports for every arm. A reference requires exact bytes.
The publication assertion checks the four ID-indexed union vectors, including
entries discovered while draining another queue (schema slots 10 through 24).
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def published(data):
    def number(fmt, at):
        return struct.unpack_from('<' + fmt, data, at)[0]

    root = number('I', 0)
    vt = root - number('i', root)

    def pointer(slot):
        field = number('H', vt + slot) if slot < number('H', vt) else 0
        return root + field + number('I', root + field) if field else 0

    result = {}
    for name, slot in [('types', 10), ('values', 14), ('expressions', 18), ('definitions', 22)]:
        tags, offsets = pointer(slot), pointer(slot + 2)
        count = number('I', tags) if tags else 0
        other = number('I', offsets) if offsets else 0
        missing = []
        for i in range(min(count, other)):
            entry = offsets + 4 + i * 4
            offset = number('I', entry)
            if data[tags + 4 + i] == 0 or offset == 0 or entry + offset >= len(data):
                missing.append(i + 1)
        result[name] = {'tags': count, 'offsets': other, 'unpublished_ids': missing}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--input', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--import-dir', action='append', default=[], type=Path)
    parser.add_argument('--reference', type=Path)
    parser.add_argument('--timeout', type=float, default=900)
    parser.add_argument('--control-input', type=Path, help='ordinary object compilation, without serialization')
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=False)
    command = [str(args.compiler)]
    if args.input.is_dir():
        command.append('-p')
    command += [str(args.input), '--jobs', '1', '--profile-compile-time',
                '--emit-chir=raw', '--output-type=staticlib', '-o', str(args.out / 'output.chir')]
    for path in args.import_dir:
        command += ['--import-path', str(path)]
    result = {'command': command, 'compiler': str(args.compiler), 'elf_sha256': sha(args.compiler),
              'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True).strip()}
    sources = sorted(args.input.rglob('*.cj')) if args.input.is_dir() else [args.input]
    result['sources'] = {str(path): sha(path) for path in sources}
    start = time.monotonic()
    with (args.out / 'compile.log').open('w') as log:
        try:
            result['compile_rc'] = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                                  timeout=args.timeout).returncode
        except subprocess.TimeoutExpired:
            result['compile_rc'] = 'TIMEOUT'
    result['wall'] = time.monotonic() - start
    result['uptime_after'] = subprocess.check_output(['uptime'], text=True).strip()
    checks = {'compile': result['compile_rc'] == 0}
    artifact = args.out / 'output.chir'
    if checks['compile'] and artifact.is_file():
        result['output_sha256'] = sha(artifact)
        result['published'] = published(artifact.read_bytes())
        checks['queue_publication'] = all(item['tags'] == item['offsets'] and not item['unpublished_ids']
                                          for item in result['published'].values())
        checks['nonempty_graph'] = all(result['published'][key]['tags'] > 0
                                       for key in ('types', 'values', 'expressions'))
        if args.reference:
            checks['exact_bytes'] = result['output_sha256'] == sha(args.reference)
        profiles = list(args.out.glob('*.time.prof'))
        result['profiles'] = {p.name: json.loads(p.read_text()) for p in profiles}
        checks['phase_scopes'] = any('AST to CHIR Translation' in p.get('CHIR', {}) and
                                    'serialization: raw' in p.get('CHIR', {})
                                    for p in result['profiles'].values())
    else:
        checks['queue_publication'] = False
    if args.control_input:
        control = [str(args.compiler)] + (['-p'] if args.control_input.is_dir() else [])
        control += [str(args.control_input), '--experimental', '--output-type=obj', '--jobs', '1',
                    '-o', str(args.out / 'control.o')]
        for path in args.import_dir:
            control += ['--import-path', str(path)]
        with (args.out / 'control.log').open('w') as log:
            result['control_rc'] = subprocess.run(control, stdout=log, stderr=subprocess.STDOUT,
                                                   timeout=args.timeout).returncode
        checks['object_control'] = result['control_rc'] == 0 and (args.out / 'control.o').is_file()
    result['checks'] = checks
    for name, passed in checks.items():
        print(f"ASSERT {name}: {'PASS' if passed else 'FAIL'}")
    (args.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if all(checks.values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
