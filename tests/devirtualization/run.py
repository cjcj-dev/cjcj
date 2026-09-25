#!/usr/bin/env python3
"""Check real stage1 devirtualization output; use the compiler's matching SDK environment."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def body(text, name):
    marker = f'srcCodeIdentifier: {name},'
    start = text.index(marker)
    return text[start:text.index('\n}', start)]


def comment_lines(text, name):
    marker = f'srcCodeIdentifier: {name},'
    return [line for line in text.splitlines() if marker in line]


def instantiated_callee(text, name):
    return [line for line in comment_lines(text, name)
            if 'genericDecl:' in line and 'linkType: internal' in line]


def verify(devirt, ast, case):
    if case == 'slot_receiver':
        value = body(devirt, 'chooseSecond')
        return [('selected_second_slot', bool(re.search(r'= Apply\([^\n]*4Impl6secondHv,', value))),
                ('upstream_cast_retained', '5SlotsE& = ClassStaticCast(' in value)]
    if case == 'boxed_receiver':
        value = body(devirt, 'readPayload')
        unbox = re.search(r'(%\d+): [^\n]* = UnBoxToValue\(', value)
        call = re.search(r'= Apply\([^\n]*7Payload4readHv, (%\d+)\)', value)
        return [('boxed_receiver_conversion_precedes_call', bool(unbox and call and
                 unbox.start() < call.start() and unbox[1] == call[1]))]
    if case == 'open_receiver':
        value = body(devirt, 'readOpen')
        return [('open_library_receiver_remains_virtual', bool(re.search(r'= Invoke\([^\n]*4Base5valueHv,', value)))]
    if case == 'inst_mangle':
        hits = []
        for name in ('secondInst', 'secondGeneric'):
            created = instantiated_callee(devirt, name)
            if not created:
                continue
            original = [line for line in comment_lines(devirt, name) if 'genericDecl:' not in line]
            if not any('rawMangledName:' in line for line in original):
                raise ValueError(f'original raw mangle missing for {name}')
            hits.append(all('rawMangledName:' not in line for line in created))
        if not hits:
            raise ValueError('instantiated callee missing')
        return [('inst_callee_raw_mangle_empty', all(hits)),
                ('original_keeps_raw_mangle', True)]
    if case == 'unchecked_cast':
        if ast is None:
            raise ValueError('AST_CHIR missing')
        value = body(ast, 'pickUnchecked')
        casts = [line for line in value.splitlines() if 'NumericCast(' in line]
        if not casts:
            raise ValueError('NumericCast missing')
        return [('unchecked_numeric_cast_need_check_false',
                 any('checkTypeCast: false' in line for line in casts))]
    if case == 'throwing_apply':
        value = body(devirt, 'chooseThrowing')
        return [('throwing_rewrite_is_try_apply',
                 'TryApply(' in value and 'TryInvoke(' not in value)]
    raise ValueError(f'unknown case {case}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    before = subprocess.check_output(['uptime'], text=True).strip()

    def run(source):
        destination = out / source.stem
        destination.mkdir(exist_ok=True)
        command = [str(compiler), str(source), '--emit-chir=opt', '--output-type=staticlib',
                   '--dump-chir', '--fchir-devirtualization', '--fno-chir-function-inlining',
                   '--jobs', '1', '-o', str(destination / 'output.chir')]
        if source.stem == 'unchecked_cast':
            command = [str(compiler), '--experimental', str(source), '--emit-chir=opt',
                       '--output-type=chir', '--dump-chir', '-O2', '--jobs', '1',
                       '-o', str(destination / 'output.chir')]
        start = time.monotonic()
        with (destination / 'compile.log').open('w') as log:
            try:
                rc = subprocess.run(command, cwd=destination, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=180).returncode
            except subprocess.TimeoutExpired:
                rc = 124
        record = dict(case=source.stem, command=command, rc=rc, wall=time.monotonic()-start,
                      input_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), assertions=[])
        dumps = list(destination.glob('output_CHIR/*_Devirtualization.chirtxt'))
        ast_dumps = list(destination.glob('output_CHIR/*_AST_CHIR.chirtxt'))
        if rc == 0 and (len(dumps) == 1 or (source.stem == 'unchecked_cast' and len(ast_dumps) == 1)):
            observed = dumps[0] if len(dumps) == 1 else ast_dumps[0]
            record['chir_sha256'] = hashlib.sha256(observed.read_bytes()).hexdigest()
            ast_text = ast_dumps[0].read_text() if len(ast_dumps) == 1 else None
            devirt_text = dumps[0].read_text() if len(dumps) == 1 else ''
            try:
                record['assertions'] = [dict(name=name, passed=passed)
                                        for name, passed in verify(devirt_text, ast_text, source.stem)]
            except ValueError as error:
                record['prerequisite_error'] = str(error)
        record['passed'] = rc == 0 and bool(record['assertions']) and all(x['passed'] for x in record['assertions'])
        for assertion in record['assertions']:
            print(f"ASSERT {source.stem}:{assertion['name']} {'PASS' if assertion['passed'] else 'FAIL'}", flush=True)
        (destination / 'result.json').write_text(json.dumps(record, indent=2)+'\n')
        return record

    with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
        cases = list(pool.map(run, sorted(Path(__file__).resolve().parent.glob('*.cj'))))
    manifest = dict(compiler=str(compiler), compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                    affinity=sorted(os.sched_getaffinity(0)), uptime_before=before,
                    uptime_after=subprocess.check_output(['uptime'], text=True).strip(), cases=cases)
    (out / 'result.json').write_text(json.dumps(manifest, indent=2)+'\n')
    return 0 if all(case['passed'] for case in cases) else 1


if __name__ == '__main__':
    raise SystemExit(main())
