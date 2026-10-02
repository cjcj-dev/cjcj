#!/usr/bin/env python3
"""One bounded LLDB launch; no retries or product state construction."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

from reuse import select, validate_modules, native_dependency

HERE = Path(__file__).resolve().parent
OUT = Path(os.environ['RUNNER_TEMP']) / 'signal-observation'
OUT.mkdir(parents=True, exist_ok=True)


def digest(path):
    with open(path, 'rb') as f:
        h = hashlib.sha256()
        for chunk in iter(lambda: f.read(1024 * 1024), b''):
            h.update(chunk)
        return h.hexdigest()


def command(argv, log, timeout=120, env=None):
    start = time.monotonic()
    with open(log, 'w') as f:
        try:
            rc = subprocess.run(argv, stdout=f, stderr=subprocess.STDOUT, env=env, timeout=timeout).returncode
        except subprocess.TimeoutExpired:
            rc = 124
    Path(str(log) + '.rc').write_text(str(rc) + '\n')
    Path(str(log) + '.wall').write_text(str(time.monotonic() - start) + '\n')
    return rc


def observe(binary, mode, size=0, entity_root=None):
    name = 'calibration' if mode == 'calibrate' else 'product-' + str(size)
    cfg = {'binary': str(binary), 'binary_sha256': digest(binary), 'mode': mode,
           'selected_size': size, 'cwd': str(OUT), 'argv': [] if mode == 'calibrate' else ['--version'],
           'stdout': str(OUT / (name + '.stdout')), 'stderr': str(OUT / (name + '.stderr')),
           'output': str(OUT / (name + '.json')),
           'environment': {'HOME': os.environ['HOME'], 'TMPDIR': os.environ.get('TMPDIR', '/tmp'),
                           'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'},
           'layout': None, 'expected_libraries': {}}
    if mode == 'product':
        calibration = json.loads((OUT / 'calibration.json').read_text())
        assert calibration['status'] == 'CALIBRATED'
        cfg['layout'] = calibration['config']['layout']
        if entity_root is None:
            work = Path(os.environ['CANGJIE_WORKSPACE']) / 'bootstrap-work'
            sdk = work / 'sdk-stage0'
            host = Path(os.environ['CJCJ_BOOTSTRAP_HOST_RT'])
            tuple_ = os.environ['HOST_TUPLE']
            cfg['environment'].update(CANGJIE_HOME=str(sdk), DYLD_LIBRARY_PATH=':'.join([
                str(host / 'lib' / tuple_), str(sdk / 'runtime/lib' / tuple_),
                str(sdk / 'lib' / tuple_), str(sdk / 'third_party/llvm/lib')]))
            cfg['expected_libraries'] = {n: digest(host / 'lib' / tuple_ / n)
                for n in ('libcangjie-runtime.dylib', 'libboundscheck.dylib')}
        else:
            selection = select(entity_root)
            if str(binary.resolve()) != selection['binary']:
                raise ValueError('candidate-path')
            cfg['environment'].update(selection['environment'])
            cfg['expected_libraries'] = selection['expected_libraries']
            (OUT / 'run-input-receipt.json').write_text(json.dumps(selection, indent=2) + '\n')
    config = OUT / (name + '.config.json')
    config.write_text(json.dumps(cfg, indent=2))
    env = dict(os.environ, SIGNAL_OBSERVER_CONFIG=str(config))
    rc = command(['/usr/bin/lldb', '--batch', '-o', 'command script import ' + str(HERE / 'observer.py'),
                  '-o', 'signal-observe'], OUT / (name + '.lldb.log'), env=env)
    if rc != 0 or not Path(cfg['output']).is_file():
        raise SystemExit('OBSERVER_UNQUALIFIED LLDB rc=' + str(rc))
    result = json.loads(Path(cfg['output']).read_text())
    if mode == 'product' and entity_root is not None:
        validate_modules(result, selection)
    print(name, result['status'], flush=True)
    return result


def main():
    if sys.argv[1] == 'calibrate':
        sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
        info = {'sdkroot': sdk, 'source_sha256': digest(HERE / 'calibrate.c'),
                'observer_sha256': digest(HERE / 'observer.py'),
                'runner': subprocess.check_output(['uname', '-a'], text=True),
                'xcode': subprocess.check_output(['xcodebuild', '-version'], text=True)}
        (OUT / 'sdk.json').write_text(json.dumps(info, indent=2))
        # Record the SDK definitions and ABI-bearing clang output before running.
        headers = sorted(Path(sdk).glob('usr/include/**/signal.h'))
        with open(OUT / 'sdk-signal-definitions.txt', 'w') as f:
            for path in headers:
                lines = path.read_text(errors='replace').splitlines()
                for i, line in enumerate(lines):
                    if any(word in line for word in ('ss_sp', 'ss_size', 'ss_flags', 'SIGSTKSZ', 'SS_DISABLE', 'SS_ONSTACK')):
                        f.write(f'{path}:{i+1}: {line}\n')
        clang_path = subprocess.check_output(['xcrun', '--find', 'clang'], text=True).strip()
        clang = [os.environ['SCCACHE_PATH'], clang_path, '-isysroot', sdk, '-arch', 'arm64', '-g', '-O0']
        rc = command(clang + [str(HERE / 'calibrate.c'), '-o', str(OUT / 'calibrator')], OUT / 'calibrator-build.log')
        if rc: raise SystemExit('calibrator build failed')
        rc = command(['otool', '-tvV', str(OUT / 'calibrator')], OUT / 'calibrator-assembly.txt')
        if rc: raise SystemExit('ABI assembly failed')
        command(['file', str(OUT / 'calibrator')], OUT / 'calibrator.file')
        result = observe(OUT / 'calibrator', 'calibrate')
        if result['status'] != 'CALIBRATED': raise SystemExit('stop: calibration unqualified')
    elif sys.argv[1] == 'reuse-product':
        selection = select(os.environ['SIGNAL_ENTITY_ROOT'])
        dependency = native_dependency()
        (OUT / 'native-dependency.json').write_text(json.dumps(dependency, indent=2) + '\n')
        result = observe(Path(selection['binary']), 'product', 131072, os.environ['SIGNAL_ENTITY_ROOT'])
        if result['status'] != 'INSTALLED' or result.get('process_rc') != 0:
            raise SystemExit(20)
        # Deliberately ends here: no helper, old-size build, or second launch.
    elif sys.argv[1] == 'product':
        result = observe(Path(sys.argv[2]), 'product', int(sys.argv[3]))
        # Only an observed successful install permits the old-size product arm.
        if result['status'] != 'INSTALLED' or result.get('process_rc') != 0:
            raise SystemExit(20)
    else:
        raise SystemExit('unknown stage')


if __name__ == '__main__':
    main()
