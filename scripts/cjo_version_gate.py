#!/usr/bin/env python3
"""Exercise the product CJO writer and reader, using upstream PackageTest mutations."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time


def run(cmd, cwd, log):
    start = time.monotonic()
    p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    log.write_bytes(p.stdout)
    return {'command': [str(x) for x in cmd], 'rc': p.returncode,
            'wall': time.monotonic() - start, 'log': str(log)}, p.stdout.decode(errors='replace')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', type=Path, required=True)
    ap.add_argument('--out', type=Path, required=True)
    ap.add_argument('--reference-compiler', type=Path, help='Official common-part CJO producer')
    ap.add_argument('--fixture-cjo', type=Path, help='Reuse identical product-written CJO across reader arms')
    args = ap.parse_args()
    compiler, out = args.compiler.resolve(), args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    fixtures = Path(__file__).resolve().parent / 'cjo_version_fixtures'
    result = {'compiler': str(compiler), 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'cases': []}
    if args.fixture_cjo:
        data = args.fixture_cjo.read_bytes()
    else:
        producer = out / 'producer'
        producer.mkdir(exist_ok=True)
        invocation, output = run([compiler, fixtures / 'vercheck.cj', '--output-type=staticlib',
                                  '-o', producer / 'libvercheck.a'], producer, out / 'producer.log')
        result['producer'] = invocation
        if invocation['rc'] != 0:
            (out / 'result.json').write_text(json.dumps(result, indent=2))
            print('INFRA producer failed; no version assertion executed')
            return 2
        data = (producer / 'vercheck.cjo').read_bytes()
    (out / 'fixture.cjo').write_bytes(data)
    root = struct.unpack_from('<I', data)[0]
    vtable = root - struct.unpack_from('<i', data, root)[0]
    offset = struct.unpack_from('<H', data, vtable + 6)[0]
    if not offset:
        raise RuntimeError('product writer omitted version')
    version = list(data[root + offset:root + offset + 3])
    writer_ok = version == [0, 1, 0]
    result['writer'] = {'version': version, 'pass': writer_ok}
    print(f"{'PASS' if writer_ok else 'FAIL'} WriterVersion observed={version}", flush=True)
    variants = {'current': (0, 1, 0), 'older_minor': (0, 0, 0), 'patch': (0, 1, 255),
                'major': (1, 1, 0), 'newer_minor': (0, 2, 0), 'missing': None}
    # Common-part CJO uses the official producer's serialized file-ID contract.
    # The candidate still generates and consumes the CHIR, and consumes this CJO.
    common = out / 'common-producer'
    common.mkdir(exist_ok=True)
    reference = (args.reference_compiler or Path(os.environ['CANGJIE_HOME']) / 'bin' / 'cjc').resolve()
    result['common_reference_sha256'] = hashlib.sha256(reference.read_bytes()).hexdigest()
    common_invocation, _ = run([reference, fixtures / 'vercheck.cj', '--experimental',
                                '--output-type=chir', '-o', common / 'unused.chir'],
                               common, common / 'producer.log')
    chir_dir = common / 'chir'
    chir_dir.mkdir(exist_ok=True)
    chir_invocation, _ = run([compiler, fixtures / 'vercheck.cj', '--emit-chir',
                              '--output-type=staticlib', '-o', chir_dir / 'vercheck.chir'],
                             chir_dir, common / 'chir.log')
    result['common_producer'] = common_invocation
    result['common_chir'] = chir_invocation
    if common_invocation['rc'] != 0 or chir_invocation['rc'] != 0:
        (out / 'result.json').write_text(json.dumps(result, indent=2))
        print('INFRA common fixture generation failed; no common version assertion executed')
        return 2
    common_data = (common / 'vercheck.cjo').read_bytes()
    result['common_cjo_sha256'] = hashlib.sha256(common_data).hexdigest()
    result['common_chir_sha256'] = hashlib.sha256((chir_dir / 'vercheck.chir').read_bytes()).hexdigest()

    def mutate(original, triplet):
        changed = bytearray(original)
        table = struct.unpack_from('<I', changed)[0]
        vt = table - struct.unpack_from('<i', changed, table)[0]
        field = table + struct.unpack_from('<H', changed, vt + 6)[0]
        if triplet is None:
            struct.pack_into('<H', changed, vt + 6, 0)
        else:
            changed[field:field + 3] = bytes(triplet)
        return changed

    tasks = []
    for name, triplet in variants.items():
        for entry in ('import', 'depinfo', 'common'):
            case = out / f'{entry}-{name}'
            case.mkdir(exist_ok=True)
            original = common_data if entry == 'common' else data
            (case / 'vercheck.cjo').write_bytes(mutate(original, triplet))
            tasks.append((entry, name, case))

    def check(task):
        entry, name, case = task
        cmd = ([compiler, fixtures / 'use.cj', '--output-type=staticlib', '-o', case / 'libuseversion.a', '--import-path', case]
               if entry == 'import' else [compiler, case / 'vercheck.cjo', '--scan-dependency'])
        if entry == 'common':
            (case / 'output').mkdir(exist_ok=True)
            cmd = [compiler, fixtures / 'specific.cj', '--experimental',
                   '--common-part-cjo', case / 'vercheck.cjo',
                   '--common-part-chir', chir_dir / 'vercheck.chir', '--output-type=staticlib',
                   '-o', case / 'output' / 'libvercheck.a']
        invocation, output = run(cmd, case, case / 'compile.log')
        accepted = name in ('current', 'older_minor', 'patch')
        # Do not turn an arbitrary compiler failure into a successful rejection.
        mismatch = "is incompatible: compiled with cjc" in output
        passed = (invocation['rc'] == 0 and not mismatch) if accepted else (
            invocation['rc'] == 1 and mismatch and 'vercheck' in output)
        if accepted and entry == 'depinfo':
            passed = passed and 'vercheck' in output
        record = dict(invocation, name=f'{entry}-{name}', expected_accept=accepted,
                      diagnostic=mismatch, **{'pass': passed})
        print(f"{'PASS' if passed else 'FAIL'} {record['name']} rc={invocation['rc']} "
              f"expected_accept={accepted} mismatch={mismatch}", flush=True)
        return record

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(tasks)) as pool:
        result['cases'] = list(pool.map(check, tasks))
    def check_cache(item):
        name, triplet = item
        case = out / f'cache-{name}'
        case.mkdir(exist_ok=True)
        source = case / 'cache.cj'
        source.write_bytes((fixtures / 'cache.cj').read_bytes())
        cmd = [compiler, 'cache.cj', '--incremental-compile', '--experimental',
               '--output-type=staticlib', '-o', 'libcacheversion.a']
        seed, _ = run(cmd, case, case / 'seed.log')
        if seed['rc'] != 0:
            return {'name': f'cache-{name}', 'pass': False, 'infra': 'seed failed', 'seed': seed}
        cjos = list((case / '.cached').glob('*.cjo'))
        if len(cjos) != 1:
            raise RuntimeError(f'expected one cache CJO, found {cjos}')
        changed = mutate(cjos[0].read_bytes(), triplet)
        cjos[0].write_bytes(changed)
        (case / 'cache-input.cjo').write_bytes(changed)
        source.write_text(source.read_text().replace('public func deleted(): Int64 { 3 }\n', '')
                          .replace('{ 1 }', '{ 2 }'))
        update, output = run(cmd, case, case / 'update.log')
        logs = '\n'.join(p.read_text() for p in (case / '.cached').glob('*.log'))
        (case / 'cache-state.log').write_text(logs)
        # This existing product log records insertion of the actual removed mangled name
        # into the set returned by LoadCachedTypeForPackage, not a test counter.
        removed = '[CollectRemovedDecl] removed mangled: _CN12cacheversion7deletedHv' in logs
        accepted = name in ('current', 'older_minor', 'patch')
        passed = (update['rc'] == 0 and 'incremental sema' in logs and removed == accepted
                  and 'is incompatible: compiled with cjc' not in output)
        record = dict(update, name=f'cache-{name}', seed=seed, removed_value=removed,
                      expected_accept=accepted, **{'pass': passed})
        print(f"{'PASS' if passed else 'FAIL'} cache-{name} rc={update['rc']} "
              f"expected_consume={accepted} removed_value={removed}", flush=True)
        return record

    with concurrent.futures.ThreadPoolExecutor(max_workers=len(variants)) as pool:
        result['cases'].extend(pool.map(check_cache, variants.items()))
    result['fixture_sha256'] = hashlib.sha256(data).hexdigest()
    result['pass'] = writer_ok and all(c['pass'] for c in result['cases'])
    (out / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    return 0 if result['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
