#!/usr/bin/env python3
"""Exercise the workflow collector on a real aborted runtime process core.

Run on Linux with PyYAML and gdb. --source contains a copied cj_gc_unit plus
its same-build runtime/boundscheck pair under lib/. No host sysctl is changed.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import difflib
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import yaml

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--source', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--core', type=Path, help='Optional real kernel core from the same ELF/SO build')
p.add_argument('--repo', type=Path, default=Path(__file__).resolve().parents[3])
a = p.parse_args()
a.source = a.source.resolve()
a.output = a.output.resolve()
a.output.mkdir(parents=True, exist_ok=True)
workflow = yaml.safe_load((a.repo / '.github/workflows/platform-matrix.yml').read_text())
steps = workflow['jobs']['colour-runtime']['steps']
collector = next(s for s in steps if s.get('name') == 'Collect runtime core backtraces')
upload = next(s for s in steps if s.get('name') == 'Upload runtime gate diagnostics')
assert collector['if'] == "${{ failure() && (steps.runtime-build.outcome == 'failure' || steps.runtime-language-gate.outcome == 'failure') }}"
assert "${{ (steps.runtime-build.outcome == 'failure' || steps.runtime-language-gate.outcome == 'failure') && '.platform-ci/runtime-gate-diagnostics/' || '' }}" in upload['with']['path'].splitlines()
assert upload['if'] == 'always()'
assert steps.index(collector) < steps.index(upload)
assert next(s for s in steps if s.get('id') == 'runtime-build')['run'].rstrip().endswith(
    'npx --yes zx@8 ci/platform_matrix/build_runtime.mjs')
name = 'RelocateWorkers.ProductSerialEntryRegistersWorkerAndClosesGeneration'
env = {**os.environ, 'LD_LIBRARY_PATH': str(a.source / 'lib'),
       'GC_UNIT_FILTER': name, 'GC_UNIT_ABORT_BEFORE': name, 'GC_UNIT_OTHER_VM_CHILD': name}
env.pop('GC_UNIT_LIST_TESTS', None)
elf = a.source / 'cj_gc_unit'
started = time.monotonic()
identity = {}
for file in [elf, *sorted((a.source / 'lib').glob('*.so'))]:
    identity[str(file)] = hashlib.sha256(file.read_bytes()).hexdigest()
(a.output / 'identity.json').write_text(json.dumps(identity, indent=2))
subprocess.run(['uptime'], stdout=(a.output / 'uptime-before.txt').open('w'), check=True)
# The existing abort hook must really execute, including the selected child name.
failed = subprocess.run([str(elf)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
(a.output / 'gate_run.log').write_bytes(failed.stdout)
assert failed.returncode != 0 and name.encode() in failed.stdout, failed.stdout
(a.output / 'gate.rc').write_text(str(failed.returncode) + '\n')
# Generate a genuine process core at the injected signal without modifying the
# shared kkk2 host's apport core_pattern. GHA separately exercises kernel dumping.
seed = a.output / 'seed.core'
if a.core:
    shutil.copy2(a.core, seed)
else:
    r = subprocess.run(['gdb', '-nx', '-batch', '-ex', 'set pagination off',
                        '-ex', 'handle SIGSEGV stop print nopass', '-ex', 'run',
                        '-ex', f'generate-core-file {seed}', '-ex', 'kill', str(elf)],
                       env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
    (a.output / 'core-generation.log').write_bytes(r.stdout)
    assert r.returncode == 0 and seed.is_file(), r.stdout


def arm(label, cut=False, with_core=True):
    work = a.output / label
    work.mkdir()
    shutil.copytree(a.repo / 'ci/platform_matrix', work / 'ci/platform_matrix')
    # The collector sees an actual source tree; no helper feeds it an ELF path.
    shutil.copytree(a.source, work / 'runtime-source/runtime')
    diag = work / '.platform-ci/runtime-gate-diagnostics'
    (diag / 'cores').mkdir(parents=True)
    if with_core:
        shutil.copy2(seed, diag / ('cores/core.' + str(elf).replace('/', '!') + '.123.456'))
    workflow_text = (a.repo / '.github/workflows/platform-matrix.yml').read_text()
    mutated = workflow_text.replace('run: python3 ci/platform_matrix/collect_runtime_cores.py',
                                    "run: ':'") if cut else workflow_text
    workflow_path = work / '.github/workflows/platform-matrix.yml'
    workflow_path.parent.mkdir(parents=True)
    workflow_path.write_text(mutated)
    if cut:
        (a.output / 'cut.diff').write_text(''.join(difflib.unified_diff(
            workflow_text.splitlines(keepends=True), mutated.splitlines(keepends=True),
            fromfile='a/.github/workflows/platform-matrix.yml',
            tofile='b/.github/workflows/platform-matrix.yml')))
    selected = next(s for s in yaml.safe_load(workflow_path.read_text())['jobs']['colour-runtime']['steps']
                    if s.get('name') == 'Collect runtime core backtraces')
    command = selected['run']
    result = subprocess.run(['bash', '-e', '-c', command], cwd=work,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    (work / 'collector.log').write_bytes(result.stdout)
    traces = list(diag.glob('*.bt.txt'))
    # All target assertions are observed independently; no earlier existence
    # assertion masks whether symbolized results reached the actual checks.
    text = '\n'.join(f.read_text(errors='replace') for f in traces)
    assertions = {
        'collector_rc': result.returncode == 0,
        'bt_exists': bool(traces) == with_core,
        'symbolized_abort': ('MapleRuntime::GcUnit::RunAll' in text) if with_core else True,
        'failed_case_matches': (name in text) if with_core else True,
        'registers': ('rip' in text) if with_core else True,
        'shared_libraries': ('libcangjie-runtime.so' in text) if with_core else True,
        'same_build_products': (diag / 'products/lib/libcangjie-runtime.so').exists(),
    }
    if not with_core:
        assertions['no_core_reason'] = 'NO_CORE:' in (diag / 'summary.txt').read_text()
    artifacts = {str(file.relative_to(work)): hashlib.sha256(file.read_bytes()).hexdigest()
                 for file in [workflow_path, work / 'ci/platform_matrix/collect_runtime_cores.py',
                              work / 'runtime-source/runtime/cj_gc_unit',
                              *sorted((work / 'runtime-source/runtime/lib').glob('*.so'))]}
    report = {'assertions': assertions, 'rc': int(not all(assertions.values())), 'sha256': artifacts}
    (work / 'assertions.json').write_text(json.dumps(report, indent=2))
    return label, report


with ThreadPoolExecutor(max_workers=4) as pool:
    results = dict(pool.map(lambda spec: arm(*spec), [
        ('green', False, True), ('cut', True, True),
        ('restored', False, True), ('no-core', False, False)]))
(a.output / 'results.json').write_text(json.dumps(results, indent=2))
print(json.dumps(results, indent=2))
assert results['green']['rc'] == results['restored']['rc'] == results['no-core']['rc'] == 0
assert results['green']['sha256'] == results['restored']['sha256']
for file, digest in results['green']['sha256'].items():
    assert (digest != results['cut']['sha256'][file]) == (file == '.github/workflows/platform-matrix.yml')
assert results['cut']['rc'] == 1
assert not results['cut']['assertions']['bt_exists']
subprocess.run(['uptime'], stdout=(a.output / 'uptime-after.txt').open('w'), check=True)
print(f'wall={time.monotonic() - started:.2f}s arms=4 real_abort_rc={failed.returncode}')
