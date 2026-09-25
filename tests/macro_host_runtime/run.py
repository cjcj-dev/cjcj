#!/usr/bin/env python3
"""Run real macro expansion through stage1 and inspect its CHIR and loader bindings.

Use an official-host SDK for both compiler and macro std/runtime. The caller
chooses whether compiler-relative runtime and host-runtime are the same inode.
No product hooks, preload libraries, or substitute runtime entry points are used.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'chir_builder'))
from decoded_compare import Package


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def functions(path):
    p = Package(path.read_bytes())
    tags = p.pointer(p.root, 14)
    return [p.string(p.pointer(obj, 4), 6)
            for i, obj in enumerate(p.vector(p.root, 16))
            if p.data[tags + 4 + i] == 11]


def run(compiler, source, expected, macro_import, output, host_runtime, parallel=False):
    output.mkdir(parents=True, exist_ok=False)
    cmd = [str(compiler), str(source), '--emit-chir=raw', '--output-type=staticlib',
           '--import-path', str(macro_import), '-o', str(output / 'output.chir')]
    if parallel:
        cmd.append('--parallel-macro-expansion')
    env = dict(os.environ, LD_DEBUG='bindings', LD_DEBUG_OUTPUT=str(output / 'loader'))
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    maps = set()
    with (output / 'compile.log').open('w') as log:
        process = subprocess.Popen(cmd, env=env, stdout=log, stderr=subprocess.STDOUT)
        while process.poll() is None:
            try:
                maps.update(Path(f'/proc/{process.pid}/maps').read_text().splitlines())
            except (FileNotFoundError, ProcessLookupError):
                pass
            if time.monotonic() - start > 120:
                process.kill()
                break
            time.sleep(0.01)
        rc = process.wait()
    (output / 'maps.txt').write_text('\n'.join(sorted(maps)) + '\n')
    names, decode_error = [], None
    try:
        names = functions(output / 'output.chir')
    except (OSError, ValueError, IndexError, struct.error) as error:
        decode_error = str(error)
    log = (output / 'compile.log').read_text()
    checks = {'compiler_exit': rc == 0, 'expanded_function_in_chir': expected in names,
              'host_not_reinitialized': "don't support init again" not in log,
              'no_foreign_config_layout': 'coStackSize must be in range' not in log}
    bindings = []
    for path in output.glob('loader.*'):
        bindings.extend(line for line in path.read_text(errors='replace').splitlines()
                        if any(f"symbol `{name}'" in line for name in ['RunCJTask', 'ReleaseHandle']))
    if source.stem == 'use':
        checks['host_task_binding'] = all(
            any(f"symbol `{name}'" in line and f'to {host_runtime}' in line for line in bindings)
            for name in ['RunCJTask', 'ReleaseHandle'])
    result = {'command': cmd, 'rc': rc, 'wall': time.monotonic() - start,
              'compiler_sha256': sha(compiler), 'host_runtime_sha256': sha(host_runtime),
              'affinity': sorted(os.sched_getaffinity(0)), 'uptime_before': before,
              'uptime_after': subprocess.check_output(['uptime'], text=True).strip(),
              'functions': names, 'decode_error': decode_error, 'bindings': bindings,
              'checks': checks}
    (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    for name, passed in checks.items():
        print(f"{'PASS' if passed else 'FAIL'} {source.stem}/{name}", flush=True)
    return all(checks.values())


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--macro-import', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--host-runtime', type=Path, required=True)
    p.add_argument('--parallel', action='store_true')
    args = p.parse_args()
    here = Path(__file__).resolve().parent
    # Keep the no-macro control even when the lifecycle assertion fails.
    results = [run(args.compiler.resolve(), here / source, expected, args.macro_import.resolve(),
                   args.out.resolve() / source[:-3], args.host_runtime.resolve(), args.parallel)
               for source, expected in [('use.cj', 'expandedById'), ('plain.cj', 'plainControl')]]
    return 0 if all(results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
