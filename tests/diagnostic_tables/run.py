#!/usr/bin/env python3
"""Exercise stage1's real Sema diagnostic path; retain every result, including rc."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('--compiler', type=Path, required=True)
p.add_argument('--source-root', type=Path, required=True)
p.add_argument('--imports-root', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--repetitions', type=int, default=3)
p.add_argument('--workers', type=int, default=3)
a = p.parse_args()
a.out.mkdir(parents=True, exist_ok=True)
imports = [a.imports_root] + sorted(a.imports_root.glob('*@cjcj'))
fixtures = Path(__file__).resolve().parent
cases = [(name, a.source_root / 'packages' / name / 'src', n, False)
         for name in ('frontend', 'frontend_tool', 'macro')
         for n in range(a.repetitions)]
cases += [('unused_import', fixtures / 'unused_import.cj', 0, True),
          ('control', fixtures / 'control.cj', 0, False)]


def run(case):
    name, source, iteration, expect_warning = case
    out = a.out / f'{name}-{iteration}'
    out.mkdir()
    command = [str(a.compiler)]
    command += ['-p', str(source)] if source.is_dir() else [str(source)]
    command += ['--emit-chir=opt', '--output-type=staticlib', '-O0', '--jobs', '1',
                '--diagnostic-format=noColor', '-o', str(out / 'output.chir')]
    for directory in imports:
        command += ['--import-path', str(directory)]
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    with (out / 'compile.log').open('w') as log:
        try:
            result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=900)
            rc = result.returncode
        except subprocess.TimeoutExpired:
            rc = 124
    output = (out / 'compile.log').read_text()
    artifacts = list(out.glob('*.chir'))
    assertions = {
        'no_index_exception': 'IndexOutOfBoundsException' not in output,
        'completed_chir': rc == 0 and len(artifacts) == 1 and artifacts[0].stat().st_size > 0,
    }
    if expect_warning:
        assertions['unused_import_warning'] = 'warning: unused import' in output
    if name == 'control':
        assertions['no_unused_import_warning'] = 'unused import' not in output
    record = dict(name=name, iteration=iteration, command=command, rc=rc,
                  wall=time.monotonic()-start, uptime_before=before,
                  uptime_after=subprocess.check_output(['uptime'], text=True).strip(),
                  assertions=assertions)
    (out / 'result.json').write_text(json.dumps(record, indent=2))
    return record


with concurrent.futures.ThreadPoolExecutor(max_workers=a.workers) as pool:
    results = list(pool.map(run, cases))
record = dict(compiler=str(a.compiler),
              compiler_sha256=hashlib.sha256(a.compiler.read_bytes()).hexdigest(),
              affinity=sorted(os.sched_getaffinity(0)), workers=a.workers, results=results)
(a.out / 'result.json').write_text(json.dumps(record, indent=2))
for result in results:
    print(result['name'], result['iteration'], 'rc='+str(result['rc']), result['assertions'])
raise SystemExit(0 if all(all(r['assertions'].values()) for r in results) else 1)
