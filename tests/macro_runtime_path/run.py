#!/usr/bin/env python3
"""Exercise compiler-relative macro runtime paths through the real stage1 CLI."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run_case(compiler, source, output, env, sdk, missing):
    output.mkdir()
    product = output / 'output.bc'
    command = [str(compiler), str(source), '--lto=full', '-O2',
               '--output-type=staticlib', '-o', str(product)]
    before = subprocess.check_output(['uptime'], text=True).strip()
    started = time.monotonic()
    timed_out = False
    with (output / 'compile.log').open('w') as log:
        try:
            completed = subprocess.run(command, env=env, cwd=output, stdout=log,
                                       stderr=subprocess.STDOUT, timeout=120)
            rc = completed.returncode
        except subprocess.TimeoutExpired:
            timed_out = True
            rc = 124
    log = (output / 'compile.log').read_text(errors='replace')
    runtime_path = str(compiler.parent / '../runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so')
    diagnostic = 'could not get realpath of library: ' + runtime_path
    checks = {'completed': not timed_out}
    if source.stem == 'annotations' and missing:
        checks['compile_rejected'] = rc == 1
        checks['missing_runtime_path_diagnostic'] = diagnostic in log
        checks['no_output'] = not product.exists()
    elif source.stem == 'undeclared':
        checks['compile_rejected'] = rc == 1
        checks['undeclared_annotation_rejected'] = "undeclared identifier 'MissingMark'" in log
        checks['no_output'] = not product.exists()
        checks['no_runtime_path_diagnostic'] = 'could not get realpath of library:' not in log
    else:
        checks['compile_success'] = rc == 0
        checks['nonempty_output'] = product.is_file() and product.stat().st_size > 0
        checks['no_runtime_path_diagnostic'] = 'could not get realpath of library:' not in log
    record = dict(command=command, rc=rc, timed_out=timed_out, checks=checks,
                  expected_diagnostic=diagnostic, wall=time.monotonic() - started,
                  compiler_sha256=sha(compiler), source_sha256=sha(source), sdk=str(sdk),
                  affinity=sorted(os.sched_getaffinity(0)), uptime_before=before,
                  uptime_after=subprocess.check_output(['uptime'], text=True).strip(),
                  product_sha256=sha(product) if product.is_file() else None)
    (output / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    for name, passed in checks.items():
        print(f"{'PASS' if passed else 'FAIL'} {output.name}/{name}", flush=True)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--sdk', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    sdk = args.sdk.resolve()
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, CANGJIE_HOME=str(sdk), cjHeapSize='32GB')
    env['PATH'] = ':'.join(str(sdk / part) for part in
                           ('bin', 'tools/bin', 'third_party/llvm/bin')) + ':' + os.environ['PATH']
    env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / part) for part in
        ('runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
         'tools/lib', 'third_party/llvm/lib'))
    env['CANGJIE_PATH'] = ':'.join(str(sdk / part) for part in
        ('modules/linux_x86_64_cjnative', 'third_party/flatbuffers/modules'))
    env['LIBRARY_PATH'] = str(sdk / 'lib/linux_x86_64_cjnative')
    manifest = {'sdk': str(sdk), 'files': {}, 'runner_sha256': sha(Path(__file__))}
    compilers = {}
    for layout in ('valid', 'missing'):
        compiler = output / layout / 'bin/cjcj-stage1'
        compiler.parent.mkdir(parents=True)
        shutil.copy2(args.compiler.resolve(), compiler)
        compilers[layout] = compiler
        manifest['files'][str(compiler)] = sha(compiler)
        if layout == 'valid':
            runtime = output / layout / 'runtime/lib/linux_x86_64_cjnative'
            runtime.mkdir(parents=True)
            for name in ('libcangjie-runtime.so', 'libboundscheck.so'):
                source = sdk / 'runtime/lib/linux_x86_64_cjnative' / name
                shutil.copy2(source, runtime / name)
                manifest['files'][str(source)] = sha(source)
                manifest['files'][str(runtime / name)] = sha(runtime / name)
    (output / 'identity.json').write_text(json.dumps(manifest, indent=2) + '\n')
    here = Path(__file__).resolve().parent
    cases = [(layout, name) for layout in ('valid', 'missing')
             for name in ('annotations', 'plain')]
    cases.append(('valid', 'undeclared'))
    def execute(case):
        layout, name = case
        return run_case(compilers[layout], here / (name + '.cj'),
                        output / (layout + '-' + name), env, sdk, layout == 'missing')
    with ThreadPoolExecutor(max_workers=len(cases)) as pool:
        records = list(pool.map(execute, cases))
    summary = {'cases': len(records),
               'failed_checks': sum(not passed for record in records for passed in record['checks'].values())}
    (output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    return int(summary['failed_checks'] != 0)


if __name__ == '__main__':
    raise SystemExit(main())
