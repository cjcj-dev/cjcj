#!/usr/bin/env python3
"""Compare explicit USER request state updates through the real compiler CLI.

Capture a reference with the baseline compiler, then pass its result.json with
--reference for the candidate. Reads the host runtime's existing request
timestamp with GDB; no compiler instrumentation, inferior writes or replacement
runtime entry points. Completed GC logs are retained as supporting evidence:
asynchronous requests can coalesce, so cycle totals are not an invariant.
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
    observer = Path(__file__).with_name('phase_gc_watch.py').resolve()
    out.mkdir(parents=True, exist_ok=False)
    runtime = sdk / 'runtime/lib/linux_x86_64_cjnative'
    env = os.environ.copy()
    env.update(CANGJIE_HOME=str(sdk), cjHeapSize='32GB', MRT_LOG_LEVEL='d',
               MRT_LOG_FILE_SIZE='128mb',
               LD_LIBRARY_PATH=':'.join(map(str, [runtime,
                   sdk / 'lib/linux_x86_64_cjnative', sdk / 'third_party/llvm/lib',
                   sdk / 'tools/lib'])))
    source = ('package phase_gc\n'
              'class Item {\n'
              '    public let value: Int64\n'
              '    public init(value: Int64) { this.value = value }\n'
              '}\n'
              'main(): Int64 { let item = Item(0); item.value }\n')
    result = {
        'compiler_sha256': sha256(compiler),
        'runtime_sha256': sha256(runtime / 'libcangjie-runtime.so'),
        'boundscheck_sha256': sha256(runtime / 'libboundscheck.so'),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'observer_sha256': sha256(observer),
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
        env['PHASE_GC_OUTPUT'] = str(directory / 'requests.json')
        start = time.monotonic()
        with (directory / 'compiler.log').open('w') as log:
            process = subprocess.run(['gdb', '--batch', '--return-child-result',
                                      '-x', str(observer), '--args', str(compiler), *flags], cwd=directory, env=env,
                                     stdout=log, stderr=subprocess.STDOUT, timeout=120)
        requests_path = directory / 'requests.json'
        requests = json.loads(requests_path.read_text()) if requests_path.exists() else {}
        events = requests.get('events', [])
        sites = ('PerformGenericInstantiation', 'PerformCHIRCompilation',
                 'ToCHIRPackage', 'DestroyASTResources')
        by_site = {site: sum(event['site'] == site for event in events) for site in sites}
        log_path = directory / 'runtime.log'
        log = log_path.read_text() if log_path.exists() else ''
        # GcStats::Dump prints this after the collection has completed, including
        # reclaimed bytes. Count completed USER cycles, not function entry hits.
        collections = [line for line in log.splitlines() if 'GC for user:' in line]
        (directory / 'collections.txt').write_text('\n'.join(collections) + '\n')
        result['cases'][name] = {'rc': process.returncode, 'flags': flags,
                                'user_collections': len(collections),
                                'requests_by_site': by_site,
                                'wall': time.monotonic() - start}
        checks[name + '_compiler_completed'] = process.returncode == 0 and requests.get('inferior_rc') == 0
        checks[name + '_observer_completed'] = 'observer_error' not in requests and 'initial' in requests
        checks[name + '_user_request_state'] = all(
            event['reason'] == 0 and event['timestamp'] > event['previous']
            and event['site'] in sites for event in events)
        if name == 'chir':
            checks['chir_product_written'] = (directory / 'main').is_file() and (directory / 'main').stat().st_size > 0
            checks['gc_log_positive_control'] = bool(collections)
            checks['request_state_positive_control'] = bool(events)
            if not args.reference:
                # A single source package visits each of the four existing
                # phase boundaries once. Qualify the baseline before comparing.
                for site in sites:
                    checks['reference_' + site + '_observed'] = by_site[site] == 1
        else:
            checks['help_has_no_phase_collection'] = not collections
            checks['help_has_no_phase_request'] = not events
    if args.reference:
        reference = json.loads(args.reference.read_text())
        checks['reference_qualified'] = reference['rc'] == 0
        for field in ['runtime_sha256', 'boundscheck_sha256', 'source_sha256', 'observer_sha256']:
            checks['same_' + field] = result[field] == reference[field]
        for name, case in result['cases'].items():
            other = reference['cases'][name]
            checks[name + '_same_flags'] = case['flags'] == other['flags']
            for site in sites:
                checks[name + '_' + site + '_request_preserved'] = case['requests_by_site'][site] == other['requests_by_site'][site]
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
