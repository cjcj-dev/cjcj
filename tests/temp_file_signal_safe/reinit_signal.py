#!/usr/bin/env python3
"""Observe the real Init/native-free/SIGINT overlap on x86-64 Linux.

GDB selects the delivery instant without replacing product calls or memory.
The assertion reads native deletion arguments and the actual process exit.
"""
import argparse
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
    p.add_argument('--tree', type=Path, required=True)
    p.add_argument('--sdk', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--dependencies', type=Path, required=True)
    args = p.parse_args()
    tree, sdk, out, deps = (x.resolve() for x in (args.tree, args.sdk, args.out, args.dependencies))
    out.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(CANGJIE_HOME=str(sdk), TMPDIR=str(out), cjHeapSize='32GB')
    env['LD_LIBRARY_PATH'] = ':'.join(str(sdk / x) for x in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    source = tree / 'tests/temp_file_signal_safe/reinit_signal.cj'
    observer = tree / 'tests/temp_file_signal_safe/reinit_signal.gdb.py'
    elf = out / 'fixture'
    cmd = [str(sdk / 'bin/cjc'), str(source), '-O2', '--trimpath', str(tree), '-o', str(elf)]
    archives, inputs = [], [source, observer, sdk / 'bin/cjc']
    for name in ('basic', 'utils', 'option'):
        d = (tree if name == 'option' else deps) / 'target/release' / (name + '@cjcj')
        cmd += ['--import-path', str(d), '-L', str(d)]
        archives += sorted(d.glob('*.a'))
        inputs += sorted(d.glob('*.cjo'))
    cmd += ['--link-options=--start-group ' + ' '.join(map(str, archives)) + ' --end-group']
    inputs += archives + list((sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))
    inputs += [sdk / 'lib/linux_x86_64_cjnative/libcangjie-std-core.a']
    (out / 'inputs.sha256').write_text(''.join(f'{sha(x)}  {x}\n' for x in inputs))
    result = {'command': cmd, 'affinity': sorted(os.sched_getaffinity(0)),
              'uptime_before': subprocess.check_output(['uptime'], text=True), 'tests': []}
    start = time.monotonic()
    with (out / 'build.log').open('w') as log:
        rc = subprocess.call(cmd, env=env, stdout=log, stderr=subprocess.STDOUT)
    result.update(build_rc=rc, build_wall=time.monotonic() - start)
    if rc == 0:
        result['elf_sha256'] = sha(elf)
        with (out / 'symbols.txt').open('w') as log:
            result['nm_rc'] = subprocess.call(['nm', '--defined-only', str(elf)], stdout=log)
        for timing in ('before', 'after'):
            manifest = out / (timing + '-paths.txt')
            record = out / (timing + '.json')
            env.update(OBS_RESULT=str(record), SIGNAL_TIMING=timing)
            command = ['gdb', '-q', '-batch', '-x', str(observer), '--args', str(elf), str(manifest)]
            start = time.monotonic()
            with (out / (timing + '.log')).open('w') as log:
                gdb_rc = subprocess.call(command, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=90)
            obs = json.loads(record.read_text()) if record.exists() else {}
            paths = manifest.read_text().splitlines() if manifest.exists() else []
            setup = gdb_rc == 0 and len(obs.get('freed', [])) == 1 and len(paths) == 2 and obs.get('exit_codes') == [130]
            # Even before the first free, Init owns this clearing transition.
            # No handler traversal may expose a partially released list.
            target = setup and obs.get('calls') == [] and all(Path(x).exists() for x in paths)
            print(f'TARGET reinit-{timing}: reached={setup} noTraversal={target}', flush=True)
            result['tests'].append({'timing': timing, 'command': command, 'gdb_rc': gdb_rc,
                                    'wall': time.monotonic() - start, 'setup': setup, 'pass': target,
                                    'observation': obs, 'remaining': {x: Path(x).exists() for x in paths}})
            if not target:
                rc = 1
    result['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    result['rc'] = rc
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return rc


if __name__ == '__main__':
    raise SystemExit(main())
