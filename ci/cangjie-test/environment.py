#!/usr/bin/env python3
"""Prepare a private SDK and record the upstream test prerequisites; never wrap tools."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

TOOLS = {'cjpm': 'tools/bin/cjpm', 'cjfmt': 'tools/bin/cjfmt',
         'cjlint': 'tools/bin/cjlint', 'cjcov': 'tools/bin/cjcov',
         'cjdb': 'tools/bin/cjdb', 'LSPServer': 'tools/bin/LSPServer',
         'cjcompat': 'tools/bin/cjcompat', 'hle': 'tools/bin/hle',
         'cjtrace-recover': 'tools/bin/cjtrace-recover'}
# #521 owns replacement of these managed tools. Readiness is not compiler identity.
COLOURED_TOOL_DEBT = set(TOOLS) - {'cjdb'}


def sha(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
    return value.hexdigest()


def inventory(root):
    return {str(p.relative_to(root)): sha(p) for p in sorted(root.rglob('*')) if p.is_file()}


def load_environment(sdk):
    raw = subprocess.check_output(['bash', '-c', 'source "$1/envsetup.sh" >&2 && env -0',
                                   'test-environment', str(sdk)])
    return dict(item.decode().split('=', 1) for item in raw.split(b'\0') if item)


def apply_environment(sdk, env, manifest):
    if manifest['sdk'] != str(sdk):
        raise ValueError('environment manifest SDK mismatch')
    # Verify recorded inputs before consuming the environment, including SDK LSP modules.
    for root, files in manifest['artifacts'].items():
        for rel, expected in files.items():
            if sha(Path(root) / rel) != expected:
                raise ValueError('environment artifact changed: ' + str(Path(root) / rel))
    env['LD_LIBRARY_PATH'] = str(sdk / 'third_party/llvm/lib') + ':' + env.get('LD_LIBRARY_PATH', '')
    for key, value in manifest['variables'].items():
        env[key] = value
    if env.get('JAVA_HOME'):
        env['PATH'] = env['JAVA_HOME'] + '/bin:' + env['PATH']
    return env


def probe(name, sdk, env, output, arm):
    path = sdk / TOOLS[name]
    record = {'path': str(path), 'sha256': sha(path) if path.is_file() else None}
    if not path.is_file():
        return name, dict(record, ready=False, reason='executable missing', rc=None)
    debug_env = dict(env, LD_DEBUG='libs')
    command = [str(path), '--version']
    if name in ('cjdb', 'hle', 'cjcompat', 'cjtrace-recover'):
        command[-1] = '--help'
    with (output / (name + '.log')).open('w') as stream:
        try:
            rc = subprocess.run(command, env=debug_env, stdout=stream, stderr=subprocess.STDOUT,
                                timeout=15, check=False).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    dynamic = subprocess.run(['readelf', '-d', str(path)], capture_output=True, text=True, check=False)
    (output / (name + '.dynamic.txt')).write_text(dynamic.stdout + dynamic.stderr)
    reason = 'probe completed' if rc == 0 else 'probe failed (see log); not semantic acceptance'
    if arm == 'bootstrap' and name in COLOURED_TOOL_DEBT:
        reason = 'cjcj#521: managed tool producer not qualified for coloured runtime'
    return name, dict(record, ready=rc == 0 and not (arm == 'bootstrap' and name in COLOURED_TOOL_DEBT),
                      reason=reason, rc=rc, log=str(output / (name + '.log')))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('sdk', type=Path, help='new private SDK directory')
    parser.add_argument('output', type=Path, help='new evidence directory')
    parser.add_argument('--arm', choices=('official', 'bootstrap'), required=True)
    parser.add_argument('--jdk', type=Path)
    parser.add_argument('--stdx', type=Path, help='arm-specific compiled stdx; never borrow official stdx for bootstrap')
    args = parser.parse_args()
    sdk, output = args.sdk.resolve(), args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    shutil.copytree(args.source, sdk, symlinks=True)
    # Framework README.md:83-95: private SDK modules + private execution-input config.
    modules = sdk / 'tools/bin/modules'
    if modules.exists():
        shutil.rmtree(modules)
    shutil.copytree(sdk / 'modules', modules)
    variables, artifacts, readiness = {}, {}, {}
    for name, root, key, required in (
            ('JDK', args.jdk, 'JAVA_HOME', 'bin/javac'),
            ('stdx', args.stdx, 'CANGJIE_STDX_PATH', None)):
        ready = bool(root and root.is_dir() and (not required or (root / required).is_file()))
        readiness[name] = {'ready': ready, 'reason': 'provided' if ready else 'dependency not supplied; tool not ready'}
        if ready:
            variables[key] = str(root.resolve())
            artifacts[str(root.resolve())] = inventory(root)
    if readiness['JDK']['ready']:
        probe_source = output / 'Prerequisite.java'
        probe_source.write_text('class Prerequisite { public static void main(String[] a) { System.out.println("JDK_READY"); } }\n')
        jdk = Path(variables['JAVA_HOME'])
        with (output / 'jdk.log').open('w') as stream:
            compiled = subprocess.run([str(jdk / 'bin/javac'), str(probe_source)], stdout=stream, stderr=subprocess.STDOUT)
            executed = subprocess.run([str(jdk / 'bin/java'), '-cp', str(output), 'Prerequisite'],
                                      stdout=stream, stderr=subprocess.STDOUT) if compiled.returncode == 0 else None
        readiness['JDK'].update(ready=compiled.returncode == 0 and executed is not None and executed.returncode == 0,
                                compile_rc=compiled.returncode, run_rc=executed.returncode if executed else None)
        (output / 'Prerequisite.class').unlink(missing_ok=True)
    artifacts[str(modules)] = inventory(modules)
    lldb = sdk / 'third_party/llvm/lib/liblldb.so.15'
    artifacts[str(lldb.parent)] = {lldb.name: sha(lldb)} if lldb.is_file() else {}
    readiness['liblldb'] = {'ready': lldb.is_file(), 'reason': str(lldb)}
    manifest = {'sdk': str(sdk), 'source': str(args.source.resolve()), 'arm': args.arm,
                'recipe_sha256': sha(Path(__file__)), 'variables': variables,
                'artifacts': artifacts, 'readiness': readiness}
    env = apply_environment(sdk, load_environment(sdk), manifest)
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(TOOLS)) as pool:
        futures = [pool.submit(probe, name, sdk, env, output, args.arm) for name in TOOLS]
        manifest['tools'] = dict(f.result() for f in futures)
    (output / 'environment.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(json.dumps({'environment': str(output / 'environment.json'), 'readiness': readiness,
                      'tools': {k: v['ready'] for k, v in manifest['tools'].items()}}, indent=2))


if __name__ == '__main__':
    main()
