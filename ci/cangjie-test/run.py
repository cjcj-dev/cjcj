#!/usr/bin/env python3
"""Run the pinned upstream Linux x86_64 suites without modifying their sources."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import threading
import time
from adapt import prepare as prepare_execution_inputs
from envelope import enter as enter_envelope

HERE = Path(__file__).resolve().parent
STATUS = {'PASSED': 'pass', 'PASS': 'pass', 'FAILED': 'fail', 'FAIL': 'fail',
          'ERRORED': 'fail', 'XPASS': 'fail', 'XFAIL': 'skip', 'SKIPPED': 'skip',
          'UNSUPPORTED': 'skip', 'UNRESOLVED': 'not_run', 'NOT_RUN': 'not_run',
          'PENDING': 'not_run', 'INCOMPLETE': 'not_run'}


def dump(path, value):
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')


def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()


def execute(command, cwd, env, log):
    start = time.monotonic()
    with log.open('w') as stream:
        result = subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                                stderr=subprocess.STDOUT, check=False)
    record = {'command': list(map(str, command)), 'cwd': str(cwd),
              'rc': result.returncode, 'wall': time.monotonic() - start}
    dump(log.with_suffix('.execution.json'), record)
    return record


# Triage-only text signatures; never reclassify or exempt a failure.
# Reason text records the environment condition each signature points at.
ENVIRONMENT_SIGNATURES = (
    ('No such directory:',
     "compiler search path missing (the recipe consumes CANGJIE_STDX_PATH per "
     "cangjie_build docs/linux.md:251-260; stdx libraries not found under it)"),
    ('can not find package',
     'package absent from the module search path (stdx/std extension or java '
     'interop binding not installed, or import path unset)'),
    ('No such file or directory',
     'referenced file or executable absent from the environment'),
    ('command not found', 'required executable absent from PATH'),
    ('Cannot allocate memory', 'host out of memory while running the case'),
    ('No space left on device', 'filesystem full while running the case'),
)


TIMEOUT_REASONS = dict.fromkeys(
    ('TimeOut', 'timeout has expired'), 'case or command exceeded its time limit')


def environment_hints(detail, timeout_failure=False):
    # Reuse the suite's upstream timeout verdict, never a mention in source text.
    timeout_hint = 'timeout has expired' if isinstance(detail, str) else 'TimeOut'
    if not isinstance(detail, str):
        detail = json.dumps(detail, ensure_ascii=False)
    hints = [signature for signature, _ in ENVIRONMENT_SIGNATURES if signature in detail]
    if timeout_failure:
        hints.append(timeout_hint)
    return hints


def environment_evidence(detail, hints):
    if not isinstance(detail, str):
        detail = json.dumps(detail, ensure_ascii=False)
    # Maple serializes cmd before stderr. Anchor each excerpt at the diagnostic,
    # never at the start of that potentially very long command record.
    excerpts = []
    for hint in hints:
        position = detail.find(hint)
        if position < 0:
            continue
        start = max(detail.rfind('\n', 0, position) + 1, position - 80)
        end = detail.find('\n', position)
        if end < 0:
            end = len(detail)
        excerpt = detail[start:min(end, position + 300)].strip()
        if excerpt not in excerpts:
            excerpts.append(excerpt)
    return '\n'.join(excerpts) if excerpts else detail.strip()[:300]


def environment_failures(rows):
    reasons = dict(ENVIRONMENT_SIGNATURES, **TIMEOUT_REASONS)
    result = []
    for row in rows:
        if row['category'] not in ('fail', 'not_run') or not row['environment_hints']:
            continue
        result.append({'suite': row['suite'], 'name': row['name'], 'status': row['status'],
                       'hints': row['environment_hints'],
                       'reasons': sorted({reasons[h] for h in row['environment_hints']}),
                       'error_evidence': environment_evidence(row['error_summary'],
                                                              row['environment_hints'])})
    return result


def summarize(suite, raw, root):
    data = json.loads(raw.read_text())
    if suite == 'Conformance':
        tests = [item for item in data if 'test_path' in item]
        expected = sum(1 for _ in (root / 'Conformance/Compiler/testsuite').rglob('test*.cj'))
        if len(tests) != expected:
            raise ValueError(f'Conformance inventory mismatch: {len(tests)} records, {expected} input cases')
    else:
        tests = [item for group in data for item in group['tests']]
        if sum(group['total'] for group in data) != len(tests):
            raise ValueError('Maple total differs from unfiltered result records')
    if not tests:
        raise ValueError('ZERO_CASES: no test records; this is not a passing suite')
    rows = []
    for item in tests:
        status = item['result']
        if status not in STATUS:
            raise ValueError('Unknown upstream status: ' + status)
        name = item.get('test_path', item.get('name'))
        case = Path(name)
        if not case.is_absolute():
            base = root / 'testsuites' / suite if suite != 'Conformance' else root / 'Conformance/Compiler/testsuite'
            case = base / case
        name = str(case.resolve().relative_to(root))
        detail = item.get('output', '') if suite != 'Conformance' else (
            item.get('compile_log', '') + '\n' + item.get('execute_log', ''))
        # Exact upstream timeout signatures; do not classify arbitrary mentions.
        timeout_failure = STATUS[status] == 'fail' and (
            bool(re.search(r'The [0-9.]+-second timeout has expired', detail))
            if suite == 'Conformance' else
            isinstance(detail, list) and any(isinstance(command, dict)
                and command.get('return_code') == 3 and command.get('stderr') == 'TimeOut'
                for command in detail))
        # Maple stops at the failed command; its XML reporter uses the last result.
        summary_detail = detail[-1] if isinstance(detail, list) and detail else detail
        if not isinstance(summary_detail, str):
            summary_detail = json.dumps(summary_detail, ensure_ascii=False)
        if len(summary_detail) > 4000:
            summary_detail = summary_detail[:1000] + '\n... [see raw results] ...\n' + summary_detail[-2900:]
        # Preserve original upstream status and logs; these are triage hints only.
        environment = environment_hints(detail, timeout_failure)
        rows.append({'suite': suite, 'name': name, 'status': status,
                     'category': STATUS[status], 'environment_hints': environment,
                     'timeout_failure': timeout_failure,
                     'error_summary': summary_detail if STATUS[status] != 'pass' else ''})
    names = [r['name'] for r in rows]
    if len(set(names)) != len(names):
        raise ValueError('Duplicate test identities in suite ' + suite)
    return sorted(rows, key=lambda r: r['name'])


def dump_case_rows(out, rows):
    dump(out / 'cases.json', rows)
    dump(out / 'failures.json', [r for r in rows if r['category'] in ('fail', 'not_run')])
    dump(out / 'timeout-failures.json', [r for r in rows if r['timeout_failure']])
    environmental = environment_failures(rows)
    dump(out / 'environment-failures.json', environmental)
    return environmental


def run_suite(suite, test, framework, output, env, jobs, scratch=None, compiler_jobs=1):
    out = output / suite
    out.mkdir()
    bulk = scratch / suite if scratch else out
    bulk.mkdir(parents=True, exist_ok=True)
    if suite == 'Conformance':
        harness = test / 'Conformance/Compiler/harness'
        command = [sys.executable, str(harness / 'harness.py'),
                   '--test-root', str(test / 'Conformance/Compiler/testsuite'),
                   '--work-dir', str(bulk / 'work'), '--cjc', env['CANGJIE_HOME'] + '/bin/cjc',
                   '--comp-threads', str(max(1, jobs // 2)), '--exec-threads', str(jobs - max(1, jobs // 2)),
                   '--cjc-flags=--jobs=' + str(compiler_jobs),
                   '--base-timeout', '30', '--log-file', str(out / 'results.log'),
                   '--no-color', '--log-mode', 'short']
        cwd = harness
        raw = out / 'results.log.json'
    else:
        cfg = ('configs/cjnative/linux_x64-linux_x64/basic.cfg' if suite == 'HLT'
               else 'configs/cjnative/cjnative_test.cfg')
        command = [sys.executable, str(framework / 'main.py'),
                   '--test_cfg', str(test / 'testsuites' / suite / cfg),
                   '-j', str(jobs), '--timeout=180', '--fail_exit',
                   '--progress=silent', '--json_output', str(out / 'results.json'),
                   '--test_list', str(test / 'testsuites' / suite / ('testlist' if suite == 'HLT' else 'cjnative_testlist')),
                   '--output', str(out / 'results.txt'), '--temp_dir', str(bulk / 'temp'),
                   '--log_dir', str(bulk / 'logs'), str(test / 'testsuites' / suite)]
        cwd = framework
        raw = out / 'results.json'
    record = execute(command, cwd, env, out / 'runner.log')
    try:
        rows = summarize(suite, raw, test)
        record['counts'] = {key: sum(r['category'] == key for r in rows)
                            for key in ('pass', 'fail', 'skip', 'not_run')}
        record['total'] = len(rows)
        record['status'] = 'ran'
        # A framework error must remain visible even when partial records exist.
        record['complete'] = (record['rc'] in (0, 1) and record['counts']['not_run'] == 0
                              and record['counts']['pass'] + record['counts']['fail'] > 0)
        environmental = dump_case_rows(out, rows)
        record['environment_failure_count'] = len(environmental)
    except (OSError, ValueError, KeyError, TypeError) as error:
        record.update(status='NOT_RUN', complete=False, error=str(error), counts=None, total=None)
    dump(out / 'summary.json', record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sdk', type=Path)
    parser.add_argument('output', type=Path, help='new directory; existing outputs are never reused')
    parser.add_argument('jobs', type=int, nargs='?', default=48, help='total workers across both Conformance pools and two Maple pools (4..48)')
    parser.add_argument('--inputs', type=Path, required=True,
                        help='directory containing pinned cangjie_test and cangjie_test_framework')
    parser.add_argument('--compiler-jobs', type=int, choices=(1, 2), default=1,
                        help='Conformance compiler parallelism; Maple uses unmodified test options inside CPU scope')
    parser.add_argument('--scratch', type=Path,
                        help='separate bulk directory for work/temp/log dirs (results stay in output)')
    parser.add_argument('--suites', default='Conformance,HLT,LLT',
                        help='comma-separated subset of Conformance,HLT,LLT (default: all three)')
    args = parser.parse_args()
    selected = args.suites.split(',')
    if not selected or any(name not in ('Conformance', 'HLT', 'LLT') for name in selected) \
            or len(set(selected)) != len(selected):
        parser.error('--suites must be a comma-separated subset of Conformance,HLT,LLT')
    sdk, output, inputs = args.sdk.resolve(), args.output.resolve(), args.inputs.resolve()
    if not 4 <= args.jobs <= 48:
        parser.error('jobs must be between 4 and 48 (including both Conformance pools)')
    if not (sdk / 'bin/cjc').is_file() or not (sdk / 'envsetup.sh').is_file():
        parser.error('INVALID_SDK: expected bin/cjc and envsetup.sh in SDK root')
    if platform.machine() != 'x86_64' or platform.system() != 'Linux':
        parser.error('the pinned recipe requires Linux x86_64')
    test, framework = inputs / 'cangjie_test', inputs / 'cangjie_test_framework'
    for path in (test / 'Conformance/Compiler/harness/harness.py', framework / 'main.py'):
        if not path.is_file():
            parser.error('missing input: ' + str(path))
    manifest = json.loads((inputs / 'source-manifest.json').read_text())
    if manifest['pins'] != json.loads((HERE / 'inputs.json').read_text()):
        parser.error('input pins differ from this runner')
    for name, expected in manifest['files'].items():
        if sha(inputs / name) != expected:
            parser.error('input content changed: ' + name)
    envelope = enter_envelope()
    if isinstance(envelope, int):
        return envelope
    output.mkdir(parents=True, exist_ok=False)
    scratch = None
    if args.scratch:
        scratch = args.scratch.resolve()
        scratch.mkdir(parents=True, exist_ok=False)
    # Admission preflight (0927 14:3x ruling): refuse to start under heavy load or low disk.
    load1 = float(Path('/proc/loadavg').read_text().split()[0])
    free_gib = shutil.disk_usage(output).free / 2**30
    if load1 > 200:
        parser.error(f'LOAD_ADMISSION: load1={load1:.1f} > 200; not starting new cases')
    if free_gib < 8:
        parser.error(f'DISK_ADMISSION: free={free_gib:.1f}GiB < 8GiB; not starting new cases')
    test, framework, adapter_hashes = prepare_execution_inputs(inputs, output)
    stop_monitor = threading.Event()

    def monitor():
        with (output / 'load-monitor.log').open('w') as stream:
            while not stop_monitor.is_set():
                loads = Path('/proc/loadavg').read_text().split()[:3]
                disk = shutil.disk_usage(output).free / 2**30
                stream.write(f'{time.strftime("%H:%M:%S")} load={"/".join(loads)} free_gib={disk:.1f}\n')
                stream.flush()
                stop_monitor.wait(60)

    watcher = threading.Thread(target=monitor, daemon=True)
    watcher.start()
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    # SDK scripts are sourced in a child; never mutate a shared installation.
    loaded = subprocess.check_output(['bash', '-c', 'source "$1/envsetup.sh" >&2 && env -0',
                                      'sdk-environment', str(sdk)])
    env = dict(entry.decode().split('=', 1) for entry in loaded.split(b'\0') if entry)
    env['CANGJIE_HOME'] = str(sdk)
    env['CANGJIE_TEST'] = str(test)
    env['CANGJIE_TEST_ADMISSION_LOG'] = str(output / 'admission.jsonl')
    env['PATH'] = str(sdk / 'bin') + ':' + env['PATH']
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    identity = {'sdk': str(sdk), 'compiler_sha256': sha(sdk / 'bin/cjc'),
                'runtime_sha256': {str(p.relative_to(sdk)): sha(p)
                                   for p in sorted((sdk / 'runtime').rglob('*.so'))},
                'pins': json.loads((HERE / 'inputs.json').read_text()),
                'recipe_sha256': sha(HERE / 'run.py'),
                'adapter_hashes': adapter_hashes,
                'cpu_envelope': envelope,
                'adapter_source_sha256': {p.name: sha(p) for p in sorted(HERE.glob('*.py'))},
                'source_manifest_sha256': sha(inputs / 'source-manifest.json'),
                'inputs': str(inputs), 'jobs': args.jobs, 'compiler_jobs': args.compiler_jobs,
                'affinity': sorted(os.sched_getaffinity(0)), 'uname': list(platform.uname()),
                'uptime_before': before}
    dump(output / 'identity.json', identity)
    smoke = output / 'smoke.cj'
    smoke.write_text('main() { println("CANGJIE_TEST_SDK_READY") }\n')
    compiled = execute([str(sdk / 'bin/cjc'), '--jobs', str(args.compiler_jobs), str(smoke), '-o', str(output / 'smoke')],
                       output, env, output / 'smoke-compile.log')
    if compiled['rc']:
        raise RuntimeError('SDK compilation preflight failed; see smoke-compile.log')
    identity['smoke_sha256'] = sha(output / 'smoke')
    executed = execute([str(output / 'smoke')], output, env, output / 'smoke-run.log')
    if executed['rc'] or (output / 'smoke-run.log').read_text().strip() != 'CANGJIE_TEST_SDK_READY':
        raise RuntimeError('SDK execution preflight failed; see smoke-run.log')
    (output / 'smoke').unlink()
    # Worker units: Conformance occupies two pools (compile + execute); each Maple suite one.
    units = (2 if 'Conformance' in selected else 0) + sum(1 for name in ('HLT', 'LLT') if name in selected)
    per_unit = args.jobs // units
    extra = args.jobs - per_unit * units
    workers = {}
    for name in selected:
        share = per_unit * (2 if name == 'Conformance' else 1)
        if extra:
            share += extra
            extra = 0
        workers[name] = share
    identity['suite_workers'] = workers
    identity['suites'] = selected
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(selected)) as pool:
        futures = {name: pool.submit(run_suite, name, test, framework, output, env,
                                     workers[name], scratch, args.compiler_jobs)
                   for name in selected}
        summaries = {name: future.result() for name, future in futures.items()}
    stop_monitor.set()
    watcher.join()
    identity.update(uptime_after=subprocess.check_output(['uptime'], text=True).strip(),
                    wall=time.monotonic() - start)
    dump(output / 'identity.json', identity)
    dump(output / 'summary.json', summaries)
    failed = any(s['status'] != 'ran' or not s['complete'] or s['counts']['fail']
                 or s['rc'] != 0 for s in summaries.values())
    print(json.dumps(summaries, indent=2))
    return 1 if failed else 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('CANGJIE_TEST_ERROR: ' + str(error), file=sys.stderr)
        sys.exit(2)
