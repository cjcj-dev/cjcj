#!/usr/bin/env python3
"""Compile real source with stage1 and assert on its devirtualization CHIR.

The pass-call cut must fail only actual_types_choose_nonrecursive_raw_callee.
No test model, manual CHIR construction, or product instrumentation is used.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def function(text, name):
    # The printer puts the source identifier at the end of a possibly multiline header.
    match = re.search(r'^.*srcCodeIdentifier: ' + re.escape(name) + r',.*\n', text, re.M)
    if not match:
        return ''
    end = text.find('\n}\n', match.end())
    return text[match.end():end + 3] if end >= 0 else ''


def check_outputs(outputs):
    multi = outputs.get('multiple_instantiations', '')
    entry = function(multi, 'entry')
    calls = re.findall(r'= Apply\([^\n]*->@([^,()\n]+), (%\d+)\)', entry)
    constants = re.findall(r'(%\d+): Int64 = Constant\(\)[^\n]*, 35i$', entry, re.M)
    expected = '_CN24trivial_statics_multiple1C2f1Hl'
    target = (len(calls) == 1 and calls[0][0] == expected and calls[0][1] in constants
              and 'InvokeStatic(' not in entry and 'TypeCast(' not in entry and 'Box(' not in entry)
    generic = function(outputs.get('generic_method', ''), 'dispatch')
    generic_this = function(multi, 'dispatch')
    dynamic = function(multi, 'fromInstance')
    control = function(outputs.get('control', ''), 'entry')
    zero_values = re.findall(r'(%\d+): Int64 = Constant\(\)[^\n]*, 0i$', control, re.M)
    control_ok = any('Store(' + value + ', ' in control for value in zero_values)
    return [
        ('actual_types_choose_nonrecursive_raw_callee', target,
         {'body': entry, 'calls': calls, 'argument_constants': constants, 'expected': expected}),
        ('generic_instantiation_preserved', bool(re.search(r'InvokeStatic\(.*identity.*<Int64>', generic)),
         {'body': generic}),
        ('generic_receiver_preserved', 'InvokeStatic(Generic-' in generic_this, {'body': generic_this}),
        ('dynamic_rtti_preserved', 'GetRTTI(' in dynamic and 'InvokeStatic(' in dynamic, {'body': dynamic}),
        ('ordinary_call_control', control_ok,
         {'body': control}),
    ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=os.cpu_count())
    args = parser.parse_args()
    args.compiler = args.compiler.resolve()
    args.out = args.out.resolve()
    args.out.mkdir(parents=True, exist_ok=True)
    if any(args.out.iterdir()):
        raise SystemExit('output directory must be empty; stale CHIR cannot count as a run')
    fixtures = Path(__file__).resolve().parent
    sources = [fixtures / (name + '.cj') for name in
               ['multiple_instantiations', 'generic_method', 'control']]

    def compile_one(source):
        dest = args.out / source.stem
        dest.mkdir()
        command = [str(args.compiler), str(source), '--emit-chir=opt', '--output-type=staticlib',
                   '--dump-chir', '-O2', '--fchir-devirtualization', '--jobs', str(args.jobs),
                   '-o', str(dest / 'output.chir')]
        start = time.monotonic()
        with (dest / 'compile.log').open('w') as log:
            try:
                rc = subprocess.run(command, cwd=dest, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=180).returncode
            except subprocess.TimeoutExpired:
                rc = 124
        chir = list((dest / 'output_CHIR').glob('*_Devirtualization.chirtxt'))
        result = {'source': str(source), 'source_sha256': sha(source), 'command': command,
                  'rc': rc, 'wall': time.monotonic() - start, 'chir': [str(p) for p in chir]}
        if rc == 0 and len(chir) == 1:
            result['chir_sha256'] = sha(chir[0])
            return result, chir[0].read_text()
        return result, ''

    record = {'compiler': str(args.compiler), 'compiler_sha256': sha(args.compiler),
              'runner_sha256': sha(Path(__file__).resolve()), 'affinity': sorted(os.sched_getaffinity(0)),
              'jobs': args.jobs, 'parallel_fixtures': len(sources),
              'uptime_before': subprocess.check_output(['uptime'], text=True), 'cases': []}
    sdk = Path(os.environ['CANGJIE_HOME'])
    record['input_hashes'] = {str(p): sha(p) for p in [
        sdk / 'runtime/lib/linux_x86_64_cjnative/libcangjie-runtime.so',
        sdk / 'runtime/lib/linux_x86_64_cjnative/libboundscheck.so',
        sdk / 'third_party/llvm/lib/libLLVM-15.so',
        sdk / 'lib/linux_x86_64_cjnative/libcangjie-std-core.a']}
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(sources)) as pool:
        results = list(pool.map(compile_one, sources))
    outputs = {}
    for source, (result, output) in zip(sources, results):
        record['cases'].append(result)
        outputs[source.stem] = output
    checks = check_outputs(outputs)
    record['checks'] = [{'name': n, 'passed': bool(p), 'observed': o} for n, p, o in checks]
    for name, passed, observed in checks:
        print(('PASS ' if passed else 'FAIL ') + name, flush=True)
        print(json.dumps(observed, ensure_ascii=False), flush=True)
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    record['rc'] = int(not all(c['rc'] == 0 for c in record['cases']) or not all(p for _, p, _ in checks))
    (args.out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record['rc']


if __name__ == '__main__':
    raise SystemExit(main())
