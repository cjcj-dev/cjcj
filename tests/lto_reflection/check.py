#!/usr/bin/env python3
"""Compile real fixtures with stage1 and assert the opt command's reflection flag.
No substituted backend or driver component is used. Compilation must succeed
before any target assertion counts as executed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    compiler, out = args.compiler.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).resolve().parent
    results = {}
    flag = '--cj-disable-lto-reflection'

    def compile_case(name, source, options, expected):
        dest = out / name
        dest.mkdir(exist_ok=True)
        command = [str(compiler), str(fixtures / source), '--output-type=staticlib',
                   '-O0', '--verbose', '-o', str(dest / 'result.a'), *options]
        start = time.monotonic()
        run = subprocess.run(command, cwd=dest, text=True, stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, timeout=180)
        (dest / 'compile.log').write_text(run.stdout)
        record = dict(command=command, compile_rc=run.returncode,
                      wall=time.monotonic() - start, expected=expected)
        # Read only executed opt commands, not frontend arguments or diagnostics.
        commands = []
        for line in run.stdout.splitlines():
            try:
                tokens = shlex.split(line)
            except ValueError:
                continue
            while tokens and tokens[0].startswith('LD_LIBRARY_PATH='):
                tokens.pop(0)
            if tokens and Path(tokens[0]).name in ('opt', 'opt-stage1'):
                commands.append(tokens)
        record['opt_commands'] = commands
        if run.returncode != 0 or not commands:
            record['status'] = 'NOT_RUN'
            print(f'NOT_RUN {name}: compile_rc={run.returncode}, opt_commands={len(commands)}')
        else:
            observed = [flag in tokens for tokens in commands]
            record['observed'] = observed
            record['status'] = 'PASS' if all(x == expected for x in observed) else 'FAIL'
            print(f'EXECUTED {name} expected={expected} observed={observed} {record["status"]}')
        results[name] = record
        return dest

    before = subprocess.check_output(['uptime'], text=True)
    for lto in ('full', 'thin'):
        compile_case(lto + '_disabled_plain', 'plain.cj',
                     ['--lto=' + lto, '--disable-reflection'], True)
        compile_case(lto + '_enabled_plain', 'plain.cj', ['--lto=' + lto], False)
        direct = compile_case(lto + '_disabled_direct', 'direct.cj',
                              ['--lto=' + lto, '--disable-reflection'], False)
        compile_case(lto + '_disabled_indirect', 'indirect.cj',
                     ['--lto=' + lto, '--disable-reflection', '--import-path', str(direct)], False)
    compile_case('no_lto_disabled', 'plain.cj', ['--disable-reflection'], False)
    result = dict(compiler=str(compiler), compiler_sha256=sha(compiler),
                  fixtures={p.name: sha(p) for p in fixtures.glob('*.cj')},
                  checker_sha256=sha(Path(__file__)), results=results,
                  affinity=sorted(os.sched_getaffinity(0)), uptime_before=before,
                  uptime_after=subprocess.check_output(['uptime'], text=True))
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 2 if any(r['status'] == 'NOT_RUN' for r in results.values()) else int(
        any(r['status'] != 'PASS' for r in results.values()))


if __name__ == '__main__':
    raise SystemExit(main())
