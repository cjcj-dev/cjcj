#!/usr/bin/env python3
"""Run actual stage1 compilers; record CHIR bytes and temporary member assertions.

All arms receive the same source paths, options, SDK and environment. Assertions
are added by instrument.py only in disposable builds. A successful compiler exit
without the expected observation is NOT proof that the insertion path ran.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--arm', action='append', required=True, help='name=/absolute/compiler')
    p.add_argument('--sdk', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--fixtures', type=Path, default=Path(__file__).parent)
    p.add_argument('--ordinary-dir', type=Path, action='append', default=[])
    args = p.parse_args()
    arms = dict(item.split('=', 1) for item in args.arm)
    inputs = [(f, True) for f in sorted(args.fixtures.glob('*.cj'))]
    for directory in args.ordinary_dir:
        inputs += [(f, False) for f in sorted(directory.glob('*.cj'))]
    env = dict(os.environ, CANGJIE_HOME=str(args.sdk), cjHeapSize='16GB')
    env['LD_LIBRARY_PATH'] = ':'.join(str(args.sdk / part) for part in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    args.out.mkdir(parents=True, exist_ok=True)
    summary = {'compilers': {name: {'path': path, 'sha256': sha(Path(path))}
                             for name, path in arms.items()},
               'runtime': {str(f): sha(f) for f in sorted(
                   (args.sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))},
               'affinity': sorted(os.sched_getaffinity(0)),
               'uptime_before': subprocess.check_output(['uptime'], text=True),
               'cases': []}

    def run(arm, compiler, source, no_prelude):
        label = ('core-' if no_prelude else 'ordinary-') + source.stem
        dest = args.out / arm / label
        dest.mkdir(parents=True, exist_ok=True)
        cmd = [compiler, str(source), '--emit-chir=opt', '--dump-chir',
               '--output-type=staticlib', '--jobs', '1', '-o', str(dest / 'output.chir')]
        if no_prelude:
            cmd.append('--no-prelude')
        start = time.monotonic()
        with (dest / 'compile.log').open('w') as log:
            try:
                rc = subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=180).returncode
            except subprocess.TimeoutExpired:
                rc = 124
        output = (dest / 'compile.log').read_text(errors='replace')
        record = dict(arm=arm, name=label, source=str(source), source_sha256=sha(source),
                      command=cmd, rc=rc, wall=time.monotonic() - start,
                      assertions=[s for s in output.splitlines() if 'CONSTEVAL ' in s],
                      outputs={str(f.relative_to(dest)): sha(f)
                               for f in dest.rglob('*.chir')}, log=str(dest / 'compile.log'))
        (dest / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
        print(arm, label, 'rc=' + str(rc), record['assertions'], flush=True)
        return record

    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        pending = [pool.submit(run, arm, compiler, f, mode)
                   for arm, compiler in arms.items() for f, mode in inputs]
        for future in concurrent.futures.as_completed(pending):
            summary['cases'].append(future.result())
            (args.out / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')
    summary['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (args.out / 'result.json').write_text(json.dumps(summary, indent=2) + '\n')
    # This collector reports every real exit code; verify.py evaluates the arms.


if __name__ == '__main__':
    main()
