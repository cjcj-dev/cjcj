#!/usr/bin/env python3
"""Run real compiler diagnostics; never stop before evaluating target assertions.

Usage: run.py COMPILER OUTPUT_DIRECTORY [compiler arguments ...]
The caller supplies the compiler's SDK and loader environment.
"""
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

compiler = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
out.mkdir(parents=True, exist_ok=True)
extra = sys.argv[3:]
fixtures = Path(__file__).resolve().parent
results = []
for name, severity in [('default', 'warning'), ('false', 'warning'),
                       ('strict', 'error'), ('plain', None)]:
    source = fixtures / (name + '.cj')
    binary = out / name
    binary.unlink(missing_ok=True)
    command = [str(compiler), str(source), '-O0', '-o', str(binary), *extra]
    proc = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    text = re.sub(r'\x1b\[[0-9;]*m', '', proc.stdout.decode(errors='replace'))
    (out / (name + '.log')).write_text(text)
    (out / (name + '.rc')).write_text(str(proc.returncode) + '\n')
    diagnostics = re.findall(r'(warning|error): constructor .?init.? is deprecated', text)
    assertions = {
        'severity': diagnostics == ([severity] if severity else []),
        'exit-status': proc.returncode == (1 if severity == 'error' else 0),
        'artifact': binary.is_file() == (severity != 'error'),
        'warning-group': ('-Woff deprecated' in text) == (severity == 'warning'),
    }
    for assertion, passed in assertions.items():
        print(f'{"PASS" if passed else "FAIL"} {name}/{assertion} rc={proc.returncode} diagnostics={diagnostics}', flush=True)
    results.append(dict(name=name, command=command, rc=proc.returncode,
                        diagnostics=diagnostics, assertions=assertions,
                        source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                        output_sha256=hashlib.sha256(binary.read_bytes()).hexdigest() if binary.is_file() else None))
(out / 'results.json').write_text(json.dumps(dict(
    compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
    results=results), indent=2) + '\n')
raise SystemExit(0 if all(all(r['assertions'].values()) for r in results) else 1)
