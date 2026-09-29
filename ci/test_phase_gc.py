#!/usr/bin/env python3
"""Compare completed explicit collections through the real compiler CLI.

Capture a reference with the baseline compiler, then pass its result.json with
--reference for the candidate. Uses the host runtime's existing GC log; no
compiler instrumentation or replacement runtime entry points are involved.
"""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--reference', type=Path)
    args = parser.parse_args()
    compiler, sdk, out = (p.resolve() for p in (args.compiler, args.sdk, args.out))
    out.mkdir(parents=True, exist_ok=False)
    runtime = sdk / 'runtime/lib/linux_x86_64_cjnative'
    env = os.environ.copy()
    env.update(CANGJIE_HOME=str(sdk), cjHeapSize='32GB', MRT_LOG_LEVEL='d',
               MRT_LOG_FILE_SIZE='128mb',
               LD_LIBRARY_PATH=':'.join(map(str, [runtime,
                   sdk / 'lib/linux_x86_64_cjnative', sdk / 'third_party/llvm/lib',
                   sdk / 'tools/lib'])))
    source = 'main(): Int64 { 0 }\n'
    result = {
        'compiler_sha256': sha256(compiler),
        'runtime_sha256': sha256(runtime / 'libcangjie-runtime.so'),
        'boundscheck_sha256': sha256(runtime / 'libboundscheck.so'),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'affinity': sorted(os.sched_getaffinity(0)),
        'uptime_before': subprocess.check_output(['uptime'], text=True).strip(),
        'cases': {},
    }
    checks = {}
    for name, flags in [('help', ['--help']), ('chir', ['--emit-chir=raw', 'main.cj', '-o', 'main'])]:
        directory = out / name
        directory.mkdir()
        (directory / 'main.cj').write_text(source)
        env['MRT_LOG_PATH'] = str(directory / 'runtime.log')
        start = time.monotonic()
        with (directory / 'compiler.log').open('w') as log:
            process = subprocess.run([str(compiler), *flags], cwd=directory, env=env,
                                     stdout=log, stderr=subprocess.STDOUT, timeout=120)
        log_path = directory / 'runtime.log'
        log = log_path.read_text() if log_path.exists() else ''
        # GcStats::Dump prints this after the collection has completed, including
        # reclaimed bytes. Count completed USER cycles, not function entry hits.
        collections = [line for line in log.splitlines() if 'GC for user:' in line]
        (directory / 'collections.txt').write_text('\n'.join(collections) + '\n')
        result['cases'][name] = {'rc': process.returncode, 'flags': flags,
                                'user_collections': len(collections),
                                'wall': time.monotonic() - start}
        checks[name + '_compiler_completed'] = process.returncode == 0
        if name == 'chir':
            checks['chir_product_written'] = (directory / 'main').is_file() and (directory / 'main').stat().st_size > 0
            checks['gc_log_positive_control'] = bool(collections)
        else:
            checks['help_has_no_phase_collection'] = not collections
    if args.reference:
        reference = json.loads(args.reference.read_text())
        checks['reference_qualified'] = reference['rc'] == 0
        for field in ['runtime_sha256', 'boundscheck_sha256', 'source_sha256']:
            checks['same_' + field] = result[field] == reference[field]
        for name, case in result['cases'].items():
            other = reference['cases'][name]
            checks[name + '_same_flags'] = case['flags'] == other['flags']
            checks[name + '_phase_collections_preserved'] = case['user_collections'] == other['user_collections']
    # Evaluate every assertion, so an unrelated earlier failure cannot obscure
    # whether the collection-preservation assertion itself was reached.
    for name, passed in checks.items():
        print(f'ASSERT {name} {"PASS" if passed else "FAIL"}', flush=True)
    result['checks'] = checks
    result['rc'] = int(not all(checks.values()))
    result['uptime_after'] = subprocess.check_output(['uptime'], text=True).strip()
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return result['rc']


if __name__ == '__main__':
    raise SystemExit(main())
