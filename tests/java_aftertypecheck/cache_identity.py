#!/usr/bin/env python3
"""Assert JNI cache sharing relationships in the real compiler's desugared AST."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
from run import brace_section


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).resolve().parent
    imports = out / 'imports'
    (imports / 'java').mkdir(parents=True, exist_ok=True)
    result = dict(compiler=str(compiler), compiler_sha256=sha(compiler),
                  affinity=sorted(os.sched_getaffinity(0)),
                  uptime_before=subprocess.check_output(['uptime'], text=True), cases={})

    def compile_one(name, stub=False):
        dest = out / name
        dest.mkdir(exist_ok=True)
        cmd = [str(compiler), str(fixtures / (name + '.cj')), '--import-path', str(imports),
               '--output-type=staticlib', '--diagnostic-format=noColor']
        cmd += (['--output-dir', str(imports / 'java'), '-o', name + '.a'] if stub else
                ['--dump-ast', '-o', str(dest / 'result')])
        start = time.monotonic()
        with (dest / 'compiler.log').open('w') as log:
            proc = subprocess.run(cmd, cwd=dest, stdout=log, stderr=subprocess.STDOUT, timeout=180)
        record = dict(command=cmd, rc=proc.returncode, wall=time.monotonic()-start,
                      fixture_sha256=sha(fixtures / (name + '.cj')))
        (dest / 'compiler.rc').write_text(str(proc.returncode) + '\n')
        return dest, record

    # These two imports depend on each other; independent user packages run concurrently.
    ready = True
    for name in ('internal', 'lang'):
        _, record = compile_one(name, True)
        result['cases'][name] = record
        if record['rc'] != 0:
            ready = False
            break

    def check(name):
        dest, record = compile_one(name)
        path = dest / 'result_AST/5_desugar_ast.txt'
        ast = path.read_text() if path.exists() else ''
        kind = 'jfield' if '_field_' in name else 'jmethod'
        refs = {}
        for cls in ('First', 'Second', 'Alias'):
            body = brace_section(ast, 'ClassDecl: ' + cls + ' ')
            # Restrict to the member under test, excluding synthesized constructors.
            members = ('$nget', '$nset') if kind == 'jfield' else ('n',)
            if cls == 'Second':
                members = ('$otherget', '$otherset') if kind == 'jfield' else ('other',)
            refs[cls] = {member: sorted(set(re.findall(r'RefExpr: (' + kind + r'[^ ]+)',
                brace_section(body, 'FuncDecl: ' + member + ' ')))) for member in members}
        slots = {cls: set(slot for group in groups.values() for slot in group)
                 for cls, groups in refs.items()}
        observed = record['rc'] == 0 and all(len(group) == 1 for groups in refs.values() for group in groups.values())
        # All target assertions are recorded even if observation fails; no early assertion hides them.
        assertions = {
            'compiler_accepted': record['rc'] == 0,
            'member_cache_refs_observed': observed,
            'distinct_members_have_distinct_slots': observed and slots['First'].isdisjoint(slots['Second']),
            'same_member_reuses_slot': observed and slots['First'] == slots['Alias'],
            'getter_setter_share_slot': observed and all(len(v) == 1 for v in slots.values()),
        }
        record.update(refs=refs, assertions=assertions, ast_sha256=sha(path) if path.exists() else None)
        for assertion, passed in assertions.items():
            print(('PASS ' if passed else 'FAIL ') + name + ':' + assertion, flush=True)
        return name, record

    if ready:
        names = [f'cache_{kind}_{mode}' for kind in ('field', 'method') for mode in ('collision', 'control', 'hash_collision')]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            result['cases'].update(dict(pool.map(check, names)))
    result['compiler_after_sha256'] = sha(compiler)
    result['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    passed = ready and all(all(case.get('assertions', {'compile': case['rc'] == 0}).values())
                           for case in result['cases'].values())
    result['rc'] = 0 if passed else 1
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return result['rc']


if __name__ == '__main__':
    raise SystemExit(main())
