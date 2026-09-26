#!/usr/bin/env python3
"""Execute AST workflow shell steps with real tools (Linux x86_64 only).

Requires PyYAML, clang, cmake, ninja, network access, and an empty work directory.
No command shims: bash xtrace records the actual install and SDK consumer args.
Run on a build worker, not on a shared SDK installation. --source optionally
copies an already fetched compiler tree; --seed-home copies private cjv inputs.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import time

import yaml

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--repo', type=Path, required=True)
p.add_argument('--work', type=Path, required=True)
p.add_argument('--source', type=Path)
p.add_argument('--seed-home', type=Path)
a = p.parse_args()
repo, work = a.repo.resolve(), a.work.resolve()
work.mkdir(parents=True, exist_ok=False)
shutil.copytree(repo / 'ci', work / 'ci')
workflow = repo / '.github/workflows/build-ast-support.yml'
shutil.copyfile(workflow, work / 'workflow.yml')
steps = yaml.safe_load(workflow.read_text())['jobs']['build']['steps']
expected = dict(line.split('=', 1) for line in (repo / 'ci/host_sdk_pin.env').read_text().splitlines() if '=' in line)['CJCJ_TOOLCHAIN']
env = {k: v for k, v in os.environ.items() if k not in ('CJCJ_TOOLCHAIN', 'AST_FLATBUFFERS_SDK')}
env.update(GITHUB_ENV=str(work / 'github.env'), RUNNER_TEMP=str(work / 'temp'), PS4='+ ')
Path(env['GITHUB_ENV']).touch()
(work / 'temp').mkdir()
if a.seed_home:
    subprocess.run(['cp', '-aL', str(a.seed_home), str(work / 'temp/ast-nightly-home')], check=True)
if a.source:
    subprocess.run(['cp', '-aL', str(a.source), str(work / 'compiler')], check=True)

result = {'expected': expected, 'steps': [], 'assertions': [], 'started': time.time()}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

result['inputs'] = {name: digest(repo / name) for name in (
    '.github/workflows/build-ast-support.yml', 'ci/build_ast_support.sh',
    'ci/host_sdk_pin.env', 'ci/test_ast_host_workflow.py')}

def save(rc):
    result['rc'] = rc
    result['wall'] = time.time() - result['started']
    (work / 'result.json').write_text(json.dumps(result, indent=2) + '\n')

wanted = {'Load existing source pins', 'Load host toolchain pin',
          'Fetch official FlatBuffers SDK input', 'Build AST support and SDK inputs'}
if not a.source:
    wanted.add('Fetch pinned sources')
for step in steps:
    if step.get('name') not in wanted:
        continue
    name = step['name']
    script = step['run'].replace('${{ matrix.platform }}', 'linux_x86_64')
    if '${{' in script:
        raise ValueError('Unexpanded GitHub expression: ' + script)
    index = len(result['steps'])
    (work / f'{index}.sh').write_text(script)
    start = time.time()
    with (work / f'{index}.log').open('w') as log:
        rc = subprocess.run(['bash', '--noprofile', '--norc', '-exo', 'pipefail', str(work / f'{index}.sh')], cwd=work, env=env, stdout=log, stderr=subprocess.STDOUT).returncode
    result['steps'].append({'name': name, 'rc': rc, 'wall': time.time() - start, 'log': f'{index}.log'})
    print(f'STEP {name} rc={rc}', flush=True)
    if rc:
        save(2)  # Infrastructure/build failure is not a red assertion arm.
        raise SystemExit(2)
    for line in Path(env['GITHUB_ENV']).read_text().splitlines():
        if line and not line.startswith('#'):
            key, value = line.split('=', 1)
            env[key] = value

# Read only actual bash trace records, not command source text.
traces = {}
for step in result['steps']:
    traces[step['name']] = [shlex.split(line[2:]) for line in (work / step['log']).read_text().splitlines() if line.startswith('+ ')]
install = [cmd for cmd in traces['Fetch official FlatBuffers SDK input'] if len(cmd) >= 3 and Path(cmd[0]).name == 'cjv' and cmd[1] == 'install']
build = [cmd for cmd in traces['Build AST support and SDK inputs'] if cmd[:2] == ['bash', 'ci/build_ast_support.sh']]
result['install_argv'], result['build_argv'] = install, build

def check(name, actual, expected_value):
    ok = actual == expected_value
    result['assertions'].append({'name': name, 'actual': actual, 'expected': expected_value, 'pass': ok})
    print(f'ASSERT {name} {"PASS" if ok else "FAIL"} actual={actual!r} expected={expected_value!r}', flush=True)

check('loaded-host-pin', env.get('CJCJ_TOOLCHAIN'), expected)
check('installed-host-pin', [cmd[2:] for cmd in install], [[expected]])
check('consumed-host-sdk', [cmd[5:] for cmd in build], [[str(work / 'temp/ast-nightly-home/.cjv/toolchains' / expected)]])

# Assert on the delivered bytes too: build_ast_support.sh must have copied the
# actual selected SDK's flatbuffers payload, not merely printed its path.
def manifest(root):
    return {str(f.relative_to(root)): digest(f) for f in sorted(root.rglob('*')) if f.is_file()}

expected_root = work / 'temp/ast-nightly-home/.cjv/toolchains' / expected / 'third_party/flatbuffers'
actual_manifest = manifest(work / 'ast-artifact/third_party/flatbuffers')
expected_manifest = manifest(expected_root)
result['artifact_manifest'] = actual_manifest
result['expected_sdk_manifest'] = expected_manifest
check('flatbuffers-payload-nonempty', bool(actual_manifest) and bool(expected_manifest), True)
check('flatbuffers-payload-host-bytes', actual_manifest, expected_manifest)
result['archive_sha256'] = digest(work / 'ast-artifact/libcangjie-ast-support.a')
rc = 0 if all(x['pass'] for x in result['assertions']) else 1
save(rc)
raise SystemExit(rc)
