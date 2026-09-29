#!/usr/bin/env python3
"""Run the real compiler, retaining evidence and distinguishing fixture failures.

The caller supplies one compiler artifact and one immutable SDK per arm. No
expected numeric symbol counts are inferred from the source generator.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(args, case, single=False):
    name = case.stem + ('-single' if single else '')
    output = args.output / name
    output.mkdir(parents=True, exist_ok=False)
    bc = output / 'output.bc'
    cmd = [str(args.compiler), str(case), '--lto=full', '-O2',
           '--output-type=staticlib', '--jobs', str(len(os.sched_getaffinity(0))),
           '-o', str(bc)]
    if single:
        cmd.append('--cjcj-disable-mangling-concurrency')
    env = dict(os.environ, CANGJIE_HOME=str(args.sdk), cjHeapSize='32GB')
    env['PATH'] = ':'.join(str(args.sdk / p) for p in
                         ('bin', 'tools/bin', 'third_party/llvm/bin')) + ':' + os.environ['PATH']
    env['LD_LIBRARY_PATH'] = ':'.join(str(args.sdk / p) for p in
        ('runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
         'tools/lib', 'third_party/llvm/lib'))
    env['CANGJIE_PATH'] = ':'.join(str(args.sdk / p) for p in
        ('modules/linux_x86_64_cjnative', 'third_party/flatbuffers/modules'))
    env['LIBRARY_PATH'] = str(args.sdk / 'lib/linux_x86_64_cjnative')
    identities = {str(args.compiler): sha(args.compiler), str(case): sha(case)}
    identities.update({str(p): sha(p) for p in
                       (args.sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so')})
    identities.update({str(p): sha(p) for p in
                       (args.sdk / 'third_party/flatbuffers/modules').glob('*.cjo')})
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    with (output / 'compile.log').open('w') as log:
        try:
            rc = subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                timeout=180).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    wall = time.monotonic() - start
    text = (output / 'compile.log').read_text(errors='replace')
    bad = 'MANGLE_INVARIANT sourceDecl=true consumerDecl=false kind=Class' in text
    good = 'MANGLE_INVARIANT sourceDecl=true consumerDecl=true kind=Class' in text
    reached = bool(re.search(r'MANGLE_ASSERT consumed=true name=\S+', text))
    qualified = 'MANGLE_QUALIFICATION shared=true separate=true fullTasks=true' in text
    expected_red = ((args.expect_red and case.stem == 'parallel') or
                    (args.ordinary_red and case.stem == 'ordinary')) and not single
    if expected_red:
        passed = (rc != 0 and rc != 124 and bad and qualified and
                  'MANGLE_CONSUMER cachedFirst=true' in text and
                  'User-defined type has no declaration' in text and
                  'MANGLE_RACE second-finally-release' in text)
    else:
        passed = rc == 0 and bc.is_file()
        if args.race and case.stem in ('parallel', 'ordinary') and not single:
            passed = (passed and good and reached and not bad and qualified and
                      'MANGLE_RACE second-store sameAdapter=false' in text and
                      'MANGLE_CONSUMER cachedFirst=false' in text and
                      'MANGLE_RACE first-resumed' in text)
    dis_rc = None
    symbols = []
    output_hash = None
    if bc.is_file():
        output_hash = sha(bc)
        ir = output / 'output.ll'
        with (output / 'disassemble.log').open('w') as log:
            dis_rc = subprocess.run([str(args.sdk / 'third_party/llvm/bin/llvm-dis'),
                                     str(bc), '-o', str(ir)], env=env,
                                    stdout=log, stderr=subprocess.STDOUT).returncode
        if dis_rc == 0:
            symbols = sorted(re.findall(r'^define\b.*?@("[^"]+"|[^ (]+)\(',
                                        ir.read_text(), re.MULTILINE))
        if not expected_red:
            passed = passed and dis_rc == 0 and bool(symbols)
    result = dict(case=name, command=cmd, rc=rc, wall=wall,
                  uptime_before=before, uptime_after=subprocess.check_output(['uptime'], text=True).strip(),
                  affinity=sorted(os.sched_getaffinity(0)), sdk=str(args.sdk), hashes=identities,
                  output_sha256=output_hash, disassemble_rc=dis_rc, symbols=symbols,
                  incomplete_observed=bad, complete_observed=good, result_assertion_reached=reached,
                  expected_red=expected_red, passed=passed)
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'{name} rc={rc} wall={wall:.2f} expected_red={expected_red} passed={passed}', flush=True)
    # Keep failed artifacts; successful bitcode/text IR can be reconstructed.
    if passed and not expected_red:
        for p in output.iterdir():
            if p.suffix in ('.bc', '.ll', '.o', '.a', '.cjo'):
                p.unlink()
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--sdk', type=Path, required=True)
    p.add_argument('--inputs', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--race', action='store_true')
    p.add_argument('--expect-red', action='store_true')
    p.add_argument('--ordinary-red', action='store_true', help='constructor cut also shares ordinary adapters')
    p.add_argument('--parallelism', type=int, choices=range(1, 5), default=4)
    args = p.parse_args()
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    cases = [(args.inputs / 'parallel.cj', False), (args.inputs / 'parallel.cj', True),
             (args.inputs / 'remainder.cj', False), (args.inputs / 'control.cj', False),
             (args.inputs / 'ordinary.cj', False), (args.inputs / 'ordinary.cj', True)]
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.parallelism) as pool:
        futures = [pool.submit(run, args, case, single) for case, single in cases]
        results = [future.result() for future in futures]
    parallel, single = results[:2]
    # Compare measured sets, not an assumed fixed count. Red arms have no valid
    # parallel output to compare; the unaffected controls must still pass.
    same_names = (parallel['symbols'] == single['symbols']) if not args.expect_red else None
    ordinary_same_names = (results[4]['symbols'] == results[5]['symbols']) if not args.ordinary_red else None
    (args.output / 'summary.json').write_text(json.dumps(
        dict(results=results, parallel_single_symbols_equal=same_names,
             ordinary_single_symbols_equal=ordinary_same_names), indent=2) + '\n')
    return int(not all(r['passed'] for r in results) or same_names is False or ordinary_same_names is False)


if __name__ == '__main__':
    raise SystemExit(main())
