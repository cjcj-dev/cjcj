#!/usr/bin/env python3
"""Read back the reviewed envelope; never launch the calibration helper."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

HERE = Path(__file__).resolve().parent
OUT = Path(os.environ['RUNNER_TEMP']) / 'signal-observation'
OUT.mkdir(parents=True, exist_ok=True)
reviewed = OUT / 'reviewed-calibration'
pin = json.loads((HERE / 'reviewed_calibration.json').read_text())
record = {'status': 'NOT_ADMITTED', 'reviewed_run': pin['run_id'],
          'reviewed_artifact': pin['artifact_id'], 'native_helper_launches': 0}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(argv):
    result = subprocess.run(argv, capture_output=True, text=True)
    record[' '.join(argv)] = {'rc': result.returncode, 'stdout': result.stdout,
                             'stderr': result.stderr}
    if result.returncode:
        raise RuntimeError('identity command failed: ' + ' '.join(argv))
    return result.stdout


try:
    assert read(['uname', '-s']).strip() == 'Darwin', 'OS mismatch'
    assert read(['uname', '-r']).strip() == '24.6.0', 'Darwin version mismatch'
    assert read(['uname', '-m']).strip() == 'arm64', 'architecture mismatch'
    assert read(['xcodebuild', '-version']) == 'Xcode 16.4\nBuild version 16F6\n', 'Xcode mismatch'
    assert read(['/usr/bin/lldb', '--version']) == (
        'lldb-1700.0.9.502\nApple Swift version 6.1.2 '
        '(swiftlang-6.1.2.1.2 clang-1700.0.13.5)\n'), 'LLDB mismatch'
    record['sdkroot'] = read(['xcrun', '--show-sdk-path']).strip()
    record['sdk_version'] = read(['xcrun', '--show-sdk-version']).strip()
    for name, expected in pin['frozen_sources'].items():
        assert digest(HERE / name) == expected, 'frozen source mismatch: ' + name
    for name, expected in pin['files'].items():
        assert digest(reviewed / name) == expected, 'reviewed entity mismatch: ' + name
    identity = json.loads((reviewed / 'identity.json').read_text())
    assert record['sdkroot'] == identity['sdkroot'], 'SDK path mismatch'
    calibration = json.loads((reviewed / 'calibration.json').read_text())
    assert calibration['status'] == 'CALIBRATED' and calibration['process_rc'] == 0
    record['layout'] = calibration['config']['layout']
    # The frozen product driver consumes only this original layout/qualification.
    # Copy the receipt verbatim; do not rewrite historical paths or observations.
    shutil.copyfile(reviewed / 'calibration.json', OUT / 'calibration.json')
    record['source_pins'] = {str(p): {'sha256': digest(p), 'text': p.read_text()}
                             for p in [Path('ci/host_sdk_pin.env'), Path('ci/llvm_pin.env'),
                                       Path('ci/source_pin.env'), Path('ci/runtime_pin.env')]
                             if p.is_file()}
    record['status'] = 'ADMITTED'
except Exception as exc:
    record['error'] = str(exc)
finally:
    (OUT / 'admission.json').write_text(json.dumps(record, indent=2) + '\n')
print(record['status'], record.get('error', ''), flush=True)
if record['status'] != 'ADMITTED':
    raise SystemExit(1)
