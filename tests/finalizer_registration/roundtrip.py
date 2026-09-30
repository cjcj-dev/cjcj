#!/usr/bin/env python3
"""Deserialize compiler-produced binary CHIR through the real frontend."""
import argparse
import json
from pathlib import Path
import subprocess

from run import digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    results = []
    for case in json.loads(args.result.read_text())['cases']:
        if Path(case['source']).stem != 'root':
            continue
        source = Path(case['log']).parent / 'output.chir'
        directory = args.out / (case['phase'] + '-' + case['optimization'])
        directory.mkdir()
        command = [str(args.compiler), '--deserialize-chir-and-dump', str(source)]
        with (directory / 'run.log').open('w') as log:
            rc = subprocess.run(command, cwd=directory, stdout=log,
                                stderr=subprocess.STDOUT, timeout=300).returncode
        output = directory / 'deserialized.chir'
        count = output.read_text().count('Intrinsic(registerFinalizer,') if output.exists() else 0
        original = next((Path(case['log']).parent / 'output_CHIR').glob(
            '*AST_CHIR.chirtxt' if case['phase'] == 'raw' else '*EraseUselessDebugExpr.chirtxt'))
        expected = original.read_text().count('Intrinsic(registerFinalizer,')
        passed = rc == 0 and count == expected and count > 0
        print(f'TARGET {directory.name} serialized_root_events={"PASS" if passed else "FAIL"}'
              f' compiler_rc={rc} before={expected} after={count}', flush=True)
        results.append({'command': command, 'compiler_rc': rc, 'expected': expected,
                        'actual': count, 'passed': passed, 'input_sha256': digest(source),
                        'output_sha256': digest(output) if output.exists() else None})
    (args.out / 'result.json').write_text(json.dumps({
        'compiler_sha256': digest(args.compiler), 'cases': results}, indent=2) + '\n')
    if not results or any(case['compiler_rc'] != 0 for case in results):
        return 2
    return 0 if all(case['passed'] for case in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
