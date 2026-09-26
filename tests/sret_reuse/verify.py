#!/usr/bin/env python3
"""Observe sret emission through a real cjc-frontend compiler, without backend linking."""
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


def functions(root):
    result = {}
    for path in root.rglob('*.ll'):
        for match in re.finditer(r'^define [^\n]+\{\n.*?^\}', path.read_text(), re.M | re.S):
            definition = match.group()
            name = re.search(r'@([^ (]+)\(', definition).group(1)
            result[name] = {'ir': definition, 'path': str(path),
                            'line': path.read_text()[:match.start()].count('\n') + 1}
    return result


def find_function(items, name):
    matches = [v for k, v in items.items() if re.search(r'\d' + name + r'(?:H|I)', k)]
    if len(matches) != 1:
        raise ValueError(f'{name}: expected one emitted definition, found {len(matches)}')
    return matches[0]


def call_slot(body, callee):
    calls = [line.strip() for line in body.splitlines()
             if re.search(r'\bcall\b.*@\S*\d' + callee + r'(?:H|I)', line)]
    if len(calls) != 1:
        raise ValueError(f'{callee}: expected one call, found {len(calls)}')
    # The first argument can contain nested type/attribute parentheses. Its final
    # SSA token before the first comma (or the end of a unit call) is the slot.
    argument = calls[0].split('(', 1)[1].split(',', 1)[0]
    tokens = re.findall(r'%(?:"[^"]+"|[-\w.]+)', argument)
    return tokens[-1], calls[0]


def observe(items, level):
    checks = []
    observations = {}
    def check(name, condition, detail):
        checks.append({'name': name, 'passed': bool(condition), 'detail': detail})

    for name, callee in [('tailLarge', 'makeLarge'), ('tailGeneric', 'identity'), ('tailBox', 'makeBox'),
                         ('nonTailLarge', 'makeLarge'), ('tailUnit', 'unitLeaf')]:
        item = find_function(items, name)
        ir = item['ir']
        slot, call = call_slot(ir, callee)
        caller_slot = re.findall(r'%(?:"[^"]+"|[-\w.]+)', ir.splitlines()[0].split(',', 1)[0])[-1]
        observations[name] = {**item, 'call': call, 'call_slot': slot, 'caller_slot': caller_slot}
        if name in ('tailLarge', 'tailGeneric', 'tailBox'):
            check('tail_sret_reuse' if level != 'O0' else 'o0_keeps_separate_slot',
                  (slot == caller_slot) == (level != 'O0'), f'{name}: callee={slot}, caller={caller_slot}')
            # This invariant applies when producer and consumer use the SAME raw
            # pointer. A disabled reuse producer changes its premise, not the
            # store rule. Record the premise as well as evaluating the assertion.
            after_call = ir.split(call, 1)[1]
            writes = [line.strip() for line in after_call.splitlines()
                      if re.search(r'^\s*store\s|^\s*(?:%[^=]+ = )?call\s.*(?:memcpy|memmove|assign|gcwrite)', line)]
            same_raw = slot == caller_slot
            check('no_store_to_same_raw_pointer', not same_raw or not writes,
                  {'function': name, 'same_raw': same_raw, 'writes_after_call': writes})
            if name == 'tailGeneric':
                # Observe the call result before its consumer writes it. Loads
                # performed inside a store are checked by the store invariant.
                before_write = re.split(r'^\s*store\s', after_call, maxsplit=1, flags=re.M)[0]
                loads = [line.strip() for line in before_write.splitlines()
                         if re.search(r'^\s*%[^=]+ = load\s', line)]
                check('reused_generic_result_is_slot', not same_raw or not loads,
                      {'same_raw': same_raw, 'loads_before_first_write': loads})
        elif name == 'nonTailLarge':
            check('non_tail_keeps_separate_slot', slot != caller_slot, call)
        else:
            writes = [line.strip() for line in ir.splitlines() if re.search(r'^\s*store\s', line)]
            check('unit_ret_store_is_skipped', not writes, writes)
    concrete = find_function(items, 'concreteGeneric')
    concrete_slot, concrete_call = call_slot(concrete['ir'], 'identity')
    check('different_sret_type_keeps_separate_slot', concrete_slot != '%0', concrete_call)
    register = find_function(items, 'scalarGeneric')
    register_slot, register_call = call_slot(register['ir'], 'identity')
    check('non_sret_caller_keeps_callee_slot', 'sret(' not in register['ir'].splitlines()[0]
          and 'alloca i8 addrspace(1)*' in register['ir'] and register_slot != '%value', register_call)
    scalar = find_function(items, 'scalar')
    check('scalar_return_unchanged', 'sret(' not in scalar['ir'].splitlines()[0]
          and 'ret i64' in scalar['ir'], scalar['ir'])
    return checks, observations


