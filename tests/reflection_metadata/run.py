#!/usr/bin/env python3
"""Compile a real fixture and check emitted metadata plus retained ClassDef state.

The inspector links the existing product archives; it does not compile copies of
compiler sources. Both inspector and command-line compiler must match --tree.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--tree', type=Path, required=True)
p.add_argument('--sdk', type=Path, required=True)
p.add_argument('--compiler', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
a = p.parse_args()
a.tree, a.sdk, a.compiler, a.output = [v.resolve() for v in (a.tree, a.sdk, a.compiler, a.output)]
a.output.mkdir(parents=True, exist_ok=True)
source = Path(__file__).resolve().parent
os.environ.update(CANGJIE_HOME=str(a.sdk), LD_LIBRARY_PATH=':'.join(
    str(a.sdk / part) for part in ('runtime/lib/linux_x86_64_cjnative',
    'lib/linux_x86_64_cjnative', 'third_party/llvm/lib', 'tools/lib')) +
    ':/usr/lib/x86_64-linux-gnu', cjHeapSize='32GB')
record = {'commands': [], 'checks': {}, 'uptime_before': subprocess.check_output(['uptime'], text=True),
          'affinity': sorted(os.sched_getaffinity(0)), 'hashes': {}}

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def run(cmd, name):
    start = time.monotonic()
    with (a.output / (name + '.log')).open('w') as f:
        rc = subprocess.run([str(x) for x in cmd], cwd=a.output, stdout=f,
                            stderr=subprocess.STDOUT, timeout=600).returncode
    record['commands'].append({'name': name, 'command': [str(x) for x in cmd],
                               'rc': rc, 'wall': time.monotonic() - start})
    print(name, 'rc=' + str(rc), flush=True)
    return rc

def check(name, ok, value):
    record['checks'][name] = {'pass': bool(ok), 'observed': value}
    print(('PASS ' if ok else 'FAIL ') + name + ' ' + json.dumps(value), flush=True)

def metadata(bitcodes, prefix):
    result = {}
    for i, bc in enumerate(bitcodes):
        ll = a.output / f'{prefix}-{i}.ll'
        if run([a.sdk / 'third_party/llvm/bin/llvm-dis', bc, '-o', ll], f'{prefix}-dis-{i}'):
            raise RuntimeError('llvm-dis failed')
        text = ll.read_text()
        nodes = dict(re.findall(r'^!(\d+) = (.*)$', text, re.M))
        for name, suffix, node in re.findall(
                r'^@"reflection_attrs:([^".]+)\.(ti|tt)" = .*?!Reflection !(\d+)', text, re.M):
            refs = re.findall(r'!(\d+)', nodes[node])
            attrs = re.findall(r'!"([^"]*)"', nodes[refs[-1]])
            if name in result and result[name] != attrs:
                raise RuntimeError('conflicting class metadata: ' + name)
            result[name] = attrs
    return result

try:
    archives = sorted((a.tree / 'target/release').glob('*@cjcj/*.a'))
    if not archives:
        raise RuntimeError('product archives missing')
    for path in [a.compiler, a.sdk / 'bin/cjc', *archives,
                 *sorted((a.sdk / 'runtime/lib/linux_x86_64_cjnative').glob('*.so')),
                 a.sdk / 'lib/linux_x86_64_cjnative/libcangjie-std-core.a',
                 a.sdk / 'third_party/llvm/lib/libLLVM-15.so']:
        record['hashes'][str(path)] = sha(path)
    inspector = a.output / 'inspect'
    cmd = [a.sdk / 'bin/cjc', source / 'inspect.cj', '-O0', '-o', inspector]
    for directory in sorted((a.tree / 'target/release').glob('*@cjcj')):
        cmd += ['--import-path', directory]
    cmd += ['--link-options', '--start-group ' + ' '.join(str(x) for x in archives) +
            ' --end-group ' + str(a.tree / 'runtime_shim/cjselfhost_llvmshim.o') +
            ' ' + str(a.sdk / 'third_party/llvm/lib/libLLVM-15.so') + ' -lstdc++']
    if run(cmd, 'inspector-build'):
        raise RuntimeError('inspector build failed')
    record['hashes'][str(inspector)] = sha(inspector)
    inspector_rc = run([inspector, a.sdk, source / 'classes.cj', a.output / 'fixture.bc'], 'inspector')
    log = (a.output / 'inspector.log').read_text()
    # A mutation failure is an assertion result, not a reason to skip metadata checks.
    if inspector_rc not in (0, 1):
        raise RuntimeError('inspector did not finish codegen')
    check('original_attributes_unchanged', inspector_rc == 0 and
          'ASSERT original_attributes_unchanged=true' in log, log.splitlines())
    temps = a.output / 'temps'
    temps.mkdir(exist_ok=True)
    if run([a.compiler, source / 'classes.cj', '--output-type=staticlib', '--save-temps', temps,
            '--dump-chir', '--dump-ir', '-O0', '-o', a.output / 'fixture.a'], 'stage1-fixture'):
        raise RuntimeError('stage1 fixture compilation failed')
    for prefix, bcs in [('inspector', [a.output / 'fixture.bc']),
                        ('stage1', sorted(x for x in temps.glob('*.bc') if not x.name.endswith('.opt.bc')))]:
        attrs = metadata(bcs, prefix)
        check(prefix + '_presence', set(attrs) == {'ImplicitOpen', 'GenericOpen', 'ExplicitOpen', 'Closed', 'Contract'}, attrs)
        check(prefix + '_abstract_open', all('abstract' in attrs.get(n, []) and 'open' in attrs.get(n, [])
              for n in ('ImplicitOpen', 'GenericOpen')), {n: attrs.get(n) for n in ('ImplicitOpen', 'GenericOpen')})
        check(prefix + '_explicit_open', 'open' in attrs.get('ExplicitOpen', []), attrs.get('ExplicitOpen'))
        check(prefix + '_closed', 'Closed' in attrs and 'open' not in attrs['Closed'], attrs.get('Closed'))
        check(prefix + '_interface_open', 'open' in attrs.get('Contract', []), attrs.get('Contract'))
    record['rc'] = int(not all(v['pass'] for v in record['checks'].values()))
except (RuntimeError, OSError, subprocess.TimeoutExpired) as exc:
    record['error'] = str(exc)
    record['rc'] = 2
finally:
    record['uptime_after'] = subprocess.check_output(['uptime'], text=True)
    (a.output / 'result.json').write_text(json.dumps(record, indent=2) + '\n')
raise SystemExit(record['rc'])
