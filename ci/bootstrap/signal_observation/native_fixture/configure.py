#!/usr/bin/env python3
"""Prepare an independent config from a future build receipt. Never launches LLDB.
Source-preparation draft: all qualification tests remain NOT_RUN.
"""
import hashlib
import json
from pathlib import Path
import sys


def require(condition, reason):
    if not condition:
        raise ValueError(reason)


def entity(item, reason):
    path = Path(item['path'])
    require(path.is_absolute() and path.is_file(), reason + '-path')
    require(hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256'], reason + '-hash')
    return str(path.resolve())


def configure(receipt, calibration, output):
    require(receipt['schema'] == '473-native-fixture-v1', 'receipt-schema')
    require(receipt['status'] == 'BUILT' and receipt['build_rc'] == 0, 'not-built')
    require(receipt['seed_size'] == 65536 and receipt['selected_size'] == 131072, 'input-size')
    require(receipt['source_base'] == '8b9d9b79832965da76208b00f814aad65090a65f', 'source-base')
    require(len(receipt['fixture_source_head']) == 40, 'fixture-source-head')
    require(receipt['launch_rc'] is None, 'already-launched')
    require(receipt['compilation_sdk'] == receipt['process_sdk'], 'sdk-mismatch')
    require(receipt['compilation_sdk']['kind'] == 'official-complete', 'sdk-kind')
    require(receipt['qualification']['unique_product_entry'] is True, 'entry-not-unique')
    require(receipt['qualification']['normal_n2c_bridge'] is True, 'bridge-unqualified')
    require(receipt['qualification']['no_lto'] is True, 'lto-unqualified')
    for group in ('manifests', 'source_inventory', 'generated_wrappers', 'libraries', 'sdk_entities'):
        require(bool(receipt[group]), 'missing-' + group)
        for item in receipt[group]:
            entity(item, group)
    observer = entity(receipt['observer'], 'observer')
    require(receipt['observer']['sha256'] == json.loads(
        (Path(__file__).parent / 'source-identity.json').read_text())['observer_sha256'], 'observer-source')
    binary = entity({'path': receipt['binary'], 'sha256': receipt['binary_sha256']}, 'binary')
    require(receipt['binary_sha256'] != '3bee36eb5a9b4c17355bad296c7a4e4e2304f07a36f8cfd9b94ecc2fa014d254', 'retained-cjc')
    require(calibration['status'] == 'CALIBRATED', 'calibration')
    expected = {}
    directories = []
    for item in receipt['modules']:
        path = entity(item, 'module')
        expected[Path(path).name] = item['sha256']
        directories.append(str(Path(path).parent))
    require({'libcangjie-runtime.dylib', 'libboundscheck.dylib'} <= expected.keys(), 'runtime-modules')
    require(len(expected) == len(receipt['modules']), 'duplicate-module')
    require(output.is_absolute() and output.is_dir(), 'output-path')
    environment = dict(receipt['environment'])
    require({'HOME', 'TMPDIR', 'PATH', 'CANGJIE_HOME'} <= environment.keys(), 'environment')
    environment['DYLD_LIBRARY_PATH'] = ':'.join(dict.fromkeys(directories))
    config = dict(mode='product', selected_size=131072, binary=binary,
                  binary_sha256=receipt['binary_sha256'], cwd=str(output), argv=[],
                  stdout=str(output / 'fixture.stdout'), stderr=str(output / 'fixture.stderr'),
                  output=str(output / 'fixture.json'), environment=environment,
                  layout=calibration['config']['layout'], expected_libraries=expected)
    return config, observer


if __name__ == '__main__':
    receipt = json.loads(Path(sys.argv[1]).read_text())
    calibration = json.loads(Path(sys.argv[2]).read_text())
    output = Path(sys.argv[3])
    config, observer = configure(receipt, calibration, output)
    (output / 'fixture.config.json').write_text(json.dumps(config, indent=2) + '\n')
    (output / 'fixture.input-receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    # An argv draft is an artifact; this program does not execute it.
    (output / 'observer.argv.json').write_text(json.dumps([
        '/usr/bin/lldb', '--batch', '-o', 'command script import ' + observer,
        '-o', 'signal-observe'], indent=2) + '\n')