def compile_case(compiler, source, destination, level, jobs, executable=False):
    destination.mkdir(parents=True, exist_ok=True)
    command = [str(compiler), str(source), *([] if executable else ['--output-type=staticlib']), '-' + level,
               '--dump-ir', '--jobs', str(jobs), '-o', str(destination / 'tail.bc')]
    start = time.monotonic()
    before = subprocess.check_output(['uptime'], text=True).strip()
    with (destination / 'compile.log').open('w') as log:
        process = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=600, cwd=destination)
    result = {'command': command, 'compiler_rc': process.returncode, 'wall': time.monotonic() - start,
              'uptime_before': before, 'uptime_after': subprocess.check_output(['uptime'], text=True).strip(),
              'checks': [], 'observations': {}}
    if executable:
        result['checks'].append({'name': 'synthetic_main_compiles',
                                 'passed': process.returncode == 0, 'detail': process.returncode})
    if process.returncode == 0:
        try:
            items = functions(destination)
            if executable:
                # Require actual executable entry IR, not merely absence of an error.
                entries = {name: item for name, item in items.items() if name == 'main'}
                result['checks'].append({'name': 'synthetic_main_emits_entry',
                                         'passed': bool(entries), 'detail': list(entries)})
                result['observations'] = entries
            else:
                result['checks'], result['observations'] = observe(items, level)
        except (ValueError, IndexError) as error:
            result['observation_error'] = str(error)
    result['passed'] = (process.returncode == 0 and bool(result['checks'])
                        and all(item['passed'] for item in result['checks'])
                        and 'observation_error' not in result)
    result['outputs'] = {str(p.relative_to(destination)): sha(p) for p in destination.rglob('*')
                         if p.is_file() and p.suffix in ('.bc', '.ll', '.chirtxt', '.cjo')}
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True, help='real compiler cjc-frontend entry')
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--jobs', type=int, default=os.cpu_count())
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    source = Path(__file__).with_name('tail.cj')
    result = {'compiler': str(args.compiler), 'compiler_sha256': sha(args.compiler),
              'fixture_sha256': sha(source), 'harness_sha256': sha(Path(__file__)),
              'main_fixture_sha256': sha(Path(__file__).with_name('main.cj')),
              'affinity': sorted(os.sched_getaffinity(0)), 'jobs': args.jobs, 'parallel_arms': 4}
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        jobs = {level: pool.submit(compile_case, args.compiler, source, args.out / level, level, args.jobs)
                for level in ('O0', 'O1')}
        jobs.update({f'main-{level}': pool.submit(compile_case, args.compiler,
                     Path(__file__).with_name('main.cj'), args.out / f'main-{level}', level,
                     args.jobs, True) for level in ('O0', 'O1')})
        result['cases'] = {level: future.result() for level, future in jobs.items()}
    for level, case in result['cases'].items():
        print(f'COMPILE {level} rc={case["compiler_rc"]} wall={case["wall"]:.3f}')
        for item in case['checks']:
            print(f'ASSERT {level} {item["name"]} {"PASS" if item["passed"] else "FAIL"} {item["detail"]}')
        if 'observation_error' in case:
            print('OBSERVATION_ERROR', case['observation_error'])
    (args.out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if all(case['passed'] for case in result['cases'].values()) else 1


if __name__ == '__main__':
    raise SystemExit(main())
