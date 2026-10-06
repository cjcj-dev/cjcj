#!/usr/bin/env python3
"""Exercise CLI stdout and atexit diagnostics on an existing product compiler."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    compiler = args.compiler.resolve(strict=True)
    source = args.source.resolve(strict=True)
    args.out.mkdir(parents=True, exist_ok=False)
    results = []

    def check(name, passed, detail):
        results.append(dict(name=name, passed=bool(passed), detail=detail))
        print(f'TARGET {name}: {"PASS" if passed else "FAIL"} {detail}', flush=True)

    runs = {}
    for name, flags in [('version', ['-v']),
                        ('scan', ['--scan-dependency', str(source)])]:
        for trace in (False, True):
            label = f'{name}-{"on" if trace else "off"}'
            fifo = args.out / (label + '.fifo')
            os.mkfifo(fifo)
            fd = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
            try:
                os.write(fd, b'+')
                env = dict(os.environ)
                env.pop('CARGO_MAKEFLAGS', None)
                env.pop('MFLAGS', None)
                env['MAKEFLAGS'] = f'--jobserver-auth=fifo:{fifo.resolve()}'
                env['CJPM_JOBSERVER'] = '1'
                if trace:
                    env['CJCJ_JOBSERVER_TRACE'] = '1'
                else:
                    env.pop('CJCJ_JOBSERVER_TRACE', None)
                command = [str(compiler), *flags]
                run = subprocess.run(command, env=env, capture_output=True, timeout=120)
                (args.out / (label + '.stdout')).write_bytes(run.stdout)
                (args.out / (label + '.stderr')).write_bytes(run.stderr)
                (args.out / (label + '.rc')).write_text(str(run.returncode) + '\n')
                runs[label] = dict(command=command, rc=run.returncode,
                                   stdout=run.stdout.decode(), stderr=run.stderr.decode())
                check(label + '-exit', run.returncode == 0, f'rc={run.returncode}')
                try:
                    token = os.read(fd, 2)
                except BlockingIOError:
                    token = b''
                check(label + '-fifo', token == b'+', f'returned={token!r}')
            finally:
                os.close(fd)
                fifo.unlink()

        off, on = runs[name + '-off'], runs[name + '-on']
        check(name + '-stdout-stable', off['stdout'] == on['stdout'], 'trace off/on byte comparison')
        for suffix in ('off', 'on'):
            output = runs[name + '-' + suffix]['stdout']
            if name == 'scan':
                try:
                    value = json.loads(output)
                    valid = isinstance(value, (list, dict))
                except json.JSONDecodeError:
                    valid = False
            else:
                # Match cjpm's consumption of everything after Target: as a triple.
                target = output.split('Target:', 1)[-1].strip()
                valid = ('Cangjie Compiler:' in output and
                         re.fullmatch(r'[\w]+-[\w]+-[\w]+-[\w]+', target) is not None)
            check(name + '-' + suffix + '-protocol', valid, 'complete stdout consumed')
        diagnostic = re.findall(
            r'^CJCJ_JOBSERVER acquired=(\d+) released=(\d+) active=(\d+) '
            r'peak=(\d+) held_tokens=(\d+)$', on['stdout'] + on['stderr'], re.M)
        check(name + '-diagnostic-channel', len(diagnostic) == 1 and
              'CJCJ_JOBSERVER' not in on['stdout'], 'atexit statistics exclusively on stderr')
        check(name + '-trace-off', 'CJCJ_JOBSERVER' not in off['stdout'] + off['stderr'],
              'no statistics with trace unset')
        check(name + '-lease-balance', len(diagnostic) == 1 and
              diagnostic[0][0] == diagnostic[0][1] and diagnostic[0][2] == '0' and
              diagnostic[0][4] == '0', f'exit statistics={diagnostic}')

    record = dict(compiler=str(compiler),
                  compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),
                  source=str(source), runs=runs, results=results)
    (args.out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return 0 if all(item['passed'] for item in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
