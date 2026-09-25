#!/usr/bin/env python3
"""Exercise builtin constructor checking through a real stage1 compiler.

The objc.lang/internal packages are front-end fixtures, not an ObjC runtime.
All verdicts consume actual compiler diagnostics and exit codes.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
import re
from pathlib import Path
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--stub-compiler', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--imports', type=Path)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).resolve().parent
    imports = a.imports or a.out / 'imports'
    (imports / 'objc').mkdir(parents=True, exist_ok=True)
    result = {'compiler': str(a.compiler), 'compiler_sha256': sha(a.compiler),
              'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True),
              'fixtures': {f.name: sha(f) for f in fixtures.glob('*.cj')}, 'cases': {}}

    def compile_one(name, compiler, stub=False):
        dest = a.out / name
        dest.mkdir(exist_ok=True)
        command = [str(compiler), str(fixtures / (name + '.cj')), '--import-path', str(imports),
                   '--output-type=staticlib', '--diagnostic-format=noColor']
        if stub:
            command += ['--output-dir', str(imports / 'objc'), '-o', name + '.a']
        else:
            command += ['--emit-chir=raw', '--dump-ast', '-o', str(dest / 'result')]
        start = time.monotonic()
        with (dest / 'compiler.log').open('w') as log:
            run = subprocess.run(command, cwd=dest, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        (dest / 'compiler.rc').write_text(str(run.returncode) + '\n')
        return {'rc': run.returncode, 'command': command, 'wall': time.monotonic() - start,
                'log': str(dest / 'compiler.log')}

    if not a.imports:
        for name in ('internal', 'lang'):
            observed = compile_one(name, a.stub_compiler, True)
            result['cases'][name] = observed
            if observed['rc']:
                (a.out / 'result.json').write_text(json.dumps(result, indent=2))
                return 2
    names = ('pointer_inferred', 'block_inferred', 'func_inferred', 'pointer_explicit',
             'block_explicit', 'type_usage', 'control', 'cpointer')
    with ThreadPoolExecutor(max_workers=4) as pool:
        for name, observed in zip(names, pool.map(lambda n: compile_one(n, a.compiler), names)):
            text = Path(observed['log']).read_text()
            pointer = 'ObjCPointer can only be used with Objective-C compatible types'
            block = 'ObjCBlock can only be used with function type over Objective-C compatible types'
            func = 'ObjCFunc can only be used with function type over Objective-C compatible types'
            expected = ([pointer, block] if name == 'type_usage' else
                        [pointer] if name.startswith('pointer') else
                        [block] if name.startswith('block') else
                        [func] if name.startswith('func') else [])
            observed['target_diagnostics'] = {s: text.count(s) for s in expected}
            observed['assertions'] = {
                'compiler_exit': observed['rc'] == (1 if expected else 0),
                'target_diagnostics': all(v == 1 for v in observed['target_diagnostics'].values()),
            }
            # Read the actual post-desugar product AST. Keep independent assertions
            # so an earlier diagnostic mismatch never hides this state assertion.
            ast_path = a.out / name / 'result_AST' / '5_desugar_ast.txt'
            ast = ast_path.read_text() if ast_path.exists() else ''
            if name != 'type_usage' and expected:
                builtin = 'ObjCPointer' if name.startswith('pointer') else ('ObjCBlock' if name.startswith('block') else 'ObjCFunc')
                broken_calls = re.findall(r'CallExpr \{[^{}]*ty: (?:Struct|Class)-' + builtin
                                          + r'[^{}]*attributes: \[([^\]]*)\]', ast)
                observed['call_attributes'] = broken_calls
                observed['assertions']['rejected_call_state'] = any('IS_BROKEN' in x for x in broken_calls)
            positions = {'pointer_inferred': [31], 'block_inferred': [41], 'func_inferred': [40],
                         'pointer_explicit': [43], 'block_explicit': [42], 'type_usage': [34, 64]}
            if name in positions:
                observed['diagnostic_columns'] = [int(v) for v in re.findall(
                    r'error: [^\n]+\n ==> [^\n]+:' + r'5:(\d+):', text)]
                observed['assertions']['diagnostic_target'] = observed['diagnostic_columns'] == positions[name]
            observed['passed'] = all(observed['assertions'].values())
            result['cases'][name] = observed
            print(('PASS ' if observed['passed'] else 'FAIL ') + name + ' observed=' + json.dumps(observed), flush=True)
    result['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (a.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if all(result['cases'][n]['passed'] for n in names) else 1


if __name__ == '__main__':
    raise SystemExit(main())
