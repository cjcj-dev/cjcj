#!/usr/bin/env python3
"""Stage1 check: an invisible extend member must not hide an inherited member."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def strip_ansi(text):
    return re.sub(r'\x1b\[[0-9;]*m', '', text)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--compiler', type=Path, required=True)
    p.add_argument('--sdk', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    here = Path(__file__).resolve().parent
    env = dict(os.environ, CANGJIE_HOME=str(a.sdk), cjHeapSize='32GB')
    env['LD_LIBRARY_PATH'] = ':'.join(str(a.sdk / part) for part in (
        'runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative',
        'third_party/llvm/lib', 'tools/lib')) + ':/usr/lib/x86_64-linux-gnu'
    record = {
        'compiler': str(a.compiler),
        'compiler_sha256': sha(a.compiler),
        'affinity': sorted(os.sched_getaffinity(0)),
        'uptime_before': subprocess.check_output(['uptime'], text=True),
        'libraries': {str(f): sha(f) for f in sorted(
            (a.sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so'))},
        'checks': {},
    }

    def compile_one(name, sources, extra):
        log_path = a.out / (name + '.log')
        cmd = [str(a.compiler), *[str(s) for s in sources], *extra]
        start = time.monotonic()
        with log_path.open('w') as log:
            rc = subprocess.run(cmd, env=env, cwd=a.out, stdout=log,
                                stderr=subprocess.STDOUT, timeout=180).returncode
        text = strip_ansi(log_path.read_text(errors='replace'))
        return rc, text, cmd, time.monotonic() - start

    base = here / 'base.cj'
    base_rc, base_text, base_cmd, base_wall = compile_one(
        'base', [base], ['--output-type=staticlib', '-o', 'libbasepkg.a'])
    record['base'] = {'rc': base_rc, 'command': base_cmd, 'wall': base_wall,
                      'fixture_sha256': sha(base)}
    if base_rc != 0 or not (a.out / 'basepkg.cjo').is_file():
        record['checks']['base_package'] = {'pass': False, 'rc': base_rc, 'log': base_text[-2000:]}
        record['rc'] = 2
        record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
        (a.out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
        print('ASSERT base_package FAIL rc=%s' % base_rc, flush=True)
        return 2

    child = here / 'child.cj'
    child_bin = a.out / 'child'
    child_rc, child_text, child_cmd, child_wall = compile_one(
        'child', [child], ['--import-path', str(a.out), '-L', str(a.out), '-lbasepkg', '-o', str(child_bin)])
    stdout = ''
    run_rc = None
    if child_rc == 0 and child_bin.is_file():
        run = subprocess.run([str(child_bin)], env=env, cwd=a.out, text=True,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
        stdout = run.stdout
        run_rc = run.returncode
    target_ok = child_rc == 0 and run_rc == 0 and stdout == '4\n3\n' and 'cannot override function' not in child_text
    record['checks']['invisible_extend_does_not_hide_parent'] = {
        'pass': target_ok, 'compile_rc': child_rc, 'run_rc': run_rc, 'stdout': stdout,
        'command': child_cmd, 'wall': child_wall, 'fixture_sha256': sha(child),
        'log': child_text[-2000:],
    }
    print('ASSERT invisible_extend_does_not_hide_parent %s compile_rc=%s run_rc=%s stdout=%r' % (
        'PASS' if target_ok else 'FAIL', child_rc, run_rc, stdout), flush=True)

    shadow = here / 'shadow.cj'
    shadow_rc, shadow_text, shadow_cmd, shadow_wall = compile_one(
        'shadow', [shadow], ['--import-path', str(a.out), '--output-type=staticlib', '-o', 'libshadow.a'])
    shadow_ok = shadow_rc == 1 and "cannot override function 'shown'" in shadow_text
    record['checks']['visible_extend_still_conflicts'] = {
        'pass': shadow_ok, 'rc': shadow_rc, 'command': shadow_cmd, 'wall': shadow_wall,
        'fixture_sha256': sha(shadow), 'log': shadow_text[-2000:],
    }
    print('ASSERT visible_extend_still_conflicts %s rc=%s' % (
        'PASS' if shadow_ok else 'FAIL', shadow_rc), flush=True)

    same = here / 'same.cj'
    same_rc, same_text, same_cmd, same_wall = compile_one(
        'same', [same], ['--output-type=staticlib', '-o', 'libsame.a'])
    same_ok = same_rc == 1 and "cannot override function 'hidden'" in same_text
    record['checks']['same_package_internal_still_conflicts'] = {
        'pass': same_ok, 'rc': same_rc, 'command': same_cmd, 'wall': same_wall,
        'fixture_sha256': sha(same), 'log': same_text[-2000:],
    }
    print('ASSERT same_package_internal_still_conflicts %s rc=%s' % (
        'PASS' if same_ok else 'FAIL', same_rc), flush=True)

    record['rc'] = 0 if all(v['pass'] for v in record['checks'].values()) else 1
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (a.out / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
    return record['rc']


if __name__ == '__main__':
    raise SystemExit(main())
