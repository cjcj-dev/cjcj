#!/usr/bin/env python3
"""Measure the real Linux stage1 entry with the official HRT GC log.

The recipe supplies argv (without the executable or -o) and env. All compared
arms must use the same recipe, source paths, SDK and host runtime. GC utilization
numerators are post-collection object bytes, not the 'collected objects' field.
Snapshots belong in a separate diagnostic run: dumping changes peak RSS.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time


def digest(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def uptime():
    return subprocess.check_output(['uptime'], text=True).strip()


def collect(args):
    recipe = json.loads(args.recipe.read_text())
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    env = dict(recipe['env'])
    env.update(HOME=str(out), TMPDIR=str(out), cjHeapSize=args.heap,
               MRT_LOG_LEVEL='i', MRT_LOG_PATH=str(out / 'runtime.log'),
               MRT_LOG_FILE_SIZE='128M')
    compiler = args.compiler.resolve(strict=True)
    command = ['taskset', '-c', args.cores, '/usr/bin/time', '-v', str(compiler),
               *recipe['argv'], '--output', str(out / 'package.a')]
    result = dict(command=command, recipe_sha256=digest(args.recipe),
                  elf_sha256=digest(compiler), cores=args.cores, heap=args.heap,
                  host_libraries={p: digest(p) for p in recipe['host_libraries']},
                  uptime_before=uptime(), started_at=time.time())
    started = time.monotonic()
    with (out / 'stdout.log').open('w') as stdout, (out / 'stderr.log').open('w') as stderr:
        try:
            rc = subprocess.run(command, cwd=out, env=env, stdout=stdout,
                                stderr=stderr, timeout=args.timeout).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    result.update(rc=rc, wall_s=time.monotonic() - started, uptime_after=uptime())
    log = (out / 'runtime.log').read_text() if (out / 'runtime.log').exists() else ''
    cycles = re.findall(r'GC for .*?utilization \((\d+)->[^/]+/(\d+)->', log)
    result['gc_cycles'] = len(cycles)
    result['gc_peak_used_obj_bytes'] = max((int(a) for a, _ in cycles), default=None)
    result['gc_peak_used_region_bytes'] = max((int(b) for _, b in cycles), default=None)
    rss = re.search(r'Maximum resident set size \(kbytes\): (\d+)',
                    (out / 'stderr.log').read_text())
    result['maxrss_kb'] = int(rss.group(1)) if rss else None
    result['outputs'] = {p.name: digest(p) for p in out.iterdir() if p.suffix in ('.a', '.cjo')}
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result))
    return 0 if rc == 0 else 1


def check(args):
    reference = json.loads(args.reference.read_text())
    candidate = json.loads(args.candidate.read_text())
    checks = {'compiler-completed': candidate['rc'] == 0,
              'reference-completed': reference['rc'] == 0,
              'gc-observed': candidate['gc_cycles'] > 0 and reference['gc_cycles'] > 0}
    for label, key, ratio in [('gc-live-bound', 'gc_peak_used_obj_bytes', args.live_ratio),
                              ('rss-bound', 'maxrss_kb', args.rss_ratio)]:
        actual, base = candidate.get(key), reference.get(key)
        checks[label] = (actual is not None and base is not None and base > 0
                         and actual <= base * ratio)
        print(f'OBSERVED {label} actual={actual} reference={base} ratio_limit={ratio}')
    if args.same_interface:
        def interfaces(result):
            return sorted(v for k, v in result['outputs'].items() if k.endswith('.cjo'))
        expected, actual = interfaces(reference), interfaces(candidate)
        checks['interface-unchanged'] = bool(expected) and actual == expected
    for label, passed in checks.items():
        print(f'{"PASS" if passed else "FAIL"} {label}')
    if args.json:
        args.json.write_text(json.dumps(checks, indent=2) + '\n')
    return 0 if all(checks.values()) else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    run = sub.add_parser('run')
    run.add_argument('--recipe', type=Path, required=True)
    run.add_argument('--compiler', type=Path, required=True)
    run.add_argument('--out', type=Path, required=True)
    run.add_argument('--cores', required=True)
    run.add_argument('--heap', default='32768MB')
    run.add_argument('--timeout', type=int, default=900)
    verify = sub.add_parser('check')
    verify.add_argument('--reference', type=Path, required=True)
    verify.add_argument('--candidate', type=Path, required=True)
    verify.add_argument('--live-ratio', type=float, required=True)
    verify.add_argument('--rss-ratio', type=float, required=True)
    verify.add_argument('--same-interface', action='store_true')
    verify.add_argument('--json', type=Path)
    args = parser.parse_args()
    return collect(args) if args.action == 'run' else check(args)


if __name__ == '__main__':
    raise SystemExit(main())
