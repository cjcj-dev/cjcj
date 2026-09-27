#!/usr/bin/env python3
"""Run the pinned upstream Linux x86_64 suites without modifying their sources."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
import time

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


def summarize(suite, raw, root):
    data = json.loads(raw.read_text())
    if suite == 'Conformance':
        tests = [item for item in data if 'test_path' in item]
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
        name = str(Path(name).resolve().relative_to(root))
        detail = item.get('output', '') if suite != 'Conformance' else (
            item.get('compile_log', '') + '\n' + item.get('execute_log', ''))
        if not isinstance(detail, str):
            detail = json.dumps(detail, ensure_ascii=False)
        # Preserve original upstream status and logs; these are triage hints only.
        environment = [word for word in ('No such file or directory', 'command not found',
                       'timed out', 'Timeout', 'timeout has expired', 'Cannot allocate memory',
                       'No space left on device') if word in detail]
        rows.append({'suite': suite, 'name': name, 'status': status,
                     'category': STATUS[status], 'environment_hints': environment,
                     'error_summary': detail[:4000] if STATUS[status] != 'pass' else ''})
    names = [r['name'] for r in rows]
    if len(set(names)) != len(names):
        raise ValueError('Duplicate test identities in suite ' + suite)
    return sorted(rows, key=lambda r: r['name'])


def run_suite(suite, test, framework, output, env, jobs):
    out = output / suite
    out.mkdir()
    if suite == 'Conformance':
        harness = test / 'Conformance/Compiler/harness'
        command = [sys.executable, str(harness / 'harness.py'),
                   '--test-root', str(test / 'Conformance/Compiler/testsuite'),
                   '--work-dir', str(out / 'work'), '--cjc', env['CANGJIE_HOME'] + '/bin/cjc',
                   '--comp-threads', str(jobs), '--exec-threads', str(jobs),
                   '--base-timeout', '30', '--log-file', str(out / 'results.log'),
                   '--no-color', '--log-mode', 'short']
        cwd = harness
        raw = out / 'results.log.json'
    else:
        cfg = ('configs/cjnative/linux_x64-linux_x64/basic.cfg' if suite == 'HLT'
               else 'configs/cjnative/cjnative_test.cfg')
        command = [sys.executable, str(framework / 'main.py'),
                   '--test_cfg', str(test / 'testsuites' / suite / cfg),
                   '-j', str(jobs), '--timeout=180', '--retry=0', '--fail_exit',
                   '--progress=silent', '--json_output', str(out / 'results.json'),
                   '--test_list', str(test / 'testsuites' / suite / ('testlist' if suite == 'HLT' else 'cjnative_testlist')),
                   '--output', str(out / 'results.txt'), '--temp_dir', str(out / 'temp'),
                   '--log_dir', str(out / 'logs'), str(test / 'testsuites' / suite)]
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
        record['complete'] = record['rc'] in (0, 1) and record['counts']['not_run'] == 0
        dump(out / 'cases.json', rows)
        dump(out / 'failures.json', [r for r in rows if r['category'] in ('fail', 'not_run')])
    except (OSError, ValueError, KeyError, TypeError) as error:
        record.update(status='NOT_RUN', complete=False, error=str(error), counts=None, total=None)
    dump(out / 'summary.json', record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('sdk', type=Path)
    parser.add_argument('output', type=Path, help='new directory; existing outputs are never reused')
    parser.add_argument('jobs', type=int, help='total worker budget, divided among three suites')
    parser.add_argument('--inputs', type=Path, required=True,
                        help='directory containing pinned cangjie_test and cangjie_test_framework')
    args = parser.parse_args()
    sdk, output, inputs = args.sdk.resolve(), args.output.resolve(), args.inputs.resolve()
    if args.jobs < 3:
        parser.error('jobs must be at least 3')
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
    output.mkdir(parents=True, exist_ok=False)
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    # SDK scripts are sourced in a child; never mutate a shared installation.
    loaded = subprocess.check_output(['bash', '-c', 'source "$1/envsetup.sh" >&2 && env -0',
                                      'sdk-environment', str(sdk)])
    env = dict(entry.decode().split('=', 1) for entry in loaded.split(b'\0') if entry)
    env['CANGJIE_HOME'] = str(sdk)
    env['CANGJIE_TEST'] = str(test)
    env['PATH'] = str(sdk / 'bin') + ':' + env['PATH']
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    identity = {'sdk': str(sdk), 'compiler_sha256': sha(sdk / 'bin/cjc'),
                'runtime_sha256': {str(p.relative_to(sdk)): sha(p)
                                   for p in sorted((sdk / 'runtime').rglob('*.so'))},
                'pins': json.loads((HERE / 'inputs.json').read_text()),
                'inputs': str(inputs), 'jobs': args.jobs,
                'affinity': sorted(os.sched_getaffinity(0)), 'uname': list(platform.uname()),
                'uptime_before': before}
    dump(output / 'identity.json', identity)
    smoke = output / 'smoke.cj'
    smoke.write_text('main() { println("CANGJIE_TEST_SDK_READY") }\n')
    compiled = execute([str(sdk / 'bin/cjc'), str(smoke), '-o', str(output / 'smoke')],
                       output, env, output / 'smoke-compile.log')
    if compiled['rc']:
        raise RuntimeError('SDK compilation preflight failed; see smoke-compile.log')
    identity['smoke_sha256'] = sha(output / 'smoke')
    executed = execute([str(output / 'smoke')], output, env, output / 'smoke-run.log')
    if executed['rc'] or (output / 'smoke-run.log').read_text().strip() != 'CANGJIE_TEST_SDK_READY':
        raise RuntimeError('SDK execution preflight failed; see smoke-run.log')
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futures = {name: pool.submit(run_suite, name, test, framework, output, env,
                                    args.jobs // 3 + (i < args.jobs % 3))
                   for i, name in enumerate(('Conformance', 'HLT', 'LLT'))}
        summaries = {name: future.result() for name, future in futures.items()}
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
