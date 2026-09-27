#!/usr/bin/env python3
"""Run real pinned harness entries against controlled load readings, not host load."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from adapt import prepare

BOOT = '''import os, runpy, sys, time, traceback
root, entry, target = sys.argv[1:4]
sys.path.insert(0, root)
sys.argv = [entry] + sys.argv[4:]
first = None
def controlled_load():
    global first
    if any(frame.name == target for frame in traceback.extract_stack()):
        if first is None:
            first = time.monotonic()
        return (201.0 if time.monotonic() - first < 2 else 0.0, 0.0, 0.0)
    return (0.0, 0.0, 0.0)
os.getloadavg = controlled_load
runpy.run_path(entry, run_name='__main__')
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('inputs', type=Path)
    parser.add_argument('sdk', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True)
    test, framework, hashes = prepare(args.inputs, args.output)
    harness = test / 'Conformance/Compiler/harness'
    env = dict(os.environ, CANGJIE_HOME=str(args.sdk), CANGJIE_TEST=str(test),
               PATH=str(args.sdk / 'bin') + ':' + os.environ['PATH'],
               PYTHONDONTWRITEBYTECODE='1')
    rows = []
    for target in ('run_commands', 'do_compile', 'do_execute'):
        out = args.output / target
        out.mkdir()
        events = out / 'admission.jsonl'
        env['CANGJIE_TEST_ADMISSION_LOG'] = str(events)
        if target == 'run_commands':
            testlist = out / 'testlist'
            testlist.write_text('Tools/cjpm/hello/hello.info\n')
            entry = framework / 'main.py'
            options = ['--test_cfg', str(test / 'testsuites/HLT/configs/cjnative/linux_x64-linux_x64/basic.cfg'),
                       '-j', '1', '--timeout=180', '--fail_exit', '--progress=silent',
                       '--json_output', str(out / 'results.json'), '--test_list', str(testlist),
                       '--output', str(out / 'results.txt'), '--temp_dir', str(out / 'temp'),
                       '--log_dir', str(out / 'logs'), str(test / 'testsuites/HLT')]
        else:
            entry = harness / 'harness.py'
            options = ['--test-root', str(test / 'Conformance/Compiler/testsuite'),
                       '--tests', 'src/regression/0006076/test_bug_0006076.cj',
                       '--work-dir', str(out / 'work'), '--cjc', str(args.sdk / 'bin/cjc'),
                       '--cjc-flags=--jobs=1', '--comp-threads', '1', '--exec-threads', '1',
                       '--log-file', str(out / 'results.log'), '--no-color', '--log-mode', 'short']
        command = [sys.executable, '-c', BOOT, str(entry.parent), str(entry), target, *options]
        with (out / 'run.log').open('w') as stream:
            result = subprocess.run(command, cwd=entry.parent, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT, timeout=180)
        observed = [json.loads(line) for line in events.read_text().splitlines()] if events.exists() else []
        pauses = [row for row in observed if row['event'] == 'pause']
        resumes = [row for row in observed if row['event'] == 'resume']
        # Observe production admission's measured load, pause and release values;
        # also require the actual upstream entry to return results for its case.
        if target == 'run_commands':
            raw = json.loads((out / 'results.json').read_text())
            cases = [case for group in raw for case in group['tests']]
            completed = len(cases) == 1 and cases[0]['result'] == 'PASS'
        else:
            raw = json.loads((out / 'results.log.json').read_text())
            cases = [case for case in raw if 'test_path' in case]
            completed = len(cases) == 1 and cases[0]['result'] == 'PASSED'
        held = bool(pauses and resumes and pauses[0]['load1'] == 201
                    and resumes[0]['load1'] == 0
                    and resumes[0]['time'] - pauses[0]['time'] >= 2)
        row = dict(target=target, entry_rc=result.returncode, cases=len(cases),
                   completed=completed, TARGET_ADMISSION_HELD=held, events=observed)
        rows.append(row)
        print(json.dumps(row), flush=True)
    (args.output / 'verification.json').write_text(json.dumps(dict(hashes=hashes, rows=rows), indent=2))
    return int(not all(row['completed'] and row['TARGET_ADMISSION_HELD'] for row in rows))


if __name__ == '__main__':
    raise SystemExit(main())
