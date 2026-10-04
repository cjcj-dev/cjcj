#!/usr/bin/env python3
"""Compile real inputs, inspect emitted CJO declarations and LLVM definitions.

CJO offsets follow ModuleFormatSchema.cj:440-452,624. No AST model or
instrumentation is linked into the compiler. Every assertion reads its output.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import struct
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def declarations(path):
    data = path.read_bytes()
    def u32(pos): return struct.unpack_from('<I', data, pos)[0]
    def field(table, offset):
        vtable = table - struct.unpack_from('<i', data, table)[0]
        size = struct.unpack_from('<H', data, vtable)[0]
        distance = struct.unpack_from('<H', data, vtable + offset)[0] if offset < size else 0
        return table + distance if distance else None
    def pointer(table, offset):
        slot = field(table, offset)
        return slot + u32(slot) if slot is not None else None
    def string(table, offset):
        pos = pointer(table, offset)
        return data[pos + 4:pos + 4 + u32(pos)].decode() if pos is not None else ''
    if data[4:8] != b'CJOF':
        raise ValueError(f'{path}: not a CJOF flatbuffer')
    vector = pointer(u32(0), 20)
    if vector is None:
        raise ValueError(f'{path}: missing declarations vector')
    result = []
    for i in range(u32(vector)):
        slot = vector + 4 + i * 4
        table = slot + u32(slot)
        result.append(dict(identifier=string(table, 18), package=string(table, 8),
                           mangled=string(table, 28), export_id=string(table, 30),
                           raw=string(table, 32)))
    return sorted(result, key=lambda x: json.dumps(x, sort_keys=True))


def run(args, case, single):
    tag = case.stem + ('-single' if single else '')
    out = args.output / tag
    out.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ, CANGJIE_HOME=str(args.sdk), cjHeapSize='32GB')
    env['PATH'] = ':'.join(str(args.sdk / p) for p in ('bin', 'tools/bin', 'third_party/llvm/bin')) + ':' + os.environ['PATH']
    env['LD_LIBRARY_PATH'] = ':'.join(str(args.sdk / p) for p in ('runtime/lib/linux_x86_64_cjnative', 'lib/linux_x86_64_cjnative', 'tools/lib', 'third_party/llvm/lib'))
    env['CANGJIE_PATH'] = ':'.join(str(args.sdk / p) for p in ('modules/linux_x86_64_cjnative', 'third_party/flatbuffers/modules'))
    env['LIBRARY_PATH'] = str(args.sdk / 'lib/linux_x86_64_cjnative')
    cmd = [str(args.compiler), str(case), '--lto=full', '-O2', '--output-type=staticlib', '-o', str(out / 'output.bc')]
    cmd += args.compiler_option
    if single: cmd += ['--cjcj-disable-mangling-concurrency']
    identity = dict(compiler=sha(args.compiler), source=sha(case), sdk=str(args.sdk),
                    libraries={str(p.relative_to(args.sdk)): sha(p) for directory in
                               ('runtime/lib/linux_x86_64_cjnative', 'third_party/flatbuffers/modules')
                               for p in (args.sdk / directory).glob('*') if p.is_file()})
    before = subprocess.check_output(['uptime'], text=True)
    start = time.monotonic()
    with (out / 'compile.log').open('w') as log:
        try: rc = subprocess.run(cmd, env=env, cwd=out, stdout=log, stderr=subprocess.STDOUT, timeout=180).returncode
        except subprocess.TimeoutExpired: rc = 124
    result = dict(tag=tag, command=cmd, identity=identity, rc=rc, wall=time.monotonic()-start,
                  affinity=sorted(os.sched_getaffinity(0)), uptime_before=before,
                  uptime_after=subprocess.check_output(['uptime'], text=True), assertions={})
    if rc == 0 and (out / 'output.bc').is_file():
        with (out / 'disassemble.log').open('w') as log:
            dis = subprocess.run([str(args.sdk/'third_party/llvm/bin/llvm-dis'), str(out/'output.bc'), '-o', str(out/'output.ll')], env=env, stdout=log, stderr=subprocess.STDOUT).returncode
        result['disassemble_rc'] = dis
        if dis == 0:
            result['symbols'] = sorted(re.findall(r'^define\b.*?@("[^"]+"|[^ (]+)\(', (out/'output.ll').read_text(), re.MULTILINE))
        result['decls'] = [d for cjo in sorted(out.glob('*.cjo')) for d in declarations(cjo)]
        result['products'] = {p.name: sha(p) for p in out.iterdir() if p.suffix in ('.cjo', '.bc')}
        checks = result['assertions']
        checks['symbols_observed'] = bool(result.get('symbols'))
        checks['declarations_observed'] = bool(result['decls'])
        if args.reference:
            ref = json.loads((args.reference/tag/'result.json').read_text())
            if args.reference_is_baseline and tag == '261_generic_extend_key':
                # BaseMangler.cpp:1419-1421 keys extends by original Ty.String().
                # The removed MangleType.String() returned only "Box", so the
                # second specialization incorrectly shared the first bucket.
                changed = []
                for decl in ref['decls']:
                    if decl['identifier'] == '' and decl['raw'] == '3Box<6String><:X':
                        old = decl['export_id']
                        suffix = 'K0_IRNat6StringEE'
                        if not old.endswith(suffix):
                            raise ValueError('baseline extend-index witness changed')
                        decl['export_id'] = old[:-len(suffix)] + 'K_IRNat6StringEE'
                        changed.append(dict(before=old, after=decl['export_id']))
                if len(changed) != 1:
                    raise ValueError('expected exactly one measured baseline extend-index delta')
                result['expected_delta'] = changed
            checks['symbols_equal'] = result.get('symbols') == ref.get('symbols')
            # Compare fields independently so an unrelated assertion cannot mask
            # execution of the raw-name or export-id assertion.
            for key in ('raw', 'export_id', 'mangled'):
                normalize = lambda values: sorted((d['package'],d['identifier'],d[key]) for d in values)
                checks[key+'_equal'] = normalize(result['decls']) == normalize(ref['decls'])
        for key, passed in checks.items():
            print(f'ASSERT {tag} {key}={passed}', flush=True)
    result['passed'] = rc == 0 and bool(result['assertions']) and all(result['assertions'].values())
    (out/'result.json').write_text(json.dumps(result, indent=2)+'\n')
    if result['passed']:
        for p in out.iterdir():
            if p.suffix in ('.cjo','.bc','.ll','.o','.a'): p.unlink()
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for key in ('compiler','sdk','inputs','output'): p.add_argument('--'+key, type=Path, required=True)
    p.add_argument('--reference', type=Path)
    p.add_argument('--reference-is-baseline', action='store_true')
    p.add_argument('--parallelism', type=int, choices=range(1,5), default=4)
    p.add_argument('--compiler-option', action='append', default=[])
    a = p.parse_args()
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    cases = [(src,False) for src in sorted(a.inputs.glob('*.cj'))]
    cases += [(a.inputs/name,True) for name in ('parallel.cj','ordinary.cj')]
    with concurrent.futures.ThreadPoolExecutor(max_workers=a.parallelism) as pool:
        results = list(pool.map(lambda case: run(a,*case),cases))
    by_tag = {r['tag']:r for r in results}
    single_equal = {name: by_tag[name].get('symbols') == by_tag[name+'-single'].get('symbols')
                    and by_tag[name].get('decls') == by_tag[name+'-single'].get('decls')
                    for name in ('parallel','ordinary')}
    (a.output/'summary.json').write_text(json.dumps(dict(results=results,single_equal=single_equal),indent=2)+'\n')
    return int(not all(r['passed'] for r in results) or not all(single_equal.values()))


if __name__ == '__main__':
    raise SystemExit(main())
