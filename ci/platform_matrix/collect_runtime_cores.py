#!/usr/bin/env python3
"""Failure-only colour-runtime diagnostics; never changes gate assertions/status."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess


def gdb(args, output):
    try:
        result = subprocess.run(
            ['gdb', '-nx', '-batch', *args], stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, timeout=120, env={**os.environ, 'DEBUGINFOD_URLS': ''})
        output.write_bytes(result.stdout)
        return result.returncode
    except (OSError, subprocess.TimeoutExpired) as exc:
        output.write_text(f'gdb unavailable or incomplete: {exc}\n')
        return 127


def collect(source, diagnostics):
    diagnostics.mkdir(parents=True, exist_ok=True)
    cores = sorted((diagnostics / 'cores').glob('core.*'))
    summary = []
    # Keep original relative locations and hashes: ELF/SO files belong to this
    # build, including intermediate outputs when installation never happened.
    products = []
    for file in sorted(source.rglob('*')):
        if not file.is_file() or file.is_symlink():
            continue
        try:
            with file.open('rb') as stream:
                magic = stream.read(4)
            if magic != b'\x7fELF':
                continue
            if '.so' not in file.name and not os.access(file, os.X_OK):
                continue
            target = diagnostics / 'products' / file.relative_to(source)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, target)
            with target.open('rb') as stream:
                digest = hashlib.sha256()
                for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                    digest.update(chunk)
            products.append(f'{digest.hexdigest()}  {target.relative_to(diagnostics)}')
        except OSError as exc:
            summary.append(f'product copy failed {file}: {exc}')
    (diagnostics / 'products.sha256').write_text('\n'.join(products) + '\n')
    for core in cores:
        # Linux NT_PRPSINFO may contain only a truncated command line. Our %E
        # filename records the full executable path, with '/' encoded as '!'.
        # Prefer that over gdb's "info proc exe" (which works for gdb-made cores).
        probe = diagnostics / (core.name + '.exe.txt')
        rc = gdb(['-c', str(core), '-ex', 'info proc exe'], probe)
        match = re.search(r"exe = '([^']+)'", probe.read_text(errors='replace'))
        encoded = core.name.removeprefix('core.').rsplit('.', 2)
        executable = (Path(encoded[0].replace('!', '/'))
                      if len(encoded) == 3 and encoded[0].startswith('!')
                      else Path(match[1]) if match else None)
        args = ['-c', str(core)]
        if executable and executable.is_file():
            args = [str(executable), *args]
        else:
            summary.append(f'{core.name}: executable unresolved (probe rc={rc}); see {probe.name}')
        trace = diagnostics / (core.name + '.bt.txt')
        rc = gdb([*args, '-ex', 'set pagination off', '-ex', 'thread apply all bt full',
                  '-ex', 'info registers', '-ex', 'info sharedlibrary'], trace)
        summary.append(f'{core.name}: executable={executable} gdb_rc={rc} trace={trace.name}')
    if not cores:
        summary.append('NO_CORE: no core reached the configured workspace directory. '
                       'See setup.log for limit/configuration failures and effective core_pattern; '
                       'gate_run.log identifies whether a signal occurred or the build stopped earlier. '
                       'A killed/non-dumpable process, external core handler, or storage exhaustion '
                       'can prevent a core; no stack is claimed.')
    (diagnostics / 'summary.txt').write_text('\n'.join(summary) + '\n')
    print('\n'.join(summary))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path('runtime-source/runtime'))
    parser.add_argument('--diagnostics', type=Path, default=Path('.platform-ci/runtime-gate-diagnostics'))
    args = parser.parse_args()
    collect(args.source.resolve(), args.diagnostics.resolve())
