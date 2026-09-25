#!/usr/bin/env python3
"""Compare complete schema-decoded CHIR, normalizing only b77d9fda cast tags.

The old NumericCastBase(NA) representation also described class casts. The new
StaticCast uses an Expression table. Flatten precisely these two representations;
all other fields, vector order, annotations and overflow strategies remain exact.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

NUMERIC = {'INT8', 'INT16', 'INT32', 'INT64', 'INT_NATIVE', 'UINT8', 'UINT16',
           'UINT32', 'UINT64', 'UINT_NATIVE', 'FLOAT16', 'FLOAT32', 'FLOAT64'}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def base_field(obj, field):
    while field not in obj:
        obj = obj['base']
    return obj[field]


def canonicalize(package):
    changes = []
    kinds, expressions = package['exprs_type'], package['exprs']
    assert len(kinds) == len(expressions)
    for index, (kind, expression) in enumerate(zip(kinds, expressions)):
        if kind == 'NumericCastBase' and expression['base']['kind'] == 'NumericCast':
            if expression['overflowStrategy'] == 'NA':
                assert set(expression) == {'base', 'overflowStrategy'}, expression.keys()
                kinds[index] = 'Expression'
                expressions[index] = expression['base']
                expressions[index]['kind'] = 'LegacyTypeCastNA'
                changes.append({'index': index, 'from': 'NumericCastBase/NA/NumericCast'})
        elif kind == 'Expression' and expression['kind'] == 'StaticCast':
            source = package['values'][expression['operands'][0] - 1]
            source_id = base_field(source, 'type')
            target_id = expression['resultTy']
            assert source_id and target_id, 'cast has no source/target type'
            source_kind = base_field(package['types'][source_id - 1], 'kind')
            target_kind = base_field(package['types'][target_id - 1], 'kind')
            # A numeric-to-numeric producer routed to ClassStaticCast is a bug,
            # not an allowed tag migration (Utils.cpp:501 at b77d9fda).
            assert not (source_kind in NUMERIC and target_kind in NUMERIC), (index, source_kind, target_kind)
            expression['kind'] = 'LegacyTypeCastNA'
            changes.append({'index': index, 'from': 'Expression/StaticCast'})
    encoded = json.dumps(package, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
    return encoded, changes


def compile_case(compiler, source, output, imports, schema, flatc, jobs):
    output.mkdir(parents=True, exist_ok=True)
    command = [str(compiler)]
    command += ['-p', str(source)] if source.is_dir() else [str(source)]
    command += ['--emit-chir=opt', '--output-type=staticlib', '-O2', '--jobs', str(jobs),
                '-o', str(output / 'output.chir')]
    for directory in imports:
        command += ['--import-path', str(directory)]
    before = subprocess.check_output(['uptime'], text=True).strip()
    start = time.monotonic()
    with (output / 'compile.log').open('w') as log:
        run = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=3600)
    result = {'artifact_dir': str(output), 'command': command, 'rc': run.returncode, 'wall': time.monotonic() - start,
              'uptime_before': before, 'uptime_after': subprocess.check_output(['uptime'], text=True).strip()}
    if run.returncode:
        return result
    artifacts = list(output.glob('*.chir'))
    assert len(artifacts) == 1, artifacts
    artifact = artifacts[0]
    result['raw_sha256'] = sha(artifact)
    decode = subprocess.run([str(flatc), '--json', '--strict-json', '--defaults-json', '--raw-binary', '--no-warnings',
                             '-o', str(output), str(schema), '--', str(artifact)],
                            capture_output=True, text=True)
    (output / 'decode.log').write_text(decode.stdout + decode.stderr)
    result['decode_rc'] = decode.returncode
    if decode.returncode:
        return result
    decoded = artifact.with_suffix('.json')
    data = json.loads(decoded.read_text())
    canonical, changes = canonicalize(data)
    (output / 'canonical.json').write_bytes(canonical)
    result['canonical_sha256'] = hashlib.sha256(canonical).hexdigest()
    result['tag_normalizations'] = changes
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', type=Path, required=True)
    p.add_argument('--candidate', type=Path, required=True)
    p.add_argument('--schema', type=Path, required=True)
    p.add_argument('--flatc', type=Path, required=True)
    p.add_argument('--source-root', type=Path, required=True)
    p.add_argument('--imports-root', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--jobs', type=int, default=os.cpu_count())
    p.add_argument('--fixture-only', action='store_true')
    p.add_argument('--workers', type=int, default=8, help='independent compiler processes')
    p.add_argument('--indices', help='comma separated original input indices; other results remain recorded')
    p.add_argument('--baseline-results', type=Path, help='reuse successful immutable baseline outputs with matching compiler SHA')
    args = p.parse_args()
    imports = [args.imports_root] + sorted(args.imports_root.glob('*@cjcj'))
    sources = [] if args.fixture_only else [root / 'src' for root in sorted((args.source_root / 'packages').iterdir())
                                           if (root / 'cjpm.toml').exists() and root.name != 'cjc']
    fixtures = [Path(__file__).with_name(name + '.cj') for name in ('class_cast', 'numeric_cast', 'control')]
    args.out.mkdir(parents=True, exist_ok=True)
    manifest = {'compilers': {name: {'path': str(exe), 'sha256': sha(exe)} for name, exe in
                             [('baseline', args.baseline), ('candidate', args.candidate)]},
                'schema_sha256': sha(args.schema), 'flatc_sha256': sha(args.flatc),
                'affinity': sorted(os.sched_getaffinity(0)), 'jobs_per_serialization': args.jobs,
                'parallel_compilers': args.workers, 'library_sources': list(map(str, sources)), 'cases': []}
    cases = [{'source': str(source)} for source in fixtures + sources]
    if (args.out / 'result.json').exists():
        saved = json.loads((args.out / 'result.json').read_text())
        assert saved['compilers'] == manifest['compilers'], 'resume compiler identity mismatch'
        cases = saved['cases']
    manifest['cases'] = cases
    selected = set(map(int, args.indices.split(','))) if args.indices else set(range(len(cases)))
    prior = None
    if args.baseline_results:
        prior = json.loads((args.baseline_results / 'result.json').read_text())
        assert prior['compilers']['baseline']['sha256'] == sha(args.baseline), 'baseline identity mismatch'
        assert prior['schema_sha256'] == sha(args.schema), 'schema identity mismatch'
        assert prior['jobs_per_serialization'] == args.jobs, 'baseline recipe mismatch'
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        pending = {}
        for index, source in enumerate(fixtures + sources):
            if index not in selected:
                continue
            for name, exe in [('baseline', args.baseline), ('candidate', args.candidate)]:
                if name == 'baseline' and prior:
                    previous = prior['cases'][index]
                    assert previous['source'] == str(source), 'baseline source mismatch'
                    result = previous.get('baseline', {})
                    if result.get('rc') == 0 and result.get('canonical_sha256'):
                        result['artifact_dir'] = str(args.baseline_results / str(index) / 'baseline')
                        assert sha(Path(result['artifact_dir']) / 'canonical.json') == result['canonical_sha256']
                        cases[index][name] = result
                        continue
                future = pool.submit(compile_case, exe, source, args.out / str(index) / name,
                                     imports, args.schema, args.flatc, args.jobs)
                pending[future] = (index, name)
        for future in concurrent.futures.as_completed(pending):
            index, name = pending[future]
            case = cases[index]
            try:
                case[name] = future.result()
            except Exception as error:
                case[name] = {'rc': -1, 'error': str(error)}
            if 'baseline' in case and 'candidate' in case:
                case['same_normalized_bytes'] = (case['baseline']['rc'] == case['candidate']['rc'] == 0
                    and case['baseline'].get('canonical_sha256') is not None
                    and case['baseline'].get('canonical_sha256') == case['candidate'].get('canonical_sha256'))
                print(f"CHIR_BYTES {case['source']} same={case['same_normalized_bytes']} rc={case['baseline']['rc']}/{case['candidate']['rc']}", flush=True)
            (args.out / 'result.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return 0 if all(case.get('same_normalized_bytes', False) for case in manifest['cases']) else 1


if __name__ == '__main__':
    raise SystemExit(main())
