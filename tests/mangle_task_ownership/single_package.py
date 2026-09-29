#!/usr/bin/env python3
"""One directed testmacro compile with explicit compiler/SDK/source identity.

This is the newly authorized fixed-SDK device, not reconstruction of #679's
deleted dependency products. No full standard-library build is performed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for arg in ('compiler', 'sdk', 'source', 'output'):
        p.add_argument('--' + arg, type=Path, required=True)
    a = p.parse_args()
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    a.output.mkdir(parents=True, exist_ok=False)
    bc = a.output / 'libstd.unittest.testmacro.bc'
    cmd = [str(a.compiler), '--no-sub-pkg', '-g', '--apc=1', '--output-type=staticlib',
           '-p', str(a.source), '--lto=full', '--output', str(bc), '-O2']
    env = dict(os.environ, CANGJIE_HOME=str(a.sdk), cjHeapSize='32GB')
    env['PATH'] = ':'.join(str(a.sdk / q) for q in ('bin', 'tools/bin', 'third_party/llvm/bin')) + ':' + os.environ['PATH']
    env['LD_LIBRARY_PATH'] = ':'.join(str(a.sdk / q) for q in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'tools/lib', 'third_party/llvm/lib'))
    env['CANGJIE_PATH'] = ':'.join(str(a.sdk / q) for q in
        ('modules/linux_x86_64_cjnative', 'third_party/flatbuffers/modules'))
    env['LIBRARY_PATH'] = str(a.sdk / 'lib/linux_x86_64_cjnative')
    hashes = {str(a.compiler): sha(a.compiler)}
    for directory in ('runtime/lib/linux_x86_64_cjnative', 'modules/linux_x86_64_cjnative',
                      'third_party/flatbuffers/modules'):
        hashes.update({str(q): sha(q) for q in (a.sdk / directory).rglob('*') if q.is_file()})
    source_hashes = {str(q.relative_to(a.source)): sha(q) for q in a.source.rglob('*') if q.is_file()}
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    with (a.output / 'compile.log').open('w') as log:
        try:
            rc = subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=900).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    wall = time.monotonic() - start
    output_hash = sha(bc) if bc.is_file() else None
    dis_rc = None
    symbols = []
    if bc.is_file():
        ir = a.output / 'output.ll'
        with (a.output / 'disassemble.log').open('w') as log:
            dis_rc = subprocess.run([str(a.sdk / 'third_party/llvm/bin/llvm-dis'), str(bc), '-o', str(ir)],
                                    env=env, stdout=log, stderr=subprocess.STDOUT).returncode
        if dis_rc == 0:
            symbols = sorted(re.findall(r'^define\b.*?@("[^"]+"|[^ (]+)\(', ir.read_text(), re.MULTILINE))
    result = dict(device='new fixed official SDK; not the original #679 device', command=cmd,
                  rc=rc, wall=wall, hashes=hashes, source_hashes=source_hashes,
                  sdk=str(a.sdk), output_sha256=output_hash, disassemble_rc=dis_rc, symbols=symbols,
                  affinity=sorted(os.sched_getaffinity(0)), uptime_before=before,
                  uptime_after=subprocess.check_output(['uptime'], text=True).strip())
    (a.output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    passed = rc == 0 and output_hash is not None and dis_rc == 0 and bool(symbols)
    print(f'testmacro rc={rc} wall={wall:.2f} symbols={len(symbols)} valid_output={passed}')
    if passed:
        for q in a.output.iterdir():
            if q.suffix in ('.bc', '.ll', '.cjo', '.o', '.a'):
                q.unlink()
    return int(not passed)


if __name__ == '__main__':
    raise SystemExit(main())
