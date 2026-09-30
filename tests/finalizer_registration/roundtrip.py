#!/usr/bin/env python3
"""Pass actual compiler CHIR to a reader linked with that product's CHIR library."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time

from run import digest, linked_libraries


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reader', type=Path, required=True)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    results = []
    source_results = json.loads(args.result.read_text())
    linkage_rc, libraries = linked_libraries(args.reader)
    for case in source_results['cases']:
        name = Path(case['source']).stem
        if name != 'root' and not (name == 'control' and case['phase'] == 'opt'):
            continue
        source = Path(case['log']).parent / 'output.chir'
        label = name + '-' + case['phase'] + '-' + case['optimization']
        command = [str(args.reader), str(source), 'scalar' if name == 'control' else 'root']
        before = subprocess.check_output(['uptime'], text=True).strip()
        start = time.monotonic()
        with (args.out / (label + '.log')).open('w') as log:
            rc = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=300).returncode
        output = (args.out / (label + '.log')).read_text()
        print(f'{label} reader_rc={rc} {output.strip()}', flush=True)
        results.append({'command': command, 'rc': rc, 'wall': time.monotonic() - start,
                        'uptime_before': before,
                        'uptime_after': subprocess.check_output(['uptime'], text=True).strip(),
                        'input_sha256': digest(source), 'output': output})
    (args.out / 'result.json').write_text(json.dumps({
        'compiler_sha256': source_results['compiler_sha256'], 'reader_sha256': digest(args.reader),
        'libraries': libraries, 'ldd_rc': linkage_rc, 'affinity': sorted(os.sched_getaffinity(0)),
        'cases': results}, indent=2) + '\n')
    if not results or any(case['rc'] not in (0, 1) or 'TARGET ' not in case['output'] for case in results):
        return 2
    return 0 if all(case['rc'] == 0 for case in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
