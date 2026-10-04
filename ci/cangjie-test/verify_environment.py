#!/usr/bin/env python3
"""Real environment CLI assertion for an official SDK and a private working JDK."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('sdk', type=Path)
parser.add_argument('output', type=Path)
parser.add_argument('jdk', type=Path)
args = parser.parse_args()
process = subprocess.run([sys.executable, str(Path(__file__).with_name('environment.py')),
                          str(args.source), str(args.sdk), str(args.output), '--arm', 'official',
                          '--jdk', str(args.jdk)], capture_output=True, text=True)
if process.returncode:
    raise SystemExit(process.stdout + process.stderr)
record = json.loads((args.output / 'environment.json').read_text())
checks = {}
checks['cjdb_loader'] = record['tools']['cjdb']['ready']
checks['jdk_compile_execute'] = record['readiness']['JDK']['ready']
expected = {str(p.relative_to(args.source / 'modules')): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (args.source / 'modules').rglob('*') if p.is_file()}
checks['lsp_modules'] = bool(expected) and record['artifacts'][str(args.sdk.resolve() / 'tools/bin/modules')] == expected
for name, passed in checks.items():
    print('ENVIRONMENT_TARGET', name, 'PASS' if passed else 'FAIL', flush=True)
print(json.dumps({'checks': checks, 'environment_script_sha256': hashlib.sha256(
    Path(__file__).with_name('environment.py').read_bytes()).hexdigest()}))
raise SystemExit(0 if all(checks.values()) else 1)
